// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IInvestor} from "../interfaces/IInvestor.sol";
import {IVault} from "../interfaces/IVault.sol";
import {InvestorStorage} from "../storage/InvestorStorage.sol";
import {IFlToken} from "../interfaces/IFlToken.sol";

import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

/**  
  * @title User's main Interaction Point when providing liquidity
  * @author Flaex
  * @notice User can:
    - Provide single asset to ensure Protocol's safety and earn real yield from trading fee
    - Claim yield generated
    - Withdraw asset
  * @dev Pretty short contract so we try to wrap things up
 */

contract Investor is InvestorStorage, IInvestor, ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 internal constant MAX_INT = type(uint256).max;

  /// @dev only Admin can call
  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getSuperAdmin(), "Invalid_Admin");
  }

  /**
   * @dev Constructor.
   * @param provider The address of the IAddressesProvider contract
   */
  constructor(IAddressesProvider provider) {
    FLAEX_PROVIDER = provider;
  }

  function initialize(address newAcceptedAsset, string memory newAcceptedAssetSymbol) external onlyAdmin {
    _acceptedAsset = newAcceptedAsset;
    _acceptedAssetSymbol = newAcceptedAssetSymbol;
    _AaveReferralCode = 0;

    emit acceptedAssetSet(_acceptedAsset);
  }

  /// @inheritdoc IInvestor
  function getAcceptedAsset() public view virtual override returns (address, string memory) {
    return (_acceptedAsset, _acceptedAssetSymbol);
  }

  /// @inheritdoc IInvestor
  function provide(uint256 amount) external virtual override {
    /// should implement a supply cap in order to secure investor's profit
    _supplyCap();

    IERC20(_acceptedAsset).safeTransferFrom(msg.sender, address(this), amount);

    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    // call supply on behalf of Vault
    AaveL1Pool.supply(_acceptedAsset, amount, FLAEX_PROVIDER.getVault(), _AaveReferralCode);

    // check if balance is > 0, if > 0: claim rewards
    if (IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(msg.sender) > 0) {
      // claim rewards first
      _claimYieldInternal(msg.sender);
    } else {
      _Investor[msg.sender].supplyIndex = AaveL1Pool.getReserveNormalizedIncome(_acceptedAsset);
      address[] memory activeAssets = IVault(FLAEX_PROVIDER.getVault()).getActiveAssets();

      for (uint8 i = 0; i < activeAssets.length; i++) {
        (uint256 currentFlIndex, , ) = IVault(FLAEX_PROVIDER.getVault()).getYieldInfo(activeAssets[i]);
        _Investor[msg.sender].Yield[activeAssets[i]] = currentFlIndex;
      }
    }

    // mint flToken/supplyIndex to msg.sender
    uint256 amountToMint = amount.rayDiv(_Investor[msg.sender].supplyIndex);
    IFlToken(FLAEX_PROVIDER.getFlToken()).mint(msg.sender, amountToMint);

    emit AssetProvided(msg.sender, _acceptedAsset, amountToMint);
  }

  /// @inheritdoc IInvestor
  function claimYield() external virtual override nonReentrant {
    uint256 oldSupplyIndex = _Investor[msg.sender].supplyIndex;

    uint256 currentSupplyIndex = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool())
      .getReserveNormalizedIncome(_acceptedAsset);

    require(oldSupplyIndex != currentSupplyIndex, "Invalid_Same_Block");
    require(IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(msg.sender) > 0);

    _claimYieldInternal(msg.sender);
  }

  /// @inheritdoc IInvestor
  function withdraw(uint256 amount) external virtual override nonReentrant returns (uint256) {
    require(amount <= IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(msg.sender), "Invalid_Withdraw_Amount");

    // claim rewards
    _claimYieldInternal(msg.sender);

    uint256 currentSupplyIndex = _Investor[msg.sender].supplyIndex;
    uint256 amountToBurn = IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(msg.sender).rayMul(currentSupplyIndex);

    // burn
    IFlToken(FLAEX_PROVIDER.getFlToken()).burn(msg.sender, amountToBurn);

    // call withdraw on Vault
    IVault(FLAEX_PROVIDER.getVault()).withdrawToInvestor(msg.sender, _acceptedAsset, amountToBurn);

    emit assetWithdrawn(msg.sender, _acceptedAsset, amountToBurn);

    return amountToBurn;
  }

  ////////////////////////////////////////////////// INTERNAL FUNCTIONS //////////////////////////////////////////////////

  /// @dev calculate supply cap eligibility
  function _supplyCap() internal view {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());

    (uint256 totalCollateralBase, , , , , uint256 healthFactor) = AaveL1Pool.getUserAccountData(
      FLAEX_PROVIDER.getVault()
    );

    /// @dev initial supply < 10 mil USD or healthFactor <= 2
    require(totalCollateralBase <= 10000000 * 1e8 || healthFactor <= WadRayMath.WAD * 2, "Too_Much_Supply_Already");
  }

  function _claimYieldInternal(address claimer) internal {
    address[] memory activeAssets = IVault(FLAEX_PROVIDER.getVault()).getActiveAssets();
    address[] memory claimedAssets;
    uint256[] memory yieldToClaim;

    for (uint8 i = 0; i < activeAssets.length; i++) {
      uint256 oldFlIndex = _Investor[claimer].Yield[activeAssets[i]];

      (uint256 currentFlIndex, , uint256 shareableAmount) = IVault(FLAEX_PROVIDER.getVault()).getYieldInfo(
        activeAssets[i]
      );

      //only claim and update when needed
      if (currentFlIndex > oldFlIndex) {
        yieldToClaim[i] = IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(claimer).rayMul(currentFlIndex - oldFlIndex);
        claimedAssets[i] = activeAssets[i];
        // just to be sure
        require(yieldToClaim[i] <= shareableAmount, "Invalid_Yield_To_Claim");
        // call transfer rewards on Vault
        IVault(FLAEX_PROVIDER.getVault()).claimYieldToInvestor(activeAssets[i], claimer, yieldToClaim[i]);

        _Investor[claimer].Yield[activeAssets[i]] = currentFlIndex;
      }
    }

    _Investor[claimer].supplyIndex = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool())
      .getReserveNormalizedIncome(_acceptedAsset);

    emit yieldClaimed(claimer, claimedAssets, yieldToClaim);
  }

  ////////////////////////////////////////////////// SHARE VIEW FUNCTIONS //////////////////////////////////////////////////

  /// @inheritdoc IInvestor
  function getInvestorBalance(address user) public view virtual override returns (uint256) {
    uint256 flTokenBalance = IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(user);
    uint256 currentSupplyIndex = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool())
      .getReserveNormalizedIncome(_acceptedAsset);

    return flTokenBalance.rayMul(currentSupplyIndex);
  }

  /// @inheritdoc IInvestor
  function getInvestorYield(address user) public view virtual override returns (address[] memory, uint256[] memory) {
    address[] memory activeAssets = IVault(FLAEX_PROVIDER.getVault()).getActiveAssets();
    uint256[] memory yieldToClaim;
    for (uint8 i = 0; i < activeAssets.length; i++) {
      uint256 oldFlIndex = _Investor[user].Yield[activeAssets[i]];
      (uint256 currentFlIndex, , ) = IVault(FLAEX_PROVIDER.getVault()).getYieldInfo(activeAssets[i]);

      yieldToClaim[i] = IFlToken(FLAEX_PROVIDER.getFlToken()).balanceOf(user).rayMul(currentFlIndex - oldFlIndex);
    }

    return (activeAssets, yieldToClaim);
  }
}
