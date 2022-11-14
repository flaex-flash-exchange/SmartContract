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

/**
 * @title Update library
 * @author Flaex
 * @notice Implements the logic for update market
 */

library UpdateMarket {
  uint256 constant MAX_INT = type(uint256).max;

  // prettier-ignore
  event MarketUpdated(uint id, address zeroAsset, address firstAsset, uint256 tradingFee, uint256 tradingFee_ProtocolShare, uint256 liquidationThreshold, uint256 liquidationProtocolShare, bool isLive);
  event MarketDropped(uint256 id, address zeroAsset, address firstAsset, bool isLive);

  function executeInitMarket(
    address zeroAsset,
    address firstAsset,
    IL2Pool AavePool,
    IPool AaveL1Pool,
    L2Encoder AaveEncoder,
    IUniswapV3Factory UniFactory,
    uint24 uniFee
  ) external {
    IUniswapV3Pool UniPool = IUniswapV3Pool(UniFactory.getPool(zeroAsset, firstAsset, uniFee));

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
    emit MarketUpdated(params.id, params.zeroToken, params.firstToken, params.tradingFee, params.tradingFee_ProtocolShare, params.liquidationThreshold, params.liquidationProtocolShare, true);

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
}
