// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAsset} from "./IAsset.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

interface IUSDX is IAsset {
    /// @notice Returns the stablecoin used by the contract
    function stablecoin() external view returns (IERC20Metadata);

    /// @notice Returns the balance of a given account
    /// @param accountId The sub-account id
    /// @return The balance of the sub-account
    function balances(uint256 accountId) external view returns (int256);

    /// @notice Deposits stablecoin into the contract
    /// @param recipientAccount The account to receive the USD asset
    /// @param assetAmount The amount of stablecoin to deposit
    function deposit(uint256 recipientAccount, uint256 assetAmount) external;

    /// @notice Withdraws stablecoin from the contract
    /// @param accountId The account to withdraw from
    /// @param stableAmount The amount of stablecoin to withdraw
    /// @param receiver The receiver for the withdraw, not sub-account
    function withdraw(uint256 accountId, uint256 stableAmount, address receiver) external;

    /// @notice Burns USDX when the issued amount exceeds the actual amount of USDC
    /// @param accountId The account id to burn from
    /// @param donateAmount The maximum amount to burn
    /// @return realDonateAmount The amount burnt
    function donate(uint256 accountId, uint256 donateAmount) external returns (uint256 realDonateAmount);

    /// @notice Returns the current exchange rate of USDC to USDX
    /// @return The current exchange rate
    function getExchangeRate() external view returns (uint256);

    /// @notice Aadjust temporary supply when exercise option
    /// @param amount The temporary change amount in usdx total supply
    function updateTemporarySupply(int256 amount) external;

    // @notice Event emitted when the fee recipient is set
    /// @param _newAcc The new fee recipient account
    event FeeRecipientSet(uint256 _newAcc);

    /// @notice Event emitted when the liquidation address is set
    /// @param liquidation The new liquidation address
    event LiquidationSet(address liquidation);

    /// @notice Event emitted when the withdraw threshold is set
    /// @param threshold The new withdraw threshold
    event WithdrawThresholdSet(uint256 threshold);

    /// @notice Event emitted when the temporarySupply value is updated
    /// @param delta The amount changed in temporarySupply
    /// @param temporarySupply The current temporarySupply value
    event TemporarySupplySet(int256 delta, int256 temporarySupply);

    /// @notice Event emitted when USDX over minted for insurance fund
    /// @param receiver The account receiving the over minted token
    /// @param excessAmount The amount of loss socialized
    event InflationaryLoss(uint256 indexed receiver, uint256 excessAmount);

    /// @notice Event emitted when a deposit is made
    /// @param accountId The account receiving the deposit
    /// @param depositor The address making the deposit
    /// @param USDAmount The amount of USD deposited
    /// @param stablecoinAmount The amount of stablecoin deposited
    event Deposit(uint256 indexed accountId, address indexed depositor, uint256 USDAmount, uint256 stablecoinAmount);

    /// @notice Event emitted when a withdrawal is made
    /// @param accountId The account making the withdrawal
    /// @param recipient The recipient of the withdrawal
    /// @param usdxAmount The amount of USDX token withdrawn
    /// @param stablecoinAmount The amount of stablecoin withdrawn
    event Withdraw(uint256 indexed accountId, address indexed recipient, uint256 usdxAmount, uint256 stablecoinAmount);
}
