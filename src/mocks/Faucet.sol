// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IERC20Metadata as IERC20} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract Faucet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 internal usdc;

    uint256 public claimAmount;

    uint256 public requiredETHAmount;

    event ClaimAmountSet(uint256 amount);

    event ETHAmountSet(uint256 amount);

    /// @param _usdc mock USDC token address
    constructor(IERC20 _usdc) {
        usdc = _usdc;

        claimAmount = 2000 * (10 ** usdc.decimals());

        requiredETHAmount = 0.001 ether;
    }

    function claim() external payable {
        require(msg.value >= requiredETHAmount, "Lower ETH Amount to claim USDC");

        usdc.safeTransfer(msg.sender, claimAmount);
    }

    function setETHAmount(uint256 _newAmount) external onlyOwner {
        require(_newAmount >= 0, "Invalid ETH amount");
        requiredETHAmount = _newAmount;

        emit ETHAmountSet(_newAmount);
    }

    function setClaimAmount(uint256 _newAmount) external onlyOwner {
        require(_newAmount > 0, "Invalid claim amount");
        claimAmount = _newAmount;

        emit ClaimAmountSet(_newAmount);
    }

    function withdrawETH(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid address");
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success,) = recipient.call{value: balance}("");
        require(success, "Transfer failed");
    }
}
