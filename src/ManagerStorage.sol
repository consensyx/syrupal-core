// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHub} from "./interfaces/IHub.sol";
import {IUSDX} from "./interfaces/IUSDX.sol";
import {IOption} from "./interfaces/IOption.sol";
import {ILiquidation} from "./interfaces/ILiquidation.sol";

import {ISpotOracle} from "./oracle/interfaces/ISpotOracle.sol";
import {IForwardOracle} from "./oracle/interfaces/IForwardOracle.sol";
import {IVolatilityOracle} from "./oracle/interfaces/IVolatilityOracle.sol";

///@title Manager Storage Contract
/// @dev This abstract contract defines all the storage of position manager.
abstract contract ManagerStorage {
    bytes32 internal constant TRANSIENT_SUB_TYPE_HASH = keccak256("transientStorage(uint256 subAccount)");

    bytes32 internal constant TRANSIENT_MKT_TYPE_HASH = keccak256("transientStorage(uint256 marketId)");

    bytes32 internal constant TRANSIENT_EXP_TYPE_HASH = keccak256("transientStorage(uint256 marketId, uint256 expiry)");

    /// @dev The central Hub contract address
    IHub public hub;

    /// @dev The USDX contract address
    IUSDX public immutable usdx;

    /// @dev The Option contract address
    IOption public immutable option;

    /// @dev The Liquidation contract address
    ILiquidation public liquidation;

    /// @dev The stablecoin oracle address
    ISpotOracle public stableOracle;

    /// @dev Parameters to handle de-pegging of the stablecoin, only for initial margin
    DepegParams public depegParams;

    /// @notice The 'operator' is responsible for executing all contract key parameters and role updates, similar to the Owner
    address public operator;

    /// @dev Last transaction ID updated by the manager, to prevent receive duplicate data
    uint256 internal lastTxId;

    uint256 constant UNIT = 1e18;

    /// @dev ID of the latest market created in the system
    uint256 public lastMarketId;

    /// @dev Last minted sub-account ID
    uint256 public lastSubAccount;

    /// @dev Sub-account that receives protocol fee
    uint256 public feeRecipient;

    /// @dev Annualised discount = e^(-rT),  defaults to no discount (risk-free rate = 0)
    uint64 public discount = 1e18;

    /// @dev Addresses authorized to execute liquidation-related transactions
    mapping(address liquidator => bool) public trustedLiquidator;

    /// @dev Addresses authorized to execute createSubAccount transactions
    mapping(address executor => bool) public trustedExecutor;

    /// @dev Maps the callers whether they are exempt from open interest fees.
    mapping(address caller => bool) public feeExemption;

    /// @dev Addresses are authorized to accept customize manager data
    mapping(address receiver => bool) internal dataReceiver;

    /// @dev Trusted and low risk accounts, when they open a position, they only need to meet the maintenance margin requirements.
    mapping(address caller => bool) public mmCallerAccounts;

    /// @dev Mapping of market IDs to their respective margin parameters
    mapping(uint256 marketId => MarginParams) public marginParams;

    /// @dev Mapping of market IDs to their respective spot price oracles
    mapping(uint256 marketId => ISpotOracle) public spotOracles;

    /// @dev  Mapping of market IDs to their respective forward price oracles
    mapping(uint256 marketId => IForwardOracle) public forwardOracles;

    /// @dev Mapping of market IDs to their respective volatility oracles
    mapping(uint256 marketId => IVolatilityOracle) public volOracles;

    /// @notice Parameters defining margin requirements for options
    struct MarginParams {
        uint256 MMRatio; // Maintenance margin ratio
        uint256 IMUpperRatio; // Upper limit of initial margin ratio
        uint256 IMLowerRatio; // Lower limit of initial margin ratio
    }

    /// @notice Parameters to handle situations when stablecoins depeg
    struct DepegParams {
        uint256 threshold; // Price threshold for considering depegging
        uint256 depegFactor; // Factor to increase margin requirements when depegging occurs
    }
}
