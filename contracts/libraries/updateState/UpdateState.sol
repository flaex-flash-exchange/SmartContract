// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {Types} from "../Types.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

library UpdateState {
  function updateOpenState(
    Types.orderInfo storage position,
    DataTypes.ReserveData memory baseTokenReserve,
    DataTypes.ReserveData memory quoteTokenReserve,
    uint256 amountToSupply,
    uint256 amountToBorrow
  ) external {
    position.aTokenAddress = baseTokenReserve.aTokenAddress;
    position.aTokenAmount += amountToSupply;
    position.aTokenIndex = baseTokenReserve.liquidityIndex;
    position.debtTokenAddress = quoteTokenReserve.variableDebtTokenAddress;
    position.debtTokenAmount += amountToBorrow;
    position.debtTokenIndex = quoteTokenReserve.variableBorrowIndex;
  }

  /// @dev we do not need to update addresses because we assume validation check is legit
  function updateCloseState(
    Types.orderInfo storage position,
    uint256 amountToWithdraw,
    uint256 amountToRepayDebt
  ) external {
    position.aTokenAmount -= amountToWithdraw;
    position.debtTokenAmount -= amountToRepayDebt;
  }

  function updateLiquidation(
    Types.orderInfo storage position,
    uint256 amountToWithdrawIncludeIncentive,
    uint256 debtToCover
  ) external {
    position.aTokenAmount -= amountToWithdrawIncludeIncentive;
    position.debtTokenAmount -= debtToCover;
  }
}
