// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

interface IVault {
  event feeToVault(address asset, uint256 amount, bool isShareable);
  event assetWithdrawn(address asset, uint256 amount);

  function setUsedAsCollateral(address asset) external;

  function approveInvestor() external;

  function approveDelagationMain(address debtToken) external;

  function setActiveAssets(address[] memory Assets) external;

  function getActiveAssets() external view returns (address[] memory);

  function transferFeeToVault(
    address asset,
    uint256 amount,
    bool isShareable
  ) external;

  function withdrawFromVault(address asset, uint256 amount) external;

  function withdrawToInvestor(
    address withdrawer,
    address asset,
    uint256 amount
  ) external;

  function claimYieldToInvestor(
    address asset,
    address claimer,
    uint256 amount
  ) external;

  function getYieldInfo(address asset)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    );
}
