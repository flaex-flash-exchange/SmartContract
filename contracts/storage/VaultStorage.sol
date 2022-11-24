// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title Storage for Vault and Investor
 * @author Flaex
 * @notice Contract used as storage of the Vault and Investor contract.
 * @dev It defines the storage layout of the Vault and Investor contract.
 */
contract VaultStorage {
  // active assets eligible for fees share
  address[] internal _activeAssets;

  uint16 internal _AaveReferralCode;

  // protocol share for trading fee, scaled-up by 1e2
  uint256 internal _protocolShare;

  // struct profit and flIndex
  struct yieldInfo {
    uint256 flIndex;
    uint256 protocolAmount;
    uint256 shareableAmount;
  }

  // mapping yield asset address => yield
  mapping(address => yieldInfo) internal _yieldGenerated;
}
