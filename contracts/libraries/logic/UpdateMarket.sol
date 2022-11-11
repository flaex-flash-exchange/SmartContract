// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {Types} from "../Types.sol";

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
    IL2Pool _AavePool,
    IPool _AaveL1Pool,
    L2Encoder _AaveEncoder
  ) external {
    // approve zeroAsset
    IERC20(zeroAsset).approve(address(_AavePool), MAX_INT);

    // approve aZeroAsset
    DataTypes.ReserveData memory reserve_zeroAsset = _AaveL1Pool.getReserveData(zeroAsset);
    address aZeroAsset = reserve_zeroAsset.aTokenAddress;
    IERC20(aZeroAsset).approve(address(_AavePool), MAX_INT);

    //set used as collateral
    bytes32 encodedZero = _AaveEncoder.encodeSetUserUseReserveAsCollateral(zeroAsset, true);
    _AavePool.setUserUseReserveAsCollateral(encodedZero);

    // approve firstAsset
    IERC20(firstAsset).approve(address(_AavePool), MAX_INT);

    // approve aFirstAsset
    DataTypes.ReserveData memory reserve_firstAsset = _AaveL1Pool.getReserveData(firstAsset);
    address aFirstAsset = reserve_firstAsset.aTokenAddress;
    IERC20(aFirstAsset).approve(address(_AavePool), MAX_INT);

    //set used as collateral
    bytes32 encodedFirst = _AaveEncoder.encodeSetUserUseReserveAsCollateral(firstAsset, true);
    _AavePool.setUserUseReserveAsCollateral(encodedFirst);
  }

  /// @dev needs to check whether aave and uniswap supports
  function executeUpdateMarket(
    mapping(bytes32 => Types.tradingPairInfo) storage tradingPair,
    mapping(uint256 => bytes32) storage _tradingPairList,
    Types.tradingPairInfo memory params
  ) external returns (bool) {
    bytes32 encodedParams = keccak256(abi.encodePacked(params.zeroToken, params.firstToken));

    bool PairExisted = false;

    for (uint256 i = 0; i < params.id; i++) {
      if (keccak256(abi.encodePacked(_tradingPairList[i])) == encodedParams) {
        params.id = i;
        PairExisted = true;
      }
    }

    tradingPair[encodedParams] = params;
    if (!PairExisted) {
      _tradingPairList[params.id] = encodedParams;
    }

    // prettier-ignore
    emit MarketUpdated(params.id, params.zeroToken, params.firstToken, params.tradingFee, params.tradingFee_ProtocolShare, params.liquidationThreshold, params.liquidationProtocolShare, true);

    return PairExisted;
  }

  function executeDropMarket(
    address zeroAsset,
    address firstAsset,
    mapping(bytes32 => Types.tradingPairInfo) storage tradingPair
  ) external {
    bytes32 encodedParams = keccak256(abi.encodePacked(zeroAsset, firstAsset));

    tradingPair[encodedParams].isLive = false;

    emit MarketDropped(tradingPair[encodedParams].id, zeroAsset, firstAsset, false);
  }
}
