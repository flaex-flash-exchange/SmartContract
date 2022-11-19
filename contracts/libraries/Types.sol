// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

library Types {
  /** @dev
   * we assume that aToken is the atoken of Token Long and debtToken is the debtToken of the asset being Long against
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

  struct executeClose {
    address baseToken;
    address quoteToken;
    uint256 baseTokenAmount;
    uint256 minQuoteTokenAmount;
    uint24 tradingFee;
    uint24 uniFee;
    uint256 AaveInterestRateMode;
  }

  struct executeRepayParital {
    address baseToken;
    address quoteToken;
    uint256 quoteTokenAmount;
    uint256 AaveInterestRateMode;
  }

  struct executeLiquidation {
    address baseToken;
    address quoteToken;
    address liquidatedUser;
    uint256 debtToCover;
    uint24[] uniPoolFees;
    uint256 maxLiquidationFactor;
    uint256 liquidationIncentive;
    uint256 AaveInterestRateMode;
  }

  enum DIRECTION {
    OPEN,
    CLOSE
  }
}
