// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../src/Option.sol";
import "../../src/Liquidation.sol";
import "../../src/Hub.sol";
import "../../src/interfaces/IInsuranceFund.sol";
import "../../src/PositionManager.sol";
import "../mocks/MockOracles.sol";
import "../../src/mocks/MockERC20.sol";

contract OptionPayoffTest is Test {
    Option option;

    IHub public hub;

    ILiquidation public liquidation;

    PositionManager positionManager;

    MockOracles oracle;

    int256 public constant UPPER_PRICE = 1e42;
    uint256 defaultExpiry = block.timestamp + 2 weeks;
    uint256 strike = 1000e18;
    uint256 callId;
    uint256 putId;
    uint256 marketId = 1;

    function setUp() public {
        oracle = new MockOracles();

        hub = new Hub();

        address managerAddress = computeCreateAddress(address(this), 5);

        liquidation = new Liquidation(PositionManager(managerAddress), IInsuranceFund(address(0)));
        option = new Option(hub, PositionManager(managerAddress), liquidation);

        positionManager = new PositionManager(
            hub, IUSDX(address(0)), option, liquidation, address(this), "Margin Accounts", "MarginNFTs"
        );

        hub.setProtocol(positionManager, IUSDX(address(0)), option, liquidation, IInsuranceFund(address(0)));

        positionManager.createMarket("ETH");

        option.setForwardOracle(uint16(marketId), address(oracle));

        callId = option.encodingSubId(marketId, defaultExpiry, strike, true);
        putId = option.encodingSubId(marketId, defaultExpiry, strike, false);
    }

    function test_calcPayOffITMCall() external {
        (, uint256 expiry,,) = option.decodingSubId(uint112(callId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(strike) + 200e18;
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(callId, 1e18);

        assertEq(uint256(payout), 200e18);
    }

    function test_calcPayOffOTMCall() external {
        (, uint256 expiry,,) = option.decodingSubId(uint96(callId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(strike) - 200e18;
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(callId, 1e18);

        assertEq(uint256(payout), 0);
    }

    function test_calcPayOffITMPut() external {
        (, uint256 expiry,,) = option.decodingSubId(uint96(putId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(strike) - 200e18;
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(putId, 1e18);

        assertEq(uint256(payout), 200e18);
    }

    function test_calcPayOffOTMPut() external {
        (, uint256 expiry,,) = option.decodingSubId(uint96(putId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(strike) + 200e18;
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(putId, 1e18);

        assertEq(uint256(payout), 0);
    }

    function test_cannotcalcPayOffIfPriceNotSet() external {
        (, uint256 expiry,,) = option.decodingSubId(uint96(callId));
        assertGt(expiry, block.timestamp);
        (int256 payout, bool priceSettled) = option.calculatePayOff(callId, 1e18);

        assertEq(payout, 0);
        assertEq(priceSettled, false);
    }

    function testFuzz_ITMCall(int256 priceDiff) external {
        vm.assume(priceDiff >= 0 && priceDiff <= UPPER_PRICE);
        (, uint256 expiry,,) = option.decodingSubId(uint96(callId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(int256(strike) + priceDiff);
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(callId, 1e18);

        assertEq(uint256(payout), uint256(spotPrice) - strike);
    }

    function testFuzz_OTMCall(int256 priceDiff) external {
        vm.assume(priceDiff >= 0 && priceDiff <= int256(strike));
        (, uint256 expiry,,) = option.decodingSubId(uint96(callId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(int256(strike) - priceDiff);
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(callId, 1e18);

        assertEq(uint256(payout), 0);
    }

    function testFuzz_ITMPut(int256 priceDiff) external {
        vm.assume(priceDiff >= 0 && priceDiff < int256(strike));
        (, uint256 expiry,,) = option.decodingSubId(uint96(putId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(int256(strike) - priceDiff);
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(putId, 1e18);

        assertEq(uint256(payout), strike - uint256(spotPrice));
    }

    function testFuzz_OTMPut(int256 priceDiff) external {
        vm.assume(priceDiff >= 0 && priceDiff <= UPPER_PRICE);
        (, uint256 expiry,,) = option.decodingSubId(uint96(putId));

        vm.warp(expiry);
        uint256 spotPrice = uint256(int256(strike) + priceDiff);
        oracle.setSettlementPrice(expiry, spotPrice);

        (int256 payout,) = option.calculatePayOff(putId, 1e18);

        assertEq(uint256(payout), 0);
    }
}
