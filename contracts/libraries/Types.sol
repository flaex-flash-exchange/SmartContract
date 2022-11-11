// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

library Types {
  /** @dev we don't need aTokenAddress/debtTokenAddress because it's the token long/short, ie:
   * long eth: supply ETH, borrow Stable
   * short eth: supply Stable, borrow ETH
   */
  struct orderInfo {
    uint256 aTokenAmount;
    uint256 aTokenIndex;
    uint256 debtTokenAmount;
    uint256 debtTokenIndex;
  }

  /** @dev in-line with Uniswap sorting, ie: (token0 < token1) == true
   */
  struct tradingPairInfo {
    uint256 id;
    address zeroToken;
    address firstToken;
    uint256 tradingFee;
    uint256 tradingFee_ProtocolShare;
    uint256 liquidationThreshold;
    uint256 liquidationProtocolShare;
    bool isLive;
  }
}
