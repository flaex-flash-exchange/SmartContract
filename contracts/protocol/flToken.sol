// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {IFlToken} from "../interfaces/IFlToken.sol";
import {IInvestor} from "../interfaces/IInvestor.sol";

/**
 * @title flToken
 * @author Flaex
 * @notice flToken contract
 * @dev non-transferable flToken, represents user's deposit amount and acts as a base to calculate profit share
 */

contract flToken is IFlToken {
  IAddressesProvider public immutable FLAEX_PROVIDER;

  /// @dev only Admin can call
  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getSuperAdmin(), "Invalid_Admin");
  }

  /// @dev only Investor can call
  modifier onlyInvestor() {
    _onlyInvestor();
    _;
  }

  function _onlyInvestor() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getInvestor(), "Invalid_Investor");
  }

  /**
   * @dev Constructor.
   * @param provider The address of the IAddressesProvider contract
   */
  constructor(IAddressesProvider provider) {
    FLAEX_PROVIDER = provider;
  }

  string public constant name = "Flaex Token";
  uint8 public constant decimals = 18;
  uint256 public totalSupply;

  string public symbol;
  address public underlying;

  function initialize() external onlyAdmin {
    (address acceptedAsset, string memory acceptedAssetSymbol) = IInvestor(FLAEX_PROVIDER.getInvestor())
      .getAcceptedAsset();
    underlying = acceptedAsset;
    symbol = string(abi.encodePacked("fl", acceptedAssetSymbol));
  }

  mapping(address => uint256) public balanceOf;

  /// @inheritdoc IFlToken
  function underlying_asset() public view virtual override returns (address) {
    return underlying;
  }

  /// @inheritdoc IFlToken
  function mint(address to, uint256 amount) external virtual override onlyInvestor {
    totalSupply += amount;
    balanceOf[to] += amount;

    emit Transfer(address(0), to, amount);
  }

  /// @inheritdoc IFlToken
  function burn(address from, uint256 amount) external virtual override onlyInvestor {
    totalSupply -= amount;
    balanceOf[from] -= amount;

    emit Transfer(from, address(0), amount);
  }
}
