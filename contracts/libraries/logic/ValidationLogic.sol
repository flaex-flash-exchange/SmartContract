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

  uint256 constant MAX_INT = type(uint256).max;

  function executeOpenCheck(
    IAddressesProvider FLAEX_PROVIDER,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.executeOpen memory params
  ) external view returns (uint24) {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IUniswapV3Factory UniFactory = IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory());

    /// @dev trading pair isLive
    bytes memory encodedParams = params.baseToken < params.quoteToken
      ? abi.encode(params.baseToken, params.quoteToken)
      : abi.encode(params.quoteToken, params.baseToken);
    require(tradingPair[encodedParams].isLive, "TradingPair_Is_Not_Live");

    /// @dev sanity check amount to open and marginLevel
    require(params.baseMarginAmount > 0, "Invalid_Base_Margin_Amount");
    require(
      params.marginLevel > 0 && params.marginLevel <= tradingPair[encodedParams].maxMarginLevel,
      "Invalid_Margin"
    );

    /// @dev sanity check again to see if aave supports
    /// @dev needs to check both tokens because of repaying later
    DataTypes.ReserveConfigurationMap memory ReserveBaseToken = AaveL1Pool.getConfiguration(params.baseToken);
    DataTypes.ReserveConfigurationMap memory ReserveQuoteToken = AaveL1Pool.getConfiguration(params.quoteToken);

    (bool baseIsActive, , , , bool baseIsPaused) = ReserveBaseToken.getFlags();
    (bool QuoteIsActive, , , , bool QuoteIsPaused) = ReserveQuoteToken.getFlags();

    require(baseIsActive && !baseIsPaused, "Aave_Base_Reserve_Is_Not_live");
    require(QuoteIsActive && !QuoteIsPaused, "Aave_Quote_Reserve_Is_Not_live");

    /// @dev sanity check again to see if uniswap supports
    require(params.uniFee == 500 || params.uniFee == 3000 || params.uniFee == 10000); //just to be extra safe
    require(
      UniFactory.getPool(params.baseToken, params.quoteToken, params.uniFee) != address(0),
      "Uniswap_Reserve_Is_Not_Live"
    );

    return tradingPair[encodedParams].tradingFee;
  }

  function executeCloseCheck(
    IAddressesProvider FLAEX_PROVIDER,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    Types.orderInfo storage position,
    Types.executeClose memory params
  ) external view returns (uint24, uint256) {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IUniswapV3Factory UniFactory = IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory());

    /// @dev baseTokenAmount must be less than user's collateral
    require(
      params.baseTokenAmount == MAX_INT || params.baseTokenAmount <= position.aTokenAmount,
      "Invalid_Base_Token_Amount"
    );

    /// @dev if baseTokenAmount == MAX_INT, baseTokenAmount = position.aTokenAmount
    params.baseTokenAmount = params.baseTokenAmount == MAX_INT ? position.aTokenAmount : params.baseTokenAmount;

    /// @dev trading pair must still be live. This exposes another todo
    /// @dev what if trading pair is no longer live?
    bytes memory encodedParams = params.baseToken < params.quoteToken
      ? abi.encode(params.baseToken, params.quoteToken)
      : abi.encode(params.quoteToken, params.baseToken);
    require(tradingPair[encodedParams].isLive, "TradingPair_Is_Not_Live");

    /// @dev sanity check amount to close
    require(params.baseTokenAmount > 0, "Invalid_Base_Token_Amount");

    /// @dev sanity check again to see if aave supports
    DataTypes.ReserveConfigurationMap memory ReserveQuoteToken = AaveL1Pool.getConfiguration(params.quoteToken);
    (bool QuoteIsActive, , , , bool QuoteIsPaused) = ReserveQuoteToken.getFlags();

    require(QuoteIsActive && !QuoteIsPaused, "Aave_Quote_Reserve_Is_Not_live");

    /// @dev sanity check again to see if uniswap supports
    require(params.uniFee == 500 || params.uniFee == 3000 || params.uniFee == 10000); //just to be extra safe
    require(
      UniFactory.getPool(params.baseToken, params.quoteToken, params.uniFee) != address(0),
      "Uniswap_Reserve_Is_Not_Live"
    );

    return (tradingPair[encodedParams].tradingFee, params.baseTokenAmount);
  }
}
