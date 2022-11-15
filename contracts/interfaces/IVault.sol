// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IVault {
  function transferFeeToVault(
    address asset,
    address from,
    uint256 amount
  ) external;
}
