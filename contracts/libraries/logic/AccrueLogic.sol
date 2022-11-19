// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../Types.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {GeneralLogic} from "./GeneralLogic.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {IUniswapV3Factory} from "../../dependencies/uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../dependencies/uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "../../dependencies/uniswap/v3-periphery/libraries/OracleLibrary.sol";

library AccrueLogic {
  using WadRayMath for uint256;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  uint256 internal constant MAX_INT = type(uint256).max;

  /**
   * @dev we need to self-accrue interest to our users
   * @param position position
   */
  function executeAccrue(
    IAddressesProvider FLAEX_PROVIDER,
    address baseToken,
    address quoteToken,
    Types.orderInfo storage position
  ) external {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());

    uint256 oldATokenAmount = position.aTokenAmount;
    uint256 oldATokenIndex = position.aTokenIndex;

    uint256 oldDebtTokenAmount = position.debtTokenAmount;
    uint256 oldDebtTokenIndex = position.debtTokenIndex;

    uint256 newATokenAmount = 0;
    uint256 newDebtTokenAmount = 0;

    // get new Indexes:
    if (oldATokenAmount != 0) {
      uint256 newATokenIndex = AaveL1Pool.getReserveNormalizedIncome(baseToken);

      newATokenAmount = (oldATokenAmount.rayDiv(oldATokenIndex)).rayMul(newATokenIndex);
      (position.aTokenIndex, position.aTokenAmount) = (newATokenIndex, newATokenAmount);
    }

    if (oldDebtTokenAmount != 0) {
      uint256 newDebtTokenIndex = AaveL1Pool.getReserveNormalizedVariableDebt(quoteToken);

      newDebtTokenAmount = (oldDebtTokenAmount.rayDiv(oldDebtTokenIndex)).rayMul(newDebtTokenIndex);
      (position.debtTokenIndex, position.debtTokenAmount) = (newDebtTokenIndex, newDebtTokenAmount);
    }
  }

  /// @dev view functions to return user data
  function executeGetUserData(
    IAddressesProvider FLAEX_PROVIDER,
    uint24[] memory uniPoolFees,
    address baseToken,
    address quoteToken,
    Types.orderInfo memory position,
    Types.tradingPairInfo memory tradingPair
  )
    external
    view
    returns (
      uint256 baseTokenAmount,
      uint256 quoteTokenAmount,
      uint256 liquidationThreshold,
      uint256 marginRatio
    )
  {
    liquidationThreshold = tradingPair.liquidationThreshold;

    if (position.aTokenAmount == 0 && position.debtTokenAmount == 0) {
      baseTokenAmount = 0;
      quoteTokenAmount = 0;
      marginRatio = MAX_INT;
    }

    baseTokenAmount = (position.aTokenAmount.rayDiv(position.aTokenIndex)).rayMul(
      IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool()).getReserveNormalizedIncome(
        baseToken
      )
    );

    quoteTokenAmount = (position.debtTokenAmount.rayDiv(position.debtTokenIndex)).rayMul(
      IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool()).getReserveNormalizedVariableDebt(
        quoteToken
      )
    );

    /// @dev first, we devise the price of baseToken in terms of quoteToken by AAVE
    /// AavePrice is scaled-up by wad (1e18)
    uint256 AAVEMarginRatio = GeneralLogic.getAAVEMarginRatio(
      IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool()),
      IPriceOracleGetter(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPriceOracle()),
      baseToken,
      quoteToken,
      baseTokenAmount,
      quoteTokenAmount
    );

    /// @dev then we devise the price of uniswap by calculating balance-weighted average price
    /// also scaled-up by wad
    uint256 UniswapBWAPMarginRatio = GeneralLogic.getBWAPMarginRatio(
      IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory()),
      // [uint24(500), uint24(3000), uint24(10000)],
      uniPoolFees,
      baseToken,
      quoteToken,
      baseTokenAmount,
      quoteTokenAmount
    );

    /// @dev marginRatio = average of AAVEMarginRatio and UniswapBWAPMarginRatio
    marginRatio = (AAVEMarginRatio + UniswapBWAPMarginRatio) / 2;
  }
}
