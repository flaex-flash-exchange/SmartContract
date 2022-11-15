// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

library Types {
  /** @dev we don't need aTokenAddress/debtTokenAddress because it's the token long/short, ie:
   * long eth: supply ETH, borrow Stable
   * short eth: supply Stable, borrow ETH
   */
  struct orderInfo {
    address aTokenAddress;
    uint256 aTokenAmount;
    uint256 aTokenIndex;
    address debtTokenAddress;
    uint256 debtTokenAmount;
    uint256 debtTokenIndex;
  }

  /** @dev in-line with Uniswap sorting, ie: (token0 < token1) == true
   */
  struct tradingPairInfo {
    uint256 id;
    address zeroToken;
    address firstToken;
    uint24 tradingFee;
    uint256 tradingFee_ProtocolShare;
    uint256 liquidationThreshold;
    uint256 liquidationProtocolShare;
    uint256 maxMarginLevel;
    bool isLive;
  }

  struct executeOpen {
    address baseToken;
    address quoteToken;
    uint256 baseMarginAmount;
    uint256 maxQuoteTokenAmount;
    uint24 tradingFee;
    uint24 uniFee;
    uint16 AaveReferralCode;
    uint256 AaveInterestRateMode;
    uint256 marginLevel;
  }

  enum DIRECTION {
    OPEN,
    CLOSE
  }
}
