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
import {SwapCallback} from "../libraries/logic/SwapCallback.sol";

//Aave Stuff:

//UniSwap Stuff
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";

//Other Stuff

/**  
  * @title User's main Interaction Point
  * @author Flaex
  * @notice User can:
    - Open/Close Long/Short
    - Repay partial Debt
    - Liquidate others
  * @dev Admin functions callable as defined in AddressesProvider
 */

contract Main is MainStorage, IMain, IUniswapV3SwapCallback, ReentrancyGuard {
  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 internal constant MAX_INT = type(uint256).max;

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
    FLAEX_PROVIDER = provider;
  }

  // Initialize basic configuration
  function initialize() external onlyAdmin {
    _AaveReferralCode = 0;
    _AaveInterestRateMode = 2; //None: 0, Stable: 1, Variable: 2
  }

  /**
   * @dev basic Aprrove market, which is to:
    - approve Lending Pool to spend our asset & aToken
    - set used as collateral
    - approve uniswap pool to spend our tokens
   * @inheritdoc IMain
   */
  function basicApprove(
    address zeroAsset,
    address firstAsset,
    uint24 uniFee
  ) external virtual override onlyAdmin {
    UpdateMarket.executeInitMarket(FLAEX_PROVIDER, zeroAsset, firstAsset, uniFee);
  }

  /**
   * @dev init/update Market
   * @inheritdoc IMain
   */
  function updateMarket(
    address Asset0,
    address Asset1,
    uint24 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare,
    uint256 maxMarginLevel
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
            maxMarginLevel: maxMarginLevel,
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
   * @param baseMarginAmount initial margin, must be in base currency
   * @param maxQuoteTokenAmount maximum accepted quoteToken In, needs to note that:
   * this only applies on the "borrowed" amount, not on the baseMargin
   * @param uniFee either 500, 3000 or 10000 (0.05% - 0.3% - 0.1%), uint24
   * @param marginLevel margin level, scaled-up by 1e2, ie. 100% = 100,00
   * @inheritdoc IMain
   */
  function openExactOutput(
    address baseToken,
    address quoteToken,
    uint256 baseMarginAmount,
    uint256 maxQuoteTokenAmount,
    uint24 uniFee,
    uint256 marginLevel
  ) external virtual override nonReentrant {
    ExecutionLogic.executeOpenExactOutput(
      FLAEX_PROVIDER,
      _tradingPair,
      _position[msg.sender][abi.encode(baseToken, quoteToken)],
      Types.executeOpen({
        baseToken: baseToken,
        quoteToken: quoteToken,
        baseMarginAmount: baseMarginAmount,
        maxQuoteTokenAmount: maxQuoteTokenAmount,
        tradingFee: 0, // needs to be updated
        uniFee: uniFee,
        AaveReferralCode: _AaveReferralCode,
        AaveInterestRateMode: _AaveInterestRateMode,
        marginLevel: marginLevel
      })
    );
  }

  /**
   * @notice close order
   * @dev closes order by selling collateral and repay debt. if after math, debt == 0 => withdraw 100% collateral
   * technically, we have to flash an estimated amount of quoteToken first, so there's chance a residue on quoteToken
   * amount will be left after repaying Flash. Then we need to handle this
   * @dev we also rely completely on our liquidation mechanism to 'not have to' check if user is in liquidation call
   * @param baseToken base currency, ie: eth if close on eth/usdc
   * @param quoteToken quote currency, ie: usdc if close on eth/usdc
   * @param baseTokenAmount amount wishes to close, type(uint256).max for 100% close
   * @param minQuoteTokenAmount minimum quote Token amount out accepted
   * @param uniFee either 500, 3000 or 10000 (0.05% - 0.3% - 0.1%), uint24
   * @inheritdoc IMain
   */
  function closeExactInput(
    address baseToken,
    address quoteToken,
    uint256 baseTokenAmount,
    uint256 minQuoteTokenAmount,
    uint24 uniFee
  ) external virtual override nonReentrant {
    ExecutionLogic.executeCloseExactInput(
      FLAEX_PROVIDER,
      _tradingPair,
      _position[msg.sender][abi.encode(baseToken, quoteToken)],
      Types.executeClose({
        baseToken: baseToken,
        quoteToken: quoteToken,
        baseTokenAmount: baseTokenAmount,
        minQuoteTokenAmount: minQuoteTokenAmount,
        tradingFee: 0,
        uniFee: uniFee,
        AaveInterestRateMode: _AaveInterestRateMode
      })
    );
  }

  /// @dev overridden function to be externally called from Uniswap Pool only
  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata _data
  ) external override {
    require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

    (
      Types.executeOpen memory openParams,
      Types.executeClose memory closeParams,
      address trader,
      Types.DIRECTION direction
    ) = abi.decode(_data, (Types.executeOpen, Types.executeClose, address, Types.DIRECTION));

    if (direction == Types.DIRECTION.OPEN) {
      /// @dev this is the call back verification to make sure msg.sender is Uniswap Pool
      CallbackValidation.verifyCallback(
        FLAEX_PROVIDER.getUniFactory(),
        openParams.baseToken,
        openParams.quoteToken,
        openParams.uniFee
      );

      SwapCallback.OpenCallback(FLAEX_PROVIDER, amount0Delta, amount1Delta, trader, openParams, _position);
    } else if (direction == Types.DIRECTION.CLOSE) {
      /// @dev this is the call back verification to make sure msg.sender is Uniswap Pool
      CallbackValidation.verifyCallback(
        FLAEX_PROVIDER.getUniFactory(),
        closeParams.baseToken,
        closeParams.quoteToken,
        closeParams.uniFee
      );

      SwapCallback.CloseCallback(FLAEX_PROVIDER, amount0Delta, amount1Delta, trader, closeParams, _position);
    }
  }

  receive() external payable {}
}
