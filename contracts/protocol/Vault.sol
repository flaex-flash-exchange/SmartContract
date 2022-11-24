// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";
import {VaultStorage} from "../storage/VaultStorage.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IInvestor} from "../interfaces/IInvestor.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IFlToken} from "../interfaces/IFlToken.sol";

import {ICreditDelegationToken} from "@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol";
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";

/**
 * @title Vault Contract
 * @author flaex
 * @notice Vault holds aToken, debtToken and assets
 * @dev Technically, we do not need to double-check the amounts between Main and Vault because we assume calculations
 * from Main is always correct. thus, any valid request from Main is accepted. is this a security threat?
 */

contract Vault is VaultStorage, IVault, ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 internal constant MAX_INT = type(uint256).max;

  /**
   * @dev Constructor.
   * @param provider The address of the IAddressesProvider contract
   */
  constructor(IAddressesProvider provider) {
    FLAEX_PROVIDER = provider;
  }

  /**
   * @dev Only Main can call functions marked by this modifier.
   **/
  modifier onlyMain() {
    _onlyMain();
    _;
  }

  /**
   * @dev Only Investor can call functions marked by this modifier.
   **/
  modifier onlyInvestor() {
    _onlyInvestor();
    _;
  }

  /**
   * @dev Only Admin can call functions marked by this modifier.
   **/
  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function _onlyMain() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getMain(), "Invalid_Main");
  }

  function _onlyInvestor() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getInvestor(), "Invalid_Investor");
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getSuperAdmin(), "Invalid_Admin");
  }

  ////////////////////////////////////////////////// ADMIN FUNCTIONS //////////////////////////////////////////////////

  function initVault() external onlyAdmin {
    _protocolShare = 2000; // 20%
    _AaveReferralCode = 0;
  }

  /// @inheritdoc IVault
  function setActiveAssets(address[] memory Assets) external virtual override onlyAdmin {
    _activeAssets = Assets;
  }

  /// @inheritdoc IVault
  function setUsedAsCollateral(address asset) external onlyAdmin {
    bytes32 encodedParams = L2Encoder(FLAEX_PROVIDER.getAaveEncoder()).encodeSetUserUseReserveAsCollateral(asset, true);
    IL2Pool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool()).setUserUseReserveAsCollateral(
      encodedParams
    );
  }

  /// @inheritdoc IVault
  function approveInvestor() external onlyAdmin {
    for (uint8 i = 0; i < _activeAssets.length; i++) {
      IERC20(_activeAssets[i]).approve(FLAEX_PROVIDER.getInvestor(), MAX_INT);
    }
  }

  /// @inheritdoc IVault
  function approveDelagationMain(address debtToken) external onlyAdmin {
    ICreditDelegationToken(debtToken).approveDelegation(FLAEX_PROVIDER.getMain(), MAX_INT);
  }

  ////////////////////////////////////////////////// INVESTOR FUNCTIONS //////////////////////////////////////////////////

  /// @inheritdoc IVault
  function withdrawToInvestor(
    address withdrawer,
    address asset,
    uint256 amount
  ) external override onlyInvestor nonReentrant {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    uint256 withdrawnAmount = AaveL1Pool.withdraw(asset, amount, withdrawer);
    assert(withdrawnAmount == amount);

    emit assetWithdrawn(asset, amount);
  }

  /// @inheritdoc IVault
  function claimYieldToInvestor(
    address asset,
    address claimer,
    uint256 amount
  ) external virtual override {
    // call transfer out
    IERC20(asset).safeTransfer(claimer, amount);

    // decrease Yield Amount
    _decreaseYield(asset, amount, false);
  }

  ////////////////////////////////////////////////// MAIN FUNCTIONS //////////////////////////////////////////////////

  /**
   * @dev transfer fee from Main to Vault, pull call because we need to seperate protocol fee from distributable fee
   * @inheritdoc IVault
   */
  function transferFeeToVault(
    address asset,
    uint256 amount,
    bool isShareable
  ) external override onlyMain {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    /// only share trading fee for open/close orders
    _increaseYield(asset, amount, isShareable);

    emit feeToVault(asset, amount, isShareable);
  }

  /// @inheritdoc IVault
  function withdrawFromVault(address asset, uint256 amount) external override onlyMain nonReentrant {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    uint256 withdrawnAmount = AaveL1Pool.withdraw(asset, amount, msg.sender);
    assert(withdrawnAmount == amount);

    emit assetWithdrawn(asset, amount);
  }

  ////////////////////////////////////////////////// SHARE VIEW FUNCTIONS //////////////////////////////////////////////////

  /// @inheritdoc IVault
  function getActiveAssets() public view virtual returns (address[] memory) {
    return _activeAssets;
  }

  /// @inheritdoc IVault
  function getYieldInfo(address asset)
    public
    view
    virtual
    override
    returns (
      uint256 flIndex,
      uint256 prototolAmount,
      uint256 shareableAmount
    )
  {
    flIndex = _yieldGenerated[asset].flIndex;
    prototolAmount = _yieldGenerated[asset].protocolAmount;
    shareableAmount = _yieldGenerated[asset].shareableAmount;
  }

  ////////////////////////////////////////////////// INTERNAL FUNCTIONS //////////////////////////////////////////////////
  function _increaseYield(
    address asset,
    uint256 amount,
    bool isShareable
  ) internal {
    uint256 oldFlIndex = _yieldGenerated[asset].flIndex;
    uint256 oldProtocolAmount = _yieldGenerated[asset].protocolAmount;
    uint256 oldShareableAmount = _yieldGenerated[asset].shareableAmount;

    uint256 newFlIndex = oldFlIndex + amount.rayDiv(IFlToken(FLAEX_PROVIDER.getFlToken()).totalSupply());
    uint256 newProtocolAmount;
    uint256 newShareableAmount;

    if (isShareable) {
      newProtocolAmount = amount.percentMul(_protocolShare);
      newShareableAmount = amount - amount.percentMul(_protocolShare);
    } else {
      newProtocolAmount = amount;
      newShareableAmount = 0;
    }

    _yieldGenerated[asset] = yieldInfo({
      flIndex: newFlIndex,
      protocolAmount: newProtocolAmount + oldProtocolAmount,
      shareableAmount: newShareableAmount + oldShareableAmount
    });
  }

  function _decreaseYield(
    address asset,
    uint256 amount,
    bool isProtocol
  ) internal {
    uint256 oldProtocolAmount = _yieldGenerated[asset].protocolAmount;
    uint256 oldShareableAmount = _yieldGenerated[asset].shareableAmount;

    if (isProtocol) {
      _yieldGenerated[asset].protocolAmount = oldProtocolAmount - amount;
    } else {
      _yieldGenerated[asset].shareableAmount = oldShareableAmount - amount;
    }
  }
}
