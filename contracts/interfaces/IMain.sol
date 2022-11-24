// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Types} from "../libraries/Types.sol";

interface IMain {
  event tradingFeeSet(uint256 oldTradingFee, uint256 newTradingFee);
  event AaveReferralCodeSet(uint16 oldCode, uint16 newCode);
  // prettier-ignore
  event liquidationParamatersSet(uint256 oldLiquidationFactor, uint256 newLiquidationFactor, uint256 oldLiquidationIncentive, uint256 newLiquidationIncentive);

  function basicApprove(
    address zeroAsset,
    address firstAsset,
    uint24 uniFee
  ) external;

  function updateMarket(
    address Asset0,
    address Asset1,
    uint24 tradingFee,
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

  function closeExactInput(
    address baseToken,
    address quoteToken,
    uint256 baseTokenAmount,
    uint256 minQuoteTokenAmount,
    uint24 uniFee
  ) external;

  function repayPartialDebt(
    address baseToken,
    address quoteToken,
    uint256 quoteTokenAmount
  ) external;

  function liquidation(
    address baseToken,
    address quoteToken,
    address liquidatedUser,
    uint256 debtToCover
  ) external;

  function getUserData(
    address baseToken,
    address quoteToken,
    address user
  ) external view returns (Types.userDatas memory);

  function getUserDataS(address user) external view returns (Types.userDatas[] memory);

  function getMarketConfiguration(address baseToken, address quoteToken)
    external
    view
    returns (Types.tradingPairInfo memory);

  function setLiquidationParameters(uint256 newLiquidatationFactor, uint256 newLiquidationIncentive) external;

  function setAaveReferralCode(uint16 newCode) external;
}
