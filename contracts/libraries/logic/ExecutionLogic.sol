// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IVault} from "../../interfaces/IVault.sol";
import {Types} from "../Types.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {ValidationLogic} from "../../libraries/logic/ValidationLogic.sol";
import {AccrueLogic} from "../../libraries/logic/AccrueLogic.sol";
import {UpdateState} from "../updateState/UpdateState.sol";

import "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";

import "../../dependencies/uniswap/v3-periphery/libraries/CallbackValidation.sol";
import {IUniswapV3Factory} from "../../dependencies/uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {SafeCast} from "../../dependencies/uniswap/v3-core/libraries/SafeCast.sol";

/**
 * @title Execution Libraries
 * @author Flaex
 * @notice Implements the logic for long/short/liquidation execution
 */

library ExecutionLogic {
  using GPv2SafeERC20 for IERC20;
  using PercentageMath for uint256;
  using SafeCast for uint256;
  using UpdateState for Types.orderInfo;

  // prettier-ignore
  event OrderOpened(address indexed trader, address baseToken, address quoteToken, uint256 baseMarginAmount, uint256 marginLevel, uint256 baseTokenAmount, uint256 quoteTokenAmount);
  // prettier-ignore
  event OrderClosed(address indexed trader, address baseToken, address quoteToken, uint256 baseTokenAmount, uint256 quoteTokenAmount);
  event repayPartialDebt(address indexed trader, address baseToken, address quoteToken, uint256 quoteTokenAmount);
  // prettier-ignore
  event liquidation(address indexed liquidatedUser, address baseToken, address quoteToken, uint256 baseTokenLiquidated, uint256 quoteTokenRepaid, uint256 liquidationIncentives);

  /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

  /** @dev execute open order
   */
  function executeOpenExactOutput(
    IAddressesProvider FLAEX_PROVIDER,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.orderInfo storage position,
    Types.executeOpen memory params
  ) external {
    IUniswapV3Pool UniPool = IUniswapV3Pool(
      IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory()).getPool(params.baseToken, params.quoteToken, params.uniFee)
    );

    /// @dev Validation
    params.tradingFee = ValidationLogic.executeOpenCheck(FLAEX_PROVIDER, tradingPair, params);

    /// @dev accrueInterest:
    if (position.aTokenAmount != 0 || position.debtTokenAmount != 0) {
      AccrueLogic.executeAccrue(FLAEX_PROVIDER, params.baseToken, params.quoteToken, position);
    }

    /// @dev transfer from msg.sender address(this)
    IERC20(params.baseToken).safeTransferFrom(msg.sender, address(this), params.baseMarginAmount);

    /// @dev amountToFlash = baseMargin * marginLevel
    uint256 amountToFlash = params.baseMarginAmount.percentMul(params.marginLevel);

    /// @dev initialize Flash
    bool zeroForOne = params.baseToken > params.quoteToken;

    bytes memory data = abi.encode(
      params,
      Types.executeClose({
        baseToken: address(0),
        quoteToken: address(0),
        baseTokenAmount: 0,
        minQuoteTokenAmount: 0,
        tradingFee: 0,
        uniFee: 0,
        AaveInterestRateMode: 0
      }),
      msg.sender,
      Types.DIRECTION.OPEN
    );

    (int256 amount0Delta, int256 amount1Delta) = UniPool.swap(
      address(this),
      zeroForOne,
      -amountToFlash.toInt256(),
      (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1),
      data
    );

    /// @dev it's technically possible to not receive the full output amount,
    /// @dev so if no price limit has been specified, require this possibility away
    zeroForOne ? require(uint256(-amount1Delta) == amountToFlash) : require(uint256(-amount0Delta) == amountToFlash);

    emit OrderOpened(
      msg.sender,
      params.baseToken,
      params.quoteToken,
      params.baseMarginAmount,
      params.marginLevel,
      params.baseMarginAmount + params.baseMarginAmount.percentMul(params.marginLevel),
      amount0Delta > 0
        ? uint256(amount0Delta) + uint256(amount0Delta).percentMul(params.tradingFee)
        : uint256(amount1Delta) + uint256(amount1Delta).percentMul(params.tradingFee)
    );
  }

  /** @dev execute close order
   */
  function executeCloseExactInput(
    IAddressesProvider FLAEX_PROVIDER,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.orderInfo storage position,
    Types.executeClose memory params
  ) external {
    IUniswapV3Pool UniPool = IUniswapV3Pool(
      IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory()).getPool(params.baseToken, params.quoteToken, params.uniFee)
    );

    /// @dev accrueInterest, this is a MUST DO FIRST, if either aTokenAmount or debtTokenAmount == 0 then revert.
    if (position.aTokenAmount == 0 || position.debtTokenAmount == 0) {
      revert("User_Has_No_Position");
    } else AccrueLogic.executeAccrue(FLAEX_PROVIDER, params.baseToken, params.quoteToken, position);

    /// @dev Validation, also needs to do sanity check on amount
    (params.tradingFee, params.baseTokenAmount) = ValidationLogic.executeCloseCheck(
      FLAEX_PROVIDER,
      tradingPair,
      position,
      params
    );

    /// @dev amountToFlash is an estimated amount only because of ExactInput Swap. If later on when the withdrawn amount
    /// of Debt Token (which is Exact) is not enough to repay Flash, function will fail
    /// amountToFlash != params.minQuoteTokenAmount, it is the result of the UniPool.swap()

    /// @dev initialize Flash
    bool zeroForOne = params.baseToken < params.quoteToken;

    bytes memory data = abi.encode(
      Types.executeOpen({
        baseToken: address(0),
        quoteToken: address(0),
        baseMarginAmount: 0,
        maxQuoteTokenAmount: 0,
        tradingFee: 0,
        uniFee: 0,
        AaveReferralCode: 0,
        AaveInterestRateMode: 0,
        marginLevel: 0
      }),
      params,
      msg.sender,
      Types.DIRECTION.CLOSE
    );

    uint256 previousDebtTokenAmount = position.debtTokenAmount;

    (int256 amount0, int256 amount1) = UniPool.swap(
      address(this),
      zeroForOne,
      params.baseTokenAmount.toInt256(),
      (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1),
      abi.encode(data)
    );

    require(uint256(-(zeroForOne ? amount1 : amount0)) >= params.minQuoteTokenAmount, "Too_Much_Output_Amount");

    emit OrderClosed(
      msg.sender,
      params.baseToken,
      params.quoteToken,
      params.baseTokenAmount,
      position.debtTokenAmount == 0
        ? previousDebtTokenAmount
        : uint256(-(zeroForOne ? amount1 : amount0)) -
          uint256(-(zeroForOne ? amount1 : amount0)).percentMul(params.tradingFee)
    );
  }

  function executeRepayPartial(
    IAddressesProvider FLAEX_PROVIDER,
    Types.orderInfo storage position,
    Types.executeRepayParital memory params
  ) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());

    /// @dev accrueInterest, this is a MUST DO FIRST, if either aTokenAmount or debtTokenAmount == 0 then revert.
    if (position.aTokenAmount == 0 || position.debtTokenAmount == 0) {
      revert("User_Has_No_Position");
    } else AccrueLogic.executeAccrue(FLAEX_PROVIDER, params.baseToken, params.quoteToken, position);

    /// @dev sanity check on amount, just as simple as amount < position.debtTokenAmount
    require(params.quoteTokenAmount < position.debtTokenAmount, "Cannot_Repay_Full");

    /// @dev transfer quoteTokenAmount from msg.sender to address(this)
    IERC20(params.quoteToken).safeTransferFrom(msg.sender, address(this), params.quoteTokenAmount);

    /// @dev repay debt
    AaveL1Pool.repay(
      params.quoteToken,
      params.quoteTokenAmount,
      params.AaveInterestRateMode,
      FLAEX_PROVIDER.getVault()
    );

    /// @dev write to storage
    // It is the same as updateCloseState, just with 0 as 1st parameter (since user doesn't withdraw collateral)
    position.updateCloseState(0, params.quoteTokenAmount);

    emit repayPartialDebt(msg.sender, params.baseToken, params.quoteToken, params.quoteTokenAmount);
  }

  /** @dev execute liquidation
   */
  function executeLiquidation(
    IAddressesProvider FLAEX_PROVIDER,
    address liquidatedUser,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.orderInfo storage position,
    Types.executeLiquidation memory params
  ) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());

    /// @dev accrueInterest, this is a MUST DO FIRST, if either aTokenAmount or debtTokenAmount == 0 then revert.
    if (position.aTokenAmount == 0 || position.debtTokenAmount == 0) {
      revert("User_Has_No_Position");
    } else AccrueLogic.executeAccrue(FLAEX_PROVIDER, params.baseToken, params.quoteToken, position);

    /// @dev validation, require aavePrice * 99% <= uniswapPrice < aavePrice
    uint256 amountToWithdrawExcludeIncentive = ValidationLogic.executeLiquidationCheck(
      FLAEX_PROVIDER,
      tradingPair,
      position,
      params
    );

    /// @dev transfer debtToCover from msg.sender to address(this)
    IERC20(params.quoteToken).safeTransferFrom(msg.sender, address(this), params.debtToCover);

    /// @dev repay Debt
    AaveL1Pool.repay(params.quoteToken, params.debtToCover, params.AaveInterestRateMode, FLAEX_PROVIDER.getVault());

    /// @dev withdraw amountToWithdrawExcludeIncentive + incentive
    uint256 liquidationIncentive = amountToWithdrawExcludeIncentive.percentMul(params.liquidationIncentive);

    uint256 amountToWithdrawIncludeIncentive = amountToWithdrawExcludeIncentive + liquidationIncentive;

    IVault(FLAEX_PROVIDER.getVault()).withdrawFromVault(params.baseToken, amountToWithdrawIncludeIncentive);

    /// @dev write to storage
    position.updateLiquidation(amountToWithdrawIncludeIncentive, params.debtToCover);

    /// @dev transfer liquidation incentives share to Vault
    uint256 liquidationProtocolShare = liquidationIncentive.percentMul(
      params.baseToken < params.quoteToken
        ? tradingPair[abi.encode(params.baseToken, params.quoteToken)].liquidationProtocolShare
        : tradingPair[abi.encode(params.quoteToken, params.baseToken)].liquidationProtocolShare
    );
    IVault(FLAEX_PROVIDER.getVault()).transferFeeToVault(params.baseToken, liquidationProtocolShare, false);

    /// @dev transfer liquidation incentives to liquidator
    IERC20(params.baseToken).safeTransfer(msg.sender, liquidationIncentive - liquidationProtocolShare);

    emit liquidation(
      liquidatedUser,
      params.baseToken,
      params.quoteToken,
      amountToWithdrawIncludeIncentive,
      params.debtToCover,
      liquidationIncentive
    );
  }
}
