// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IInvestor {
  event acceptedAssetSet(address acceptedAsset);
  event AssetProvided(address indexed investor, address acceptedAsset, uint256 amount);
  event yieldClaimed(address indexed claimer, address[] yieldTokenAddress, uint256[] amount);
  event assetWithdrawn(address indexed withdrawer, address acceptedAsset, uint256 amount);

  function getAcceptedAsset() external view returns (address, string memory);

  function getInvestorBalance(address user) external view returns (uint256);

  function getInvestorYield(address user) external view returns (address[] memory, uint256[] memory);

  function provide(uint256 amount) external;

  function claimYield() external;

  function withdraw(uint256 amount) external returns (uint256);
}
