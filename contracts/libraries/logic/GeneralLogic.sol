// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {Types} from "../Types.sol";

import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";

import {IUniswapV3Factory} from "../../dependencies/uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../dependencies/uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "../../dependencies/uniswap/v3-periphery/libraries/OracleLibrary.sol";

/**
 * @title General logic Libraries
 * @author Flaex
 * @notice Implements general functions
 */

library GeneralLogic {
  using WadRayMath for uint256;
  using FullMath for uint256;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  function getAAVEMarginRatio(
    IPool AaveL1Pool,
    IPriceOracleGetter AaveOracle,
    address baseToken,
    address quoteToken,
    uint256 baseTokenAmount,
    uint256 quoteTokenAmount
  ) external view returns (uint256 AAVEMarginRatio) {
    DataTypes.ReserveConfigurationMap memory ReserveBaseToken = AaveL1Pool.getConfiguration(baseToken);
    DataTypes.ReserveConfigurationMap memory ReserveQuoteToken = AaveL1Pool.getConfiguration(quoteToken);

    /// @dev balanceOfBase in Base_Currency = basePrice * baseAmount / baseDecimal
    uint256 balanceOfBase = AaveOracle.getAssetPrice(baseToken).mulDiv(baseTokenAmount, ReserveBaseToken.getDecimals());
    uint256 balanceOfQuote = AaveOracle.getAssetPrice(quoteToken).mulDiv(
      quoteTokenAmount,
      ReserveQuoteToken.getDecimals()
    );

    /// @dev marginRatio = balanceOfBase / balanceOfQuote
    AAVEMarginRatio = balanceOfBase.wadDiv(balanceOfQuote);
  }

  function getBWAPMarginRatio(
    IUniswapV3Factory UniFactory,
    uint24[] memory uniPoolFees,
    address baseToken,
    address quoteToken,
    uint256 baseTokenAmount,
    uint256 quoteTokenAmount
  ) external view returns (uint256 BWAPMarginRatio) {
    uint256 totalMarginRatioMulBalance;

    for (uint8 i = 0; i < uniPoolFees.length; i++) {
      if (UniFactory.getPool(baseToken, quoteToken, uniPoolFees[i]) != address(0)) {
        uint256 quoteTokenOut = OracleLibrary.getQuoteAtTick(
          OracleLibrary.consult(UniFactory.getPool(baseToken, quoteToken, uniPoolFees[i]), 1),
          uint128(baseTokenAmount),
          baseToken,
          quoteToken
        );

        totalMarginRatioMulBalance += quoteTokenOut.mulDiv(
          IERC20(baseToken).balanceOf(UniFactory.getPool(baseToken, quoteToken, uniPoolFees[i])),
          quoteTokenAmount
        );
      }
    }

    /// @dev looks stupid due to stack too deep
    BWAPMarginRatio = totalMarginRatioMulBalance.wadDiv(
      IERC20(baseToken).balanceOf(UniFactory.getPool(baseToken, quoteToken, uniPoolFees[0])) +
        IERC20(baseToken).balanceOf(UniFactory.getPool(baseToken, quoteToken, uniPoolFees[1])) +
        IERC20(baseToken).balanceOf(UniFactory.getPool(baseToken, quoteToken, uniPoolFees[2]))
    );
  }
}
