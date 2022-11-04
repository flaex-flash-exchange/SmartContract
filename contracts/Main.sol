// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

/** Logic:
 * Long TOKEN/USDC: -> Meaning collateral TOKEN, borrow USDC
    - step 1: User deposit USDC to Main
    - step 2: Main calls Uniswap Flash to 'borrow' TOKEN
    - step 3: Main collateral TOKEN to AAVE
    - step 4: Main borrow USDC + user's initial margin to repay Uniswap Flash
    *** END RESULT:
     - Collateral: TOKEN
     - Borrow: USDC

* Short TOKEN/USDC: -> Meaning collateral USDC, borrow TOKEN
    - step 1: User deposit USDC to Main
    - step 2: Main calls Uniswap Flash to borrow USDC
    - step 3: Main collateral USDC (plus user's initial margin) to AAVE
    - step 4: Main borrow TOKEN to repay Uniswap Flash
    *** END RESULT:
     - Collateral: USDC
     - Borrow: TOKEN

 */

contract Main {
  constructor(address admin) {
    admin = payable(msg.sender);
  }

  receive() external payable {}

  struct orderInfo {
    uint8 orderID;
    uint256 tokenBorrowed;
  }

  mapping(address => orderInfo) public userPosition;
}
