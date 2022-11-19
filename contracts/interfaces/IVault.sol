// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IVault {
  function transferFeeToVault(address asset, uint256 amount) external;

  function withdrawFromVault(address asset, uint256 amount) external;
}
