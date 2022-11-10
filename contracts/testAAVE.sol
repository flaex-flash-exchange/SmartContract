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

contract testAAVE is ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;

  address admin;
  IPoolAddressesProvider AddressProvider;
  IL2Pool Pool;
  IPool L1Pool;
  L2Encoder Encoder;
  uint16 referralCode;
  uint8 interestRateMode;

  constructor(
    address _AddressProvider,
    address _Encoder,
    uint16 _referralCode, //0
    uint8 _interestRateMode //Stable: 1, Variable: 2, input: 2
  ) {
    admin = payable(msg.sender);
    AddressProvider = IPoolAddressesProvider(_AddressProvider);
    address _Pool = AddressProvider.getPool();
    Pool = IL2Pool(_Pool);
    L1Pool = IPool(_Pool);
    Encoder = L2Encoder(_Encoder);
    referralCode = _referralCode;
    interestRateMode = _interestRateMode;
  }

  struct OrderInfo {
    // uint128 orderID; // global order ID
    // address asset; // asset to Long/Short, do I need it?
    address aTokenAddress;
    uint256 aTokenAmount;
    uint256 supplyIndex;
    address debtTokenAddress;
    uint256 debtTokenAmount;
    uint256 variableBorrowIndex;
    // uint8 debtTokenType; // 0:none, 1: stable, 2: variable, dont need this because assume all debt is variable
  }
  //map user's address => collateralToken => OrderInfo
  mapping(address => mapping(address => OrderInfo)) public userPosition;

  function _accrueInterest(address user, address asset) internal returns (uint256, uint256) {
    //get user's info
    OrderInfo memory orderInfo = userPosition[user][asset];

    //retrieve old supplyIndex & aTokenAmount
    uint256 oldSupplyIndex = orderInfo.supplyIndex;
    uint256 oldATokenAmount = orderInfo.aTokenAmount;

    //retrive old variableBorrowIndex & debtTokenAmount
    uint256 oldVariableBorrowIndex = orderInfo.variableBorrowIndex;
    uint256 oldDebtTokenAmount = orderInfo.debtTokenAmount;

    uint256 newATokenAmount = 0;
    uint256 newDebtTokenAmount = 0;

    if (oldATokenAmount != 0) {
      //get new borrowIndex, should get normalizedIncome here because of real-time
      // uint256 newSupplyIndex = Reserve.liquidityIndex;
      uint256 newSupplyIndex = L1Pool.getReserveNormalizedIncome(asset);

      //update user's new aTokenAmount & borrowIndex
      newATokenAmount = oldATokenAmount * (newSupplyIndex.rayDiv(oldSupplyIndex));
      (orderInfo.supplyIndex, orderInfo.aTokenAmount) = (newSupplyIndex, newATokenAmount);
    }

    if (oldDebtTokenAmount != 0) {
      uint256 newVariableBorrowIndex = L1Pool.getReserveNormalizedVariableDebt(asset);

      //update:
      newDebtTokenAmount = oldDebtTokenAmount * (newVariableBorrowIndex.rayDiv(oldVariableBorrowIndex));
      (orderInfo.variableBorrowIndex, orderInfo.debtTokenAmount) = (newVariableBorrowIndex, newDebtTokenAmount);
    }

    //get ReserveData
    //DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    //write to storage:
    userPosition[user][asset] = orderInfo;

    return (newATokenAmount, newDebtTokenAmount);
  }

  function Supply(address asset, uint256 amount) external returns (bool) {
    //basic check
    require(amount > 0, "Invalid_Amount");

    //accrueInterestSupply()
    _accrueInterest(msg.sender, asset);

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
    OrderInfo memory orderInfo = userPosition[msg.sender][asset];

    uint256 oldATokenAmount = orderInfo.aTokenAmount;

    //get new Info
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    orderInfo.aTokenAddress = Reserve.aTokenAddress;
    orderInfo.aTokenAmount = amount + oldATokenAmount;
    orderInfo.supplyIndex = Reserve.liquidityIndex;

    //write
    userPosition[msg.sender][asset] = orderInfo;

    return true;
  }

  function Borrow(address asset, uint256 amount) external returns (bool) {
    //basic check
    require(amount > 0, "Invalid_Amount");

    //accrueInterestSupply()
    _accrueInterest(msg.sender, asset);

    //encode:
    bytes32 encodedParams = Encoder.encodeBorrowParams(asset, amount, interestRateMode, referralCode);

    //call borrow()
    Pool.borrow(encodedParams);

    //record:
    //get old
    OrderInfo memory orderInfo = userPosition[msg.sender][asset];

    uint256 oldDebtToken = orderInfo.debtTokenAmount;

    //get new info:
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    orderInfo.debtTokenAddress = Reserve.variableDebtTokenAddress;
    orderInfo.debtTokenAmount = amount + oldDebtToken;
    orderInfo.variableBorrowIndex = Reserve.variableBorrowIndex;

    //write
    userPosition[msg.sender][asset] = orderInfo;

    return true;
  }

  function Repay(address asset, uint256 amount) external returns (bool) {
    //uint(256) for max
    //basic check
    require(amount > 0, "Invalid_Amount");

    //accrueInterestSupply()
    _accrueInterest(msg.sender, asset);

    //transfer amount from msg.sender to address(this)
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

    //Encoder
    bytes32 encodedParams = Encoder.encodeBorrowParams(asset, amount, interestRateMode, referralCode);

    // call repay
    Pool.repay(encodedParams);

    //record
    //get old:
    OrderInfo memory orderInfo = userPosition[msg.sender][asset];

    uint256 oldDebtToken = orderInfo.debtTokenAmount;

    //get new info:
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    orderInfo.debtTokenAmount = amount == type(uint256).max ? 0 : oldDebtToken - amount;
    orderInfo.variableBorrowIndex = amount == 0 ? 0 : Reserve.variableBorrowIndex;

    //write
    userPosition[msg.sender][asset] = orderInfo;

    return true;
  }

  function Withdraw(address asset, uint256 amount) external nonReentrant returns (bool) {
    //uint(256) for max
    //basic check
    require(amount > 0, "Invalid_Amount");

    //accrueInterestSupply()
    _accrueInterest(msg.sender, asset);

    //Encoder
    bytes32 encodedParams = Encoder.encodeWithdrawParams(asset, amount);

    //call withdraw()
    Pool.withdraw(encodedParams);

    //record
    //getold
    OrderInfo memory orderInfo = userPosition[msg.sender][asset];

    uint256 oldATokenAmount = orderInfo.aTokenAmount;

    //get new info:
    DataTypes.ReserveData memory Reserve = L1Pool.getReserveData(asset);

    orderInfo.aTokenAmount = amount == type(uint256).max ? 0 : oldATokenAmount - amount;
    orderInfo.supplyIndex = amount == type(uint256).max ? 0 : Reserve.liquidityIndex;

    //write
    userPosition[msg.sender][asset] = orderInfo;

    return true;
  }

  receive() external payable {}
}
