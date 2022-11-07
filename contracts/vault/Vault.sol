// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

/// @title Vault Contract
/// @author flaex
/// @notice Vault keeps track of all Investors
/// @dev
/** 
  Vault transfer fund to Main and deposit all assets into AAVE as collateral,
  thus effectively increase Main's collateral and keeps Main safe
  Vault also keeps track of Investors for distributing rewards & profit.
*/
