// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IMain {
  event tradingFeeSet(uint256 oldTradingFee, uint256 newTradingFee);

  function basicApprove(address asset, address stable) external;

  function updateMarket(
    address Asset0,
    address Asset1,
    uint256 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare
  ) external;

  function dropMarket(address Asset0, address Asset1) external;
}
