// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IMain {
  event tradingFeeSet(uint256 oldTradingFee, uint256 newTradingFee);

  function basicApprove(
    address zeroAsset,
    address firstAsset,
    uint24 uniFee
  ) external;

  function updateMarket(
    address Asset0,
    address Asset1,
    uint24 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare,
    uint256 maxMarginLevel
  ) external;

  function dropMarket(address Asset0, address Asset1) external;

  function getAllMarkets() external returns (address[] memory);

  function openExactOutput(
    address baseToken,
    address quoteToken,
    uint256 baseMarginAmount,
    uint256 maxQuoteTokenAmount,
    uint24 uniFee,
    uint256 marginLevel
  ) external;
}
