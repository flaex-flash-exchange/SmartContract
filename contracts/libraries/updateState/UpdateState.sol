// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {Types} from "../Types.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

library UpdateState {
  function updateOpenState(
    uint256 amountToSupply,
    uint256 amountToBorrow,
    Types.orderInfo memory localPosition,
    DataTypes.ReserveData memory Reserve
  ) external pure returns (Types.orderInfo memory) {
    uint256 oldATokenAmount = localPosition.aTokenAmount;
    uint256 oldDebtTokenAmount = localPosition.debtTokenAmount;

    uint256 newATokenAmount = amountToSupply + oldATokenAmount;
    uint256 newDebtTokenAmount = amountToBorrow + oldDebtTokenAmount;

    localPosition = Types.orderInfo({
      aTokenAddress: Reserve.aTokenAddress,
      aTokenAmount: newATokenAmount,
      aTokenIndex: Reserve.liquidityIndex,
      debtTokenAddress: Reserve.variableDebtTokenAddress,
      debtTokenAmount: newDebtTokenAmount,
      debtTokenIndex: Reserve.variableBorrowIndex
    });

    return localPosition;
  }
}
