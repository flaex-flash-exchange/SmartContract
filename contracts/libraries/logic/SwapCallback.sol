// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {Types} from "../Types.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {UpdateState} from "../updateState/UpdateState.sol";

import "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

library SwapCallback {
  using GPv2SafeERC20 for IERC20;
  using PercentageMath for uint256;
  using UpdateState for Types.orderInfo;

  // prettier-ignore
  event openOrder(address indexed trader, address baseToken, address quoteToken, uint256 baseMarginAmount, uint256 marginLevel, uint baseTokenAmount, uint quoteTokenAmount);

  function OpenCallback(
    IAddressesProvider FLAEX_PROVIDER,
    address trader,
    int256 amount0Delta,
    int256 amount1Delta,
    Types.executeOpen memory params,
    Types.orderInfo storage position
  ) external returns (Types.orderInfo memory) {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IVault Vault = IVault(FLAEX_PROVIDER.getVault());

    // bytes memory encodedParams = params.baseToken < params.quoteToken
    //   ? abi.encode(params.baseToken, params.quoteToken)
    //   : abi.encode(params.quoteToken, params.baseToken);

    // bytes memory encodedParams = abi.encode(zeroAsset, firstAsset);

    // call Supply() onBehalfOf to supply baseToken
    uint256 amountToSupply = params.baseMarginAmount + params.baseMarginAmount.percentMul(params.marginLevel);
    AaveL1Pool.supply(params.baseToken, amountToSupply, address(Vault), params.AaveReferralCode);

    // calculate borrow amount (amountToBorrow = amountToPay)
    (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
      ? (params.baseToken < params.quoteToken, uint256(amount0Delta))
      : (params.quoteToken < params.baseToken, uint256(amount1Delta));

    // require amountToBorrow to be less than or equal to maxQuoteTokenAmount
    require(amountToPay <= params.maxQuoteTokenAmount, "Too_Little_Input_Amount");

    // calculate final borrow amount (borrow amount + fee)
    uint256 fee = amountToPay.percentMul(params.tradingFee);
    uint256 amountToBorrow = amountToPay + fee;

    // call Borrow() on amountToBorrow to borrow quoteToken
    // is there any restrictions to user's opening orders?
    AaveL1Pool.borrow(
      params.quoteToken,
      amountToBorrow,
      params.AaveInterestRateMode,
      params.AaveReferralCode,
      address(Vault)
    );

    // transfer Fee to Vault by calling Vault's transferFeeToVault()
    Vault.transferFeeToVault(params.quoteToken, address(this), fee);

    // repay Flash
    if (!isExactInput) {
      IERC20(params.quoteToken).safeTransfer(msg.sender, amountToPay);
    }

    // write to storage
    DataTypes.ReserveData memory Reserve = AaveL1Pool.getReserveData(params.baseToken);

    /**
     * aTokenAddress is aToken of baseToken
     * aTokenAmount is amountToSupply
     * aTokenIndex is current LiquidityIndex
     * debtTokenAddress is debtToken of quoteToken (variable or stable depends on AaveInterestRateMode),
     * however, we do not support stable debt!
     * debtTokenAmount is amountToBorrow
     * debtTokenIndex is current variableBorrowIndex, which implies no stable debt supported!
     * rewards is in case Aave opens liquidity mining program, currently off
     */

    // prettier-ignore
    emit openOrder(trader, params.baseToken, params.quoteToken, params.baseMarginAmount, params.marginLevel, amountToSupply, amountToBorrow);

    return UpdateState.updateOpenState(amountToSupply, amountToBorrow, position, Reserve);
  }
}
