// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";

import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

import {ReentrancyGuard} from "./libraries/utils/ReentrancyGuard.sol";

contract testAAVE {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;

  address admin;
  IPoolAddressesProvider AddressProvider;
  IL2Pool Pool;
  IPool L1Pool;
  L2Encoder Encoder;
  uint16 referralCode;

  constructor(
    address _AddressProvider,
    address _Encoder,
    uint16 _referralCode
  ) {
    admin = payable(msg.sender);
    AddressProvider = IPoolAddressesProvider(_AddressProvider);
    address _Pool = AddressProvider.getPool();
    Pool = IL2Pool(_Pool);
    L1Pool = IPool(_Pool);
    Encoder = L2Encoder(_Encoder);
    referralCode = _referralCode;
  }

  struct OrderInfo {
    // uint128 orderID; // global order ID
    // address asset; // asset to Long/Short, do I need it?
    address aTokenAddress;
    uint256 aTokenAmount;
    address debtTokenAddress;
    uint8 debtTokenType; // 0:none, 1: stable, 2: variable
    address debtTokenAmount;
    uint256 supplyIndex; //Normalized Income to calculate interest Rate
  }
  //map user's address => collateralToken => OrderInfo
  mapping(address => mapping(address => OrderInfo)) public userPosition;

  //map user's address => OrderInfo to test AAVE:
  mapping(address => OrderInfo) public aavePosition;

  // Map of reserves and their data (underlyingAssetOfReserve => reserveData)
  //   mapping(address => DataTypes.ReserveData) internal _reserves;

  function _accrueInterestSupply(address user, address asset) internal returns (uint256) {
    //get user's info
    OrderInfo memory oldOrderInfo = userPosition[user][asset];

    //retrieve old supplyIndex & aTokenAmount
    uint256 oldSupplyIndex = oldOrderInfo.supplyIndex;
    uint256 oldATokenAmount = oldOrderInfo.aTokenAmount;

    if (oldATokenAmount == 0) {
      return 0;
    }

    //get ReserseData
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    //get new borrowIndex, or current Liquidity Index:
    uint256 newSupplyIndex = Reserve.liquidityIndex;

    //update user's new aTokenAmount & borrowIndex
    uint256 newATokenAmount = oldATokenAmount * (newSupplyIndex.rayDiv(oldSupplyIndex));
    (oldOrderInfo.supplyIndex, oldOrderInfo.aTokenAmount) = (newSupplyIndex, newATokenAmount);

    //write to storage:
    userPosition[user][asset] = oldOrderInfo;

    return newATokenAmount;
  }

  function Supply(address asset, uint256 amount) external returns (bool) {
    //basic check
    require(amount > 0, "Invalid_Amount");

    //accrueInterestSupply()
    _accrueInterestSupply(msg.sender, asset);

    //transfer amount from msg.sender to address(this)
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

    //approve spender Pool to spend amount of asset
    IERC20(asset).approve(address(Pool), amount);

    //asset: address of underlying
    //amount is cast to uint128()
    bytes32 encodedParams = Encoder.encodeSupplyParams(asset, amount, referralCode);

    //call supply function
    Pool.supply(encodedParams);

    //record user's info
    //get old info:
    OrderInfo memory oldOrderInfo = userPosition[msg.sender][asset];

    uint256 oldATokenAmount = oldOrderInfo.aTokenAmount;

    //get new Info
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    oldOrderInfo.aTokenAddress = Reserve.aTokenAddress;
    oldOrderInfo.aTokenAmount = amount + oldATokenAmount;
    oldOrderInfo.supplyIndex = Reserve.liquidityIndex;

    userPosition[msg.sender][asset] = oldOrderInfo;

    return true;
  }

  function Borrow() external returns (bool) {
    return true;
  }

  function Repay() external returns (bool) {
    return true;
  }

  receive() external payable {}
}
