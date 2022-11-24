// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {Types} from "../Types.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {UpdateState} from "../updateState/UpdateState.sol";

import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {PercentageMath} from "@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";

library SwapCallback {
  using GPv2SafeERC20 for IERC20;
  using PercentageMath for uint256;
  using UpdateState for Types.orderInfo;

  function OpenCallback(
    IAddressesProvider FLAEX_PROVIDER,
    int256 amount0Delta,
    int256 amount1Delta,
    address trader,
    Types.executeOpen memory params,
    mapping(address => mapping(bytes => Types.orderInfo)) storage position
  ) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IVault Vault = IVault(FLAEX_PROVIDER.getVault());

    /// @dev call Supply() onBehalfOf to supply baseToken
    uint256 amountToSupply = params.baseMarginAmount + params.baseMarginAmount.percentMul(params.marginLevel);
    AaveL1Pool.supply(params.baseToken, amountToSupply, address(Vault), params.AaveReferralCode);

    /// @dev calculate borrow amount (amountToBorrow = amountToPay)
    (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
      ? (params.baseToken < params.quoteToken, uint256(amount0Delta))
      : (params.quoteToken < params.baseToken, uint256(amount1Delta));

    /// @dev calculate final borrow amount (borrow amount + fee)
    uint256 fee = amountToPay.percentMul(params.tradingFee);
    uint256 amountToBorrow = amountToPay + fee;

    /// @dev require amountToBorrow to be less than or equal to maxQuoteTokenAmount
    require(amountToBorrow <= params.maxQuoteTokenAmount, "Too_Little_Input_Amount");

    /// @dev call Borrow() on amountToBorrow to borrow quoteToken
    /// @dev is there any restrictions to user's opening orders at this stage?
    AaveL1Pool.borrow(
      params.quoteToken,
      amountToBorrow,
      params.AaveInterestRateMode,
      params.AaveReferralCode,
      address(Vault)
    );

    /// @dev transfer Fee to Vault by calling Vault's transferFeeToVault()
    Vault.transferFeeToVault(params.quoteToken, fee, true);

    /// @dev repay Flash
    if (!isExactInput) {
      IERC20(params.quoteToken).safeTransfer(msg.sender, amountToPay);
    }

    /// @dev write to storage
    DataTypes.ReserveData memory baseTokenReserve = AaveL1Pool.getReserveData(params.baseToken);
    DataTypes.ReserveData memory quoteTokenReserve = AaveL1Pool.getReserveData(params.quoteToken);

    /**
     * aTokenAddress is aToken of baseToken
     * aTokenAmount is amountToSupply
     * aTokenIndex is current LiquidityIndex
     * debtTokenAddress is debtToken of quoteToken (variable or stable depends on AaveInterestRateMode),
     * however, we do not support stable debt!
     * debtTokenAmount is amountToBorrow
     * debtTokenIndex is current variableBorrowIndex, which implies no stable debt supported!
     */

    position[trader][abi.encode(params.baseToken, params.quoteToken)].updateOpenState(
      baseTokenReserve,
      quoteTokenReserve,
      amountToSupply,
      amountToBorrow
    );
  }

  function CloseCallback(
    IAddressesProvider FLAEX_PROVIDER,
    int256 amount0Delta,
    int256 amount1Delta,
    address trader,
    Types.executeClose memory params,
    mapping(address => mapping(bytes => Types.orderInfo)) storage position
  ) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IVault Vault = IVault(FLAEX_PROVIDER.getVault());

    /// @dev repay Debt with amountToFlash as param on behalf of Vault
    /// amountToRepay = amountToFlash = either amount0Delta or amount1Delta

    (bool isExactInput, uint256 amountToFlash, uint256 amountToPay) = amount0Delta > 0
      ? (params.baseToken < params.quoteToken, uint256(amount1Delta), uint256(amount0Delta))
      : (params.quoteToken < params.baseToken, uint256(amount0Delta), uint256(amount1Delta));

    /**
      (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
     */

    if (isExactInput) {
      /// calculate tradingFee first:
      uint256 fee = amountToFlash.percentMul(params.tradingFee);

      /// @dev calculate amount to repay debt
      /// @dev if amountToFlash (ie. amountToRepay) >= user's debt then withdraw 100% collateral
      (uint256 amountToRepayDebt, uint256 amountToWithdraw) = (amountToFlash - fee) >=
        position[trader][abi.encode(params.baseToken, params.quoteToken)].debtTokenAmount
        ? (
          position[trader][abi.encode(params.baseToken, params.quoteToken)].debtTokenAmount,
          position[trader][abi.encode(params.baseToken, params.quoteToken)].aTokenAmount
        )
        : (amountToFlash - fee, params.baseTokenAmount); // sub is safe here because of percentage math

      AaveL1Pool.repay(params.quoteToken, amountToRepayDebt, params.AaveInterestRateMode, address(Vault));

      /// @dev withdraw() needs to be called from Vault!
      Vault.withdrawFromVault(params.baseToken, amountToWithdraw);

      /// @dev repay Flash with amountToRepay
      IERC20(params.baseToken).safeTransfer(msg.sender, amountToPay);

      /// @dev transferFeeToVault, fee is on the amountToFlash
      Vault.transferFeeToVault(params.baseToken, fee, true);

      /// @dev transfer PnL (in both currencies)
      // baseToken
      if (amountToWithdraw > amountToPay) IERC20(params.baseToken).safeTransfer(trader, amountToWithdraw - amountToPay);
      // quoteToken
      if (amountToRepayDebt > position[trader][abi.encode(params.baseToken, params.quoteToken)].debtTokenAmount)
        IERC20(params.quoteToken).safeTransfer(
          trader,
          amountToRepayDebt - position[trader][abi.encode(params.baseToken, params.quoteToken)].debtTokenAmount
        );

      /// @dev write to storage
      // DataTypes.ReserveData memory baseTokenReserve = AaveL1Pool.getReserveData(params.baseToken);
      // DataTypes.ReserveData memory quoteTokenReserve = AaveL1Pool.getReserveData(params.quoteToken);

      /**
       * aTokenAddress is aToken of baseToken
       * aTokenAmount decreases by amountToWithdraw
       * aTokenIndex is current LiquidityIndex
       * debtTokenAddress is debtToken of quoteToken (variable or stable depends on AaveInterestRateMode),
       * however, we do not support stable debt!
       * debtTokenAmount decreases by amountToRepayDebt
       * debtTokenIndex is current variableBorrowIndex, which implies no stable debt supported!
       */

      if (amountToRepayDebt >= position[trader][abi.encode(params.baseToken, params.quoteToken)].debtTokenAmount) {
        delete position[trader][abi.encode(params.baseToken, params.quoteToken)];
      } else {
        position[trader][abi.encode(params.baseToken, params.quoteToken)].updateCloseState(
          amountToWithdraw,
          amountToRepayDebt
        );
      }
    }
  }
}
