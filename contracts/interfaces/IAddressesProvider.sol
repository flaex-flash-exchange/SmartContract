// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IAddressesProvider {
  event AaveAddressProviderSet(address oldAaveAddressProvider, address newAaveAddressProvider);
  event AaveEncoderSet(address oldAaveEncoder, address newAaveEncoder);
  event UniFactorySet(address oldUniFactory, address newUniFactory);
  event SuperAdminSet(address oldSuperAdmin, address newSuperAdmin);
  event MainSet(address oldMain, address newMain);
  event VaultSet(address oldVault, address newVault);
  event flTokenSet(address oldFlToken, address newFlToken);

  function getAaveAddressProvider() external view returns (address);

  function setAaveAddressProvider(address newAaveAddressProvider) external;

  function getAaveEncoder() external view returns (address);

  function setAaveEncoder(address newAaveEncoder) external;

  function getUniFactory() external view returns (address);

  function setUniFactory(address newUniFactory) external;

  function getSuperAdmin() external view returns (address);

  function setSuperAdmin(address newSuperAdmin) external;

  function getMain() external view returns (address);

  function setMain(address newMain) external;

  function getVault() external view returns (address);

  function setVault(address newVault) external;

  function getInvestor() external view returns (address);

  function setInvestor(address newInvestor) external;

  function getFlToken() external view returns (address);

  function setFlToken(address newFlToken) external;
}
