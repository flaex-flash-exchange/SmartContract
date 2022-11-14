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

library SwapCallback {
  function OpenCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    Types.executeOpen memory params,
    Types.tradingPairInfo storage position
  ) external {
    /**
      tokenIn = quoteToken
      tokenOut = baseToken

      (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
      ? (tokenIn < tokenOut, uint256(amount0Delta))
      : (tokenOut < tokenIn, uint256(amount1Delta));
      */

    (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
      ? (params.quoteToken < params.baseToken, uint256(amount0Delta))
      : (params.baseToken < params.quoteToken, uint256(amount1Delta));
  }
}
