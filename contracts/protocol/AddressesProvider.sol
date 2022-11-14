// SPDX-License-Identifier: UNLICESED
pragma solidity ^0.8.10;

import {Ownable} from "../libraries/utils/Ownable.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";

contract AddressesProvider is Ownable, IAddressesProvider {
  //Flaex Stuff:
  address SuperAdmin;
  address Main;

  //AAVE Stuff:
  address AaveAddressProvider;
  address AaveEncoder;

  //Uniswap Stuff
  address UniFactory;

  constructor(address Owner, address Admin) {
    transferOwnership(Owner);
    SuperAdmin = Admin;
  }

  function getAaveAddressProvider() external view override returns (address) {
    return AaveAddressProvider;
  }

  function setAaveAddressProvider(address newAaveAddressProvider) external override onlyOwner {
    address oldAaveAddressProvider = AaveAddressProvider;
    AaveAddressProvider = newAaveAddressProvider;
    emit AaveAddressProviderSet(oldAaveAddressProvider, newAaveAddressProvider);
  }

  function getAaveEncoder() external view override returns (address) {
    return AaveEncoder;
  }

  function setAaveEncoder(address newAaveEncoder) external override onlyOwner {
    address oldAaveEncoder = AaveEncoder;
    AaveEncoder = newAaveEncoder;
    emit AaveEncoderSet(oldAaveEncoder, newAaveEncoder);
  }

  function getUniFactory() external view override returns (address) {
    return UniFactory;
  }

  function setUniFactory(address newUniFactory) external override onlyOwner {
    address oldUniFactory = UniFactory;
    UniFactory = newUniFactory;
    emit UniFactorySet(oldUniFactory, newUniFactory);
  }

  function getSuperAdmin() external view override returns (address) {
    return SuperAdmin;
  }

  function setSuperAdmin(address newSuperAdmin) external override onlyOwner {
    address oldSuperAdmin = SuperAdmin;
    SuperAdmin = newSuperAdmin;
    emit SuperAdminSet(oldSuperAdmin, newSuperAdmin);
  }

  function getMain() external view override returns (address) {
    return Main;
  }

  function setMain(address newMain) external override onlyOwner {
    address oldMain = Main;
    Main = newMain;
    emit MainSet(oldMain, newMain);
  }
}
