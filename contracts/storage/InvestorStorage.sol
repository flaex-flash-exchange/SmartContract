// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title Storage for Vault and Investor
 * @author Flaex
 * @notice Contract used as storage of the Vault and Investor contract.
 * @dev It defines the storage layout of the Vault and Investor contract.
 */
contract InvestorStorage {
  uint16 internal _AaveReferralCode;

  address internal _acceptedAsset;

  string internal _acceptedAssetSymbol;

  struct investorInfo {
    uint256 supplyIndex;
    uint256 lockTimestamp;
    mapping(address => uint256) Yield;
  }

  // mapping user to info
  mapping(address => investorInfo) internal _Investor;
}
