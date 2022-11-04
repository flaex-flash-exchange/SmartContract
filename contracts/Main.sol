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

import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";

contract Main {
  address admin;
  IL2Pool Pool;
  L2Encoder Encoder;

  constructor(address _Pool, address _Encoder) {
    admin = payable(msg.sender);
    Pool = IL2Pool(_Pool);
    Encoder = L2Encoder(_Encoder);
  }

  receive() external payable {}

  struct orderInfo {
    uint128 orderID;
    uint256 tokenBorrowed;
  }

  mapping(address => orderInfo) public userPosition;

  function testBorrow(address asset, uint256 amount) public {
    uint16 referralCode = 0;
    bytes32 encodedParams = Encoder.encodeSupplyParams(asset, amount, referralCode);

    Pool.borrow(encodedParams);
  }
}
