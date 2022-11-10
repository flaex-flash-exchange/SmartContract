// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";

/// @title Vault Contract
/// @author flaex
/// @notice Vault keeps track of all Investors
/// @dev
/** 
  Main transfer fund to Vault and deposit all assets into AAVE as collateral,
  thus effectively increase Main's collateral and keeps Main safe
  Vault also keeps track of Investors for distributing rewards & profit.
*/

contract Vault {
  address Admin;
  address Main;

  constructor(address _Admin, address _Main) {
    Admin = _Admin;
    Main = _Main;
  }

  /**
   * @dev Only main can call functions marked by this modifier.
   **/

  modifier onlyMain() {
    _onlyMain();
    _;
  }

  /**
   * @dev Only Admin can call functions marked by this modifier.
   **/

  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function _onlyMain() internal view virtual {
    require(msg.sender == Main, "Invalid_Call");
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == Admin, "Invalid_Call");
  }
}
