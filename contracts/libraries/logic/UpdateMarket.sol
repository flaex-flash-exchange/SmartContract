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
 * @title SupplyLogic library
 * @author Aave
 * @notice Implements the base logic for supply/withdraw
 */

library UpdateMarket {
  uint256 constant MAX_INT = type(uint256).max;

  // prettier-ignore
  event MarketUpdated(address zeroAsset, address firstAsset, uint256 tradingFee, uint256 tradingFee_ProtocolShare, uint256 liquidationThreshold, uint256 liquidationProtocolShare, bool isLive);
  event MarketDropped(address zeroAsset, address firstAsset, bool isLive);

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

  function executeUpdateMarket(
    address zeroAsset,
    address firstAsset,
    uint256 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair
  ) external {
    bytes memory encodedParams = abi.encode(zeroAsset, firstAsset);

    tradingPair[encodedParams] = Types.tradingPairInfo({
      zeroToken: zeroAsset,
      firstToken: firstAsset,
      tradingFee: tradingFee,
      tradingFee_ProtocolShare: tradingFee_ProtocolShare,
      liquidationThreshold: liquidationThreshold,
      liquidationProtocolShare: liquidationProtocolShare,
      isLive: true
    });

    // prettier-ignore
    emit MarketUpdated(zeroAsset, firstAsset, tradingFee, tradingFee_ProtocolShare, liquidationThreshold, liquidationProtocolShare, true);
  }

  function executeDropMarket(
    address zeroAsset,
    address firstAsset,
    mapping(bytes => Types.tradingPairInfo) storage tradingPair
  ) external {
    bytes memory encodedParams = abi.encode(zeroAsset, firstAsset);
    tradingPair[encodedParams].isLive = false;

    emit MarketDropped(zeroAsset, firstAsset, false);
  }
}

/**
 struct tradingPairInfo {
    address zeroToken;
    address firstToken;
    uint256 tradingFee;
    uint256 tradingFee_ProtocolShare;
    uint256 liquidationThreshold;
    uint256 liquidationProtocolShare;
    bool isLive;
  } */
