// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IAddressesProvider {
  event AaveAddressProviderSet(address oldAaveAddressProvider, address newAaveAddressProvider);
  event AaveEncoderSet(address oldAaveEncoder, address newAaveEncoder);
  event UniFactorySet(address oldUniFactory, address newUniFactory);
  event SuperAdminSet(address oldSuperAdmin, address newSuperAdmin);

  function getAaveAddressProvider() external view returns (address);

  function setAaveAddressProvider(address newAaveAddressProvider) external;

  function getAaveEncoder() external view returns (address);

  function setAaveEncoder(address newAaveEncoder) external;

  function getUniFactory() external view returns (address);

  function setUniFactory(address newUniFactory) external;

  function getSuperAdmin() external view returns (address);

  function setSuperAdmin(address newSuperAdmin) external;
}
