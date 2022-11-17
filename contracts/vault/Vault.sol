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
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";

import {VaultStorage} from "../storage/VaultStorage.sol";
import {IVault} from "../interfaces/IVault.sol";

/**
 * @title Vault Contract
 * @author flaex
 * @notice Vault holds aToken, debtToken and assets
 * @dev Technically, we do not need to double-check the amounts between Main and Vault because we assume calculations
 * from Main is always correct. thus, any valid request from Main is accepted. is this a security threat?
 */

contract Vault is IVault, ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;

  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 internal constant MAX_INT = type(uint256).max;

  /**
   * @dev Constructor.
   * @param provider The address of the IAddressesProvider contract
   */
  constructor(IAddressesProvider provider) {
    FLAEX_PROVIDER = provider;
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

  /**
   * @dev transfer fee from Main to Vault, pull call because we need to seperate protocol fee from distributable fee
   * @inheritdoc IVault
   */
  function transferFeeToVault(
    address asset,
    address from,
    uint256 amount
  ) external override onlyMain {
    IERC20(asset).safeTransferFrom(from, address(this), amount);
    /// do stuff here
  }

  /**
   * @dev withdraw aToken, transfer Token to caller
   * @param asset address of th underlying asset
   * @param amount underlying asset amount
   * @inheritdoc IVault
   */
  function withdrawFromVault(address asset, uint256 amount) external override onlyMain nonReentrant {
    IPool AaveL1Pool = IPool(IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider()).getPool());
    uint256 withdrawnAmount = AaveL1Pool.withdraw(asset, amount, msg.sender);
    assert(withdrawnAmount == amount);
  }
}
