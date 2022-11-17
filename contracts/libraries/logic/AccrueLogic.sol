// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../Types.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

library AccrueLogic {
  using WadRayMath for uint256;

  /**
   * @dev we need to self-accrue interest to our users
   * @param position position
   */
  function executeAccrue(IAddressesProvider FLAEX_PROVIDER, Types.orderInfo storage position) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());

    uint256 oldATokenAmount = position.aTokenAmount;
    uint256 oldATokenIndex = position.aTokenIndex;

    uint256 oldDebtTokenAmount = position.debtTokenAmount;
    uint256 oldDebtTokenIndex = position.debtTokenIndex;

    uint256 newATokenAmount = 0;
    uint256 newDebtTokenAmount = 0;

    // get new Indexes:
    if (oldATokenAmount != 0) {
      //get new borrowIndex, should get normalizedIncome here because of real-time
      uint256 newATokenIndex = AaveL1Pool.getReserveNormalizedIncome(position.aTokenAddress);

      newATokenAmount = (oldATokenAmount.rayDiv(oldATokenIndex)).rayMul(newATokenIndex);
      (position.aTokenIndex, position.aTokenAmount) = (newATokenIndex, newATokenAmount);
    }

    if (oldDebtTokenAmount != 0) {
      uint256 newDebtTokenIndex = AaveL1Pool.getReserveNormalizedVariableDebt(position.debtTokenAddress);

      newDebtTokenAmount = (oldDebtTokenAmount.rayDiv(oldDebtTokenIndex)).rayMul(newDebtTokenIndex);
      (position.debtTokenIndex, position.debtTokenAmount) = (newDebtTokenIndex, newDebtTokenAmount);
    }
  }
}
