// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ICreditDelegationToken} from "@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol";
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

import {VaultStorage} from "./VaultStorage.sol";

/**
 * @title Vault Contract
 * @author flaex
 * @notice Vault holds aToken and assets
 * @dev
 */

contract Vault {
  IAddressesProvider public immutable FLAEX_PROVIDER;

  uint256 internal constant MAX_INT = type(uint256).max;

  constructor(address provider) {
    FLAEX_PROVIDER = IAddressesProvider(provider);
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
    require(msg.sender == FLAEX_PROVIDER.getMain(), "Invalid_Main");
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getSuperAdmin(), "Invalid_Admin");
  }

  function initVault() external onlyAdmin {}

  function setUsedAsCollateral(address asset) external onlyAdmin {
    bytes32 encodedParams = L2Encoder(FLAEX_PROVIDER.getAaveEncoder()).encodeSetUserUseReserveAsCollateral(asset, true);
    IL2Pool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool()).setUserUseReserveAsCollateral(
      encodedParams
    );
  }

  function approveDelagationMain(address debtToken) external onlyAdmin {
    ICreditDelegationToken(debtToken).approveDelegation(FLAEX_PROVIDER.getMain(), MAX_INT);
  }

  function transferToVault(address asset, uint256 amount) external onlyMain {
    // IERC20(asset).transferFrom(sender, recipient, amount);
  }

  function withdrawFromVault(address asset, uint256 amount) external onlyMain {}
}
