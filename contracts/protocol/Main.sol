// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

/** Logic:
 * Long TOKEN/USDC: -> Meaning collateral TOKEN, borrow USDC
    - step 1: User deposit USDC to Main
    - step 2: Main calls Uniswap Flash to 'borrow' TOKEN
    - step 3: Main collateral TOKEN to AAVE
    - step 4: Main borrow USDC + user's initial margin to repay Uniswap Flash
    *** END RESULT:
     - Collateral: TOKEN
     - Borrow: USDC

* Short TOKEN/USDC: -> Meaning collateral USDC, borrow TOKEN
    - step 1: User deposit USDC to Main
    - step 2: Main calls Uniswap Flash to borrow USDC
    - step 3: Main collateral USDC (plus user's initial margin) to AAVE
    - step 4: Main borrow TOKEN to repay Uniswap Flash
    *** END RESULT:
     - Collateral: USDC
     - Borrow: TOKEN
 */

//flaex Stuff
import {IAddressesProvider} from "../interfaces/IAddressesProvider.sol";
import {ExecutionLogic} from "../libraries/logic/ExecutionLogic.sol";
import {UpdateMarket} from "../libraries/logic/UpdateMarket.sol";
import {ReentrancyGuard} from "../libraries/utils/ReentrancyGuard.sol";
import {MainStorage} from "../storage/MainStorage.sol";
import {IMain} from "../interfaces/IMain.sol";
import {Types} from "../libraries/Types.sol";

//Aave Stuff:
import {IL2Pool} from "@aave/core-v3/contracts/interfaces/IL2Pool.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {L2Encoder} from "@aave/core-v3/contracts/misc/L2Encoder.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {GPv2SafeERC20} from "@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {WadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";

//UniSwap Stuff
import {PeripheryPayments} from "@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

//Other Stuff

/**  
  * @title User's main Interaction Point
  * @author Flaex
  * @notice User can:
    - Open/Close Long/Short
    - Supply extra Stable Coin
    - Liquidate others
  * @dev Admin functions callable as defined in AddressesProvider
 */

// contract Main is ReentrancyGuard, IUniswapV3SwapCallback, PeripheryPayments {
contract Main is MainStorage, IMain, ReentrancyGuard {
  using GPv2SafeERC20 for IERC20;
  using WadRayMath for uint256;

  IAddressesProvider public immutable FLAEX_PROVIDER;
  uint256 MAX_INT = type(uint256).max;

  //only Admin can call
  modifier onlyAdmin() {
    _onlyAdmin();
    _;
  }

  function _onlyAdmin() internal view virtual {
    require(msg.sender == FLAEX_PROVIDER.getSuperAdmin(), "Invalid_Admin");
  }

  /**
   * @dev Constructor.
   * @param provider The address of the IAddressesProvider contract
   */
  constructor(IAddressesProvider provider) {
    FLAEX_PROVIDER = IAddressesProvider(provider);
    _AaveAddressProvider = IPoolAddressesProvider(FLAEX_PROVIDER.getAaveAddressProvider());
    _AavePool = IL2Pool(_AaveAddressProvider.getPool());
    _AaveL1Pool = IPool(_AaveAddressProvider.getPool());
    _AaveEncoder = L2Encoder(FLAEX_PROVIDER.getAaveEncoder());
  }

  // Initialize basic configuration
  function initialize() external onlyAdmin {
    _AaveReferralCode = 0;
    _AaveInterestRateMode = 2; //None: 0, Stable: 1, Variable: 2
  }

  /**
   * @dev basic Aprrove market, which is to:
    - approve Lending Pool to spend our asset & aToken
    - set used as collateral
   * @inheritdoc	IMain
   */
  function basicApprove(address zeroAsset, address firstAsset) external virtual override onlyAdmin {
    UpdateMarket.executeInitMarket(zeroAsset, firstAsset, _AavePool, _AaveL1Pool, _AaveEncoder);
  }

  /**
   * @dev init/update Market
   * @inheritdoc	IMain
   */
  function updateMarket(
    address Asset0,
    address Asset1,
    uint256 tradingFee,
    uint256 tradingFee_ProtocolShare,
    uint256 liquidationThreshold,
    uint256 liquidationProtocolShare
  ) external virtual override onlyAdmin {
    //in-line with uniswap
    (address zeroAsset, address firstAsset) = Asset0 < Asset1 ? (Asset0, Asset1) : (Asset1, Asset0);

    UpdateMarket.executeUpdateMarket(
      zeroAsset,
      firstAsset,
      tradingFee,
      tradingFee_ProtocolShare,
      liquidationThreshold,
      liquidationProtocolShare,
      _tradingPair
    );
  }

  /**
   * @dev drop market, isLive -> False
   * @inheritdoc	IMain
   */
  function dropMarket(address Asset0, address Asset1) external virtual override onlyAdmin {
    //in-line with uniswap
    (address zeroAsset, address firstAsset) = Asset0 < Asset1 ? (Asset0, Asset1) : (Asset1, Asset0);

    UpdateMarket.executeDropMarket(zeroAsset, firstAsset, _tradingPair);
  }

  function openLong() external {}

  receive() external payable {}
}
