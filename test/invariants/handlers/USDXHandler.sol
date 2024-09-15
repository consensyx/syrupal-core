// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AddressSet, LibAddressSet} from "../utils/AddressSet.sol";
import {BaseHandler} from "./BaseHandler.sol";

import {USDX} from "../../../src/token/USDX.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";
import {PositionManager} from "../../../src/PositionManager.sol";

contract USDXHandler is BaseHandler {
    using LibAddressSet for AddressSet;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal deployer;

    USDX internal usdx;

    MockERC20 internal usdc;

    PositionManager internal pm;

    uint256 constant DEFAULT_USDC_SUPPLY = 1000_000e18;

    /*//////////////////////////////////////////////////////////////////////////
                                    STATE-VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    /*//////////////////////////////////////////////////////////////////////////
                                     MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier createActor() {
        // currentActor = msg.sender;
        currentActor.account = msg.sender;

        vm.startPrank(deployer);

        currentActor.subAccount = pm.createSubAccount(msg.sender);
        usdc.mint(msg.sender, DEFAULT_USDC_SUPPLY);

        vm.stopPrank();

        // _actors.add(msg.sender);
        _actors.push(currentActor);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(USDX _usdx, MockERC20 _usdc, PositionManager _pm, address _deployer) BaseHandler() {
        usdx = _usdx;

        usdc = _usdc;

        pm = _pm;

        deployer = _deployer;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 HANDLER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function deposit(uint256 amount) public countCall("deposit") createActor {
        amount = bound(amount, 0, usdc.balanceOf(currentActor.account));

        vm.prank(currentActor.account);
        usdx.deposit(currentActor.subAccount, amount);

        ghost_depositSum += amount;
    }

    function withdraw(uint256 actorIndexSeed, uint256 amount) public countCall("withdraw") useActor(actorIndexSeed) {}
}
