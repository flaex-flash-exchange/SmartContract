// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

//flaex Stuff
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ExecutionLogic} from "../libraries/logic/ExecutionLogic.sol";
import {UpdateMarket} from "../libraries/logic/UpdateMarket.sol";
import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";
import {MainStorage} from "../storage/MainStorage.sol";
import {IMain} from "../interfaces/IMain.sol";
import {Types} from "../libraries/Types.sol";
import {Vault} from "../vault/Vault.sol";
import {ValidationLogic} from "../libraries/logic/ValidationLogic.sol";

//Aave Stuff:
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

//UniSwap Stuff
import {PeripheryPayments} from "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";

//Other Stuff

/**  
  * @title User's main Interaction Point
  * @author Flaex
  * @notice User can:
    - Open/Close Long/Short
    - Supply extra Stable Coin
    - Liquidate others
  * @dev Admin functions callable as defined in AddressesProvider
 */

// contract Main is ReentrancyGuard, IUniswapV3SwapCallback, PeripheryPayments {
contract Main is MainStorage, IMain, IUniswapV3SwapCallback, ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 MAX_INT = type(uint256).max;

  //only Admin can call
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
    FLAEX_PROVIDER = IAddressesProvider(provider);
  }

  // Initialize basic configuration
  function initialize() external onlyAdmin {
    _AaveReferralCode = 0;
    _AaveInterestRateMode = 2; //None: 0, Stable: 1, Variable: 2

    _AaveAddressProvider = IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider());
    _AavePool = IL2Pool(_AaveAddressProvider.getPool());
    _AaveL1Pool = IPool(_AaveAddressProvider.getPool());
    _AaveEncoder = L2Encoder(FLAEX_PROVIDER.getAaveEncoder());

    _UniFactory = IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory());
  }

  /**
   * @dev basic Aprrove market, which is to:
    - approve Lending Pool to spend our asset & aToken
    - set used as collateral
   * @inheritdoc IMain
   */
  function basicApprove(
    address zeroAsset,
    address firstAsset,
    uint24 uniFee
  ) external virtual override onlyAdmin {
    UpdateMarket.executeInitMarket(zeroAsset, firstAsset, _AavePool, _AaveL1Pool, _AaveEncoder, _UniFactory, uniFee);
  }

  /**
   * @dev init/update Market
   * @inheritdoc IMain
   */
  function updateMarket(
    address Asset0,
    address Asset1,
    uint256 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare
  ) external virtual override onlyAdmin {
    //in-line with uniswap
    (address zeroAsset, address firstAsset) = Asset0 < Asset1 ? (Asset0, Asset1) : (Asset1, Asset0);

    if (
      !(
        UpdateMarket.executeUpdateMarket(
          _tradingPair,
          _tradingPairList,
          Types.tradingPairInfo({
            id: _tradingPairCount,
            zeroToken: zeroAsset,
            firstToken: firstAsset,
            tradingFee: tradingFee,
            tradingFee_ProtocolShare: tradingFee_ProtocolShare,
            liquidationThreshold: liquidationThreshold,
            liquidationProtocolShare: liquidationProtocolShare,
            isLive: true
          })
        )
      )
    ) {
      _tradingPairCount++;
    }
  }

  /**
   * @dev drop market, isLive -> False
   * @inheritdoc IMain
   */
  function dropMarket(address Asset0, address Asset1) external virtual override onlyAdmin {
    //in-line with uniswap
    (address zeroAsset, address firstAsset) = Asset0 < Asset1 ? (Asset0, Asset1) : (Asset1, Asset0);

    UpdateMarket.executeDropMarket(zeroAsset, firstAsset, _tradingPair);
  }

  /// @inheritdoc IMain
  function getAllMarkets() public view virtual override returns (address[] memory) {
    address[] memory allMarkets;

    for (uint256 i = 0; i < (_tradingPairCount - 1) * 2; i += 2) {
      (address zeroToken, address firstToken) = abi.decode(_tradingPairList[i / 2], (address, address));
      allMarkets[i] = zeroToken;
      allMarkets[i + 1] = firstToken;
    }

    return allMarkets;
  }

  /// @inheritdoc IMain
  // function accrueInterest(
  //   address user,
  //   address baseToken,
  //   address quoteToken
  // ) public virtual override {
  //   ExecutionLogic.executeAccrue(_AaveL1Pool, _position[user][asset]);
  // }

  /**
   * @notice open order
   * @dev technically there's only '1 side' of trading, ie: shorting eth/usdc meaning longing usdc/eth and so:
    - baseToken = collateral Token = aTokenAddress
    - quoteToken = borrow Token = debtTokenAddress
    - we don't need to check if Vault has enough collateral because AAVE Document quotes:
     + begin quote
       The delegatee cannot abuse credit approval to liquidate delegator i.e.
       if the borrow puts delegator's position in HF < HEALTH_FACTOR_LIQUIDATION_THRESHOLD, then borrow will fail.
     + end quote
   * @param baseToken base currency, ie: eth if open on eth/usdc
   * @param quoteToken quote currency, ie: usdc if open on eth/usdc
   * @param baseMargin initial margin, must be in base currency
   * @param maxQuoteTokenAmount maximum accepted output
   * @param uniFee either 500, 3000 or 10000 (0.05% - 0.3% - 0.1%), uint24
   * @param marginLevel margin level, scaled-up by wad (1e18)
   * @inheritdoc IMain
   */
  function openExactOutput(
    address baseToken,
    address quoteToken,
    uint256 baseMargin,
    uint256 maxQuoteTokenAmount,
    uint24 uniFee,
    uint256 marginLevel
  ) external virtual override nonReentrant {
    // elegibility check
    ValidationLogic.executeOpenCheck(
      FLAEX_PROVIDER,
      _tradingPair,
      Types.executeOpen({
        baseToken: baseToken,
        quoteToken: quoteToken,
        baseMargin: baseMargin,
        maxQuoteTokenAmount: maxQuoteTokenAmount,
        uniFee: uniFee,
        marginLevel: marginLevel,
        maxMarginLevel: _maxMarginLevel
      })
    );

    // accrue Interest
    bytes memory encodedParams = abi.encode(baseToken, quoteToken);

    if (
      _position[msg.sender][encodedParams].aTokenAmount != 0 ||
      _position[msg.sender][encodedParams].debtTokenAmount != 0
    ) {
      ExecutionLogic.executeAccrue(_AaveL1Pool, _position[msg.sender][encodedParams]);
    }
  }

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata _data
  ) external override {
    require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

    (Types.executeOpen memory params, address trader, Types.DIRECTION direction) = abi.decode(
      _data,
      (Types.executeOpen, address, Types.DIRECTION)
    );

    CallbackValidation.verifyCallback(address(_UniFactory), params.baseToken, params.quoteToken, params.uniFee);

    if (direction == Types.DIRECTION.OPEN) {}
  }

  receive() external payable {}
}
