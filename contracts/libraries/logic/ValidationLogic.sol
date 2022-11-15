// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../Types.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";

import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

library ValidationLogic {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  function executeOpenCheck(
    IAddressesProvider FLAEX_PROVIDER,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.executeOpen memory params
  ) external view returns (uint24) {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IUniswapV3Factory UniFactory = IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory());

    // trading pair isLive
    bytes memory encodedParam = params.baseToken < params.quoteToken
      ? abi.encode(params.baseToken, params.quoteToken)
      : abi.encode(params.quoteToken, params.baseToken);
    require(tradingPair[encodedParam].isLive, "TradingPair_Is_Not_Live");

    require(params.marginLevel > 0 && params.marginLevel <= tradingPair[encodedParam].maxMarginLevel, "Invalid_Margin");

    // sanity check again to see if aave supports
    DataTypes.ReserveConfigurationMap memory ReserveBaseToken = AaveL1Pool.getConfiguration(params.baseToken);
    DataTypes.ReserveConfigurationMap memory ReserveQuoteToken = AaveL1Pool.getConfiguration(params.quoteToken);

    (bool baseIsActive, , , , bool baseIsPaused) = ReserveBaseToken.getFlags();
    (bool QuoteIsActive, , , , bool QuoteIsPaused) = ReserveQuoteToken.getFlags();

    require(baseIsActive && !baseIsPaused, "Aave_Base_Reserve_Is_Not_live");
    require(QuoteIsActive && !QuoteIsPaused, "Aave_Quote_Reserve_Is_Not_live");

    // sanity check again to see if uniswap supports
    require(params.uniFee == 500 || params.uniFee == 3000 || params.uniFee == 10000); //just to be extra safe
    require(
      UniFactory.getPool(params.baseToken, params.quoteToken, params.uniFee) != address(0),
      "Uniswap_Reserve_Is_Not_Live"
    );

    return tradingPair[encodedParam].tradingFee;
  }
}
