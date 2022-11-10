// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../libraries/Types.sol";
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

/**
 * @title Storage
 * @author Flaex
 * @notice Contract used as storage of the Main contract.
 * @dev It defines the storage layout of the Main contract.
 */

contract MainStorage {
  // mapping (pair => tradingPairInfo), ie: ETH/USDC => tradingPairInfo
  mapping(bytes => Types.tradingPairInfo) internal _tradingPair;

  // mapping (user => Token/aToken => orderInfo)
  mapping(address => mapping(address => Types.orderInfo)) internal _position;

  // Aave Address Provider
  IPoolAddressesProvider _AaveAddressProvider;

  // Layer 2 Pool for optimization
  IL2Pool _AavePool;

  // Layer 1 for un-supported functions
  IPool _AaveL1Pool;

  // Layer 2 Encoder
  L2Encoder _AaveEncoder;

  // Aave Referral Code
  uint16 internal _AaveReferralCode;

  // Aave Interest Rate Mode, None: 0, Stable: 1, Variable: 2
  uint8 internal _AaveInterestRateMode;
}
