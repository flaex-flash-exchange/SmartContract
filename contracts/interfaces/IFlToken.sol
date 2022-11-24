// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IFlToken {
  event Transfer(address indexed from, address indexed to, uint256 amount);

  function name() external pure returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external pure returns (uint8);

  function totalSupply() external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function underlying_asset() external view returns (address);

  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;
}
