// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {Types} from "../Types.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IAddressesProvider} from "../../interfaces/IAddressesProvider.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/**
 * @title Update library
 * @author Flaex
 * @notice Implements the logic for update market
 */

library UpdateMarket {
  uint256 constant MAX_INT = type(uint256).max;

  // prettier-ignore
  event MarketUpdated(uint id, address zeroAsset, address firstAsset, uint256 tradingFee, uint256 liquidationThreshold, uint256 liquidationProtocolShare, bool isLive);
  event MarketDropped(uint256 id, address zeroAsset, address firstAsset, bool isLive);

  function executeInitMarket(
    IAddressesProvider FLAEX_PROVIDER,
    address zeroAsset,
    address firstAsset,
    uint24 uniFee
  ) external {
    IL2Pool AavePool = IL2Pool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    L2Encoder AaveEncoder = L2Encoder(FLAEX_PROVIDER.getAaveEncoder());
    IUniswapV3Pool UniPool = IUniswapV3Pool(
      IUniswapV3Factory(FLAEX_PROVIDER.getUniFactory()).getPool(zeroAsset, firstAsset, uniFee)
    );

    // approve zeroAsset for both AAVE Pool and Uniswap Pool
    IERC20(zeroAsset).approve(address(AavePool), MAX_INT);
    IERC20(zeroAsset).approve(address(UniPool), MAX_INT);

    // approve aZeroAsset
    DataTypes.ReserveData memory reserve_zeroAsset = AaveL1Pool.getReserveData(zeroAsset);
    address aZeroAsset = reserve_zeroAsset.aTokenAddress;
    IERC20(aZeroAsset).approve(address(AavePool), MAX_INT);

    //set used as collateral
    bytes32 encodedZero = AaveEncoder.encodeSetUserUseReserveAsCollateral(zeroAsset, true);
    AavePool.setUserUseReserveAsCollateral(encodedZero);

    // approve firstAsset for both AAVE Pool and Uniswap Pool
    IERC20(firstAsset).approve(address(AavePool), MAX_INT);
    IERC20(firstAsset).approve(address(UniPool), MAX_INT);

    // approve aFirstAsset
    DataTypes.ReserveData memory reserve_firstAsset = AaveL1Pool.getReserveData(firstAsset);
    address aFirstAsset = reserve_firstAsset.aTokenAddress;
    IERC20(aFirstAsset).approve(address(AavePool), MAX_INT);

    //set used as collateral
    bytes32 encodedFirst = AaveEncoder.encodeSetUserUseReserveAsCollateral(firstAsset, true);
    AavePool.setUserUseReserveAsCollateral(encodedFirst);
  }

  /// @dev needs to check whether aave and uniswap supports ?
  function executeUpdateMarket(
    mapping(bytes => Types.tradingPairInfo) storage tradingPair,
    mapping(uint256 => bytes) storage tradingPairList,
    Types.tradingPairInfo memory params
  ) external returns (bool) {
    bytes memory encodedParams = abi.encode(params.zeroToken, params.firstToken);

    bool PairExisted = false;

    for (uint256 i = 0; i < params.id; i++) {
      if (keccak256(abi.encode(tradingPairList[i])) == keccak256(encodedParams)) {
        params.id = i;
        PairExisted = true;
      }
    }

    tradingPair[encodedParams] = params;
    if (!PairExisted) {
      tradingPairList[params.id] = encodedParams;
    }

    // prettier-ignore
    emit MarketUpdated(params.id, params.zeroToken, params.firstToken, params.tradingFee, params.liquidationThreshold, params.liquidationProtocolShare, true);

    return PairExisted;
  }

  function executeDropMarket(
    address zeroAsset,
    address firstAsset,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair
  ) external {
    bytes memory encodedParams = abi.encode(zeroAsset, firstAsset);

    tradingPair[encodedParams].isLive = false;

    emit MarketDropped(tradingPair[encodedParams].id, zeroAsset, firstAsset, false);
  }

  /// @dev safe because only Main can pull call transferFrom from Vault
  function executeApproveVault(
    IAddressesProvider FLAEX_PROVIDER,
    address[] memory Assets,
    bool isUpapprove
  ) external {
    for (uint8 i = 0; i < Assets.length; i++) {
      !isUpapprove
        ? IERC20(Assets[i]).approve(FLAEX_PROVIDER.getVault(), MAX_INT)
        : IERC20(Assets[i]).approve(FLAEX_PROVIDER.getVault(), 0);
    }
  }
}
