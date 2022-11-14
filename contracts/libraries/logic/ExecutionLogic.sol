// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../Types.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {PercentageMath} from "node_modules/@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";

/**
 * @title Execution Libraries
 * @author Flaex
 * @notice Implements the logic for long/short execution
 */

library ExecutionLogic {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;
  using PercentageMath for uint256;
  using SafeCast for uint256;

  /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

  // direction

  /**
   * @dev we need to self-accrue interest to our users
   * @param position position
   */
  function executeAccrue(IPool L1Pool, Types.orderInfo storage position) external {
    uint256 oldATokenAmount = position.aTokenAmount;
    uint256 oldATokenIndex = position.aTokenIndex;

    uint256 oldDebtTokenAmount = position.debtTokenAmount;
    uint256 oldDebtTokenIndex = position.debtTokenIndex;

    uint256 newATokenAmount = 0;
    uint256 newDebtTokenAmount = 0;

    // get new Indexes:
    if (oldATokenAmount != 0) {
      //get new borrowIndex, should get normalizedIncome here because of real-time
      uint256 newATokenIndex = L1Pool.getReserveNormalizedIncome(position.aTokenAddress);

      newATokenAmount = oldATokenAmount * (newATokenIndex.rayDiv(oldATokenIndex));
      (position.aTokenIndex, position.aTokenAmount) = (newATokenIndex, newATokenAmount);
    }

    if (oldDebtTokenAmount != 0) {
      uint256 newDebtTokenIndex = L1Pool.getReserveNormalizedVariableDebt(position.debtTokenAddress);

      newDebtTokenAmount = oldDebtTokenAmount * (newDebtTokenIndex.rayDiv(oldDebtTokenIndex));
      (position.debtTokenIndex, position.debtTokenAmount) = (newDebtTokenIndex, newDebtTokenAmount);
    }
  }

  /**
   * @dev execute open order
   *
   */
  function executeOpenExactInput(
    address Vault,
    // IPool AavePool,
    IUniswapV3Factory UniFactory,
    Types.executeOpen memory params // Types.tradingPairInfo storage position
  ) external {
    // transfer from msg.sender directly to Vault ignoring address(this)
    IERC20(params.baseToken).safeTransferFrom(msg.sender, Vault, params.baseMargin);

    // borrowFlashAmount = baseMargin * marginLevel
    uint256 borrowFlashAmount = params.baseMargin.percentMul(params.marginLevel);

    IUniswapV3Pool UniPool = IUniswapV3Pool(UniFactory.getPool(params.baseToken, params.quoteToken, params.uniFee));

    //(int256 amount0Delta, int256 amount1Delta) = UniPool.swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, data);
    // amountSpecified: positive for exactInput, negative for exactOutput
    // amountSpecified = -amountOut.toInt(256) = -borrowFlashAmount
    // sqrtPriceLimitX96:
    /**
      sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96
     */

    /**
      uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

      require(amountIn <= params.amountInMaximum, 'Too much requested');

     */

    // initialize Flash
    bool zeroForOne = params.baseToken > params.quoteToken;
    uint160 sqrtPriceLimitX96 = (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1);

    bytes memory data = abi.encode(params, msg.sender, Types.DIRECTION.OPEN);

    (int256 amount0Delta, int256 amount1Delta) = UniPool.swap(
      address(this),
      zeroForOne,
      -borrowFlashAmount.toInt256(),
      sqrtPriceLimitX96,
      data
    );

    uint256 amountOutReceived;
    (, amountOutReceived) = zeroForOne
      ? (uint256(amount0Delta), uint256(-amount1Delta))
      : (uint256(amount1Delta), uint256(-amount0Delta));

    // it's technically possible to not receive the full output amount,
    // so if no price limit has been specified, require this possibility away
    if (sqrtPriceLimitX96 == 0) require(amountOutReceived == borrowFlashAmount);
  }
}

/**
 struct orderInfo {
    address aTokenAddress;
    uint256 aTokenAmount;
    uint256 aTokenIndex;
    address debtTokenAddress;
    uint256 debtTokenAmount;
    uint256 debtTokenIndex;
    uint256 rewards;

  struct executeOpen {
    address baseToken;
    address quoteToken;
    uint256 baseMargin;
    uint256 maxQuoteTokenAmount;
    uint24 uniFee;
    uint256 marginLevel;
    uint256 maxMarginLevel;
  }
  } */
