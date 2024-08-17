// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./utils/IntegrationSetup.sol";

contract BatchTransferTest is IntegrationSetup {
    using DecimalMath for uint256;

    address charlie = address(0xcc);
    uint256 charlieAcc;
    address dave = address(0xcc);
    uint256 daveAcc;

    int256 amountOfContracts = 1e18;

    uint64 expiry;

    function setUp() public {
        _setupIntegration();

        charlieAcc = positionManager.createSubAccount(charlie);
        vm.prank(charlie);
        positionManager.approve(address(this), charlieAcc);
        vm.stopPrank();

        daveAcc = positionManager.createSubAccount(dave);
        vm.prank(dave);
        positionManager.approve(address(this), daveAcc);
        vm.stopPrank();

        _depositUSD(address(alice), aliceAcc, DEFAULT_DEPOSIT);
        _depositUSD(address(bob), bobAcc, DEFAULT_DEPOSIT);
        _depositUSD(address(charlie), charlieAcc, DEFAULT_DEPOSIT);
        _depositUSD(address(dave), daveAcc, DEFAULT_DEPOSIT);

        expiry = uint64(block.timestamp + 4 weeks);

        _setForwardPrice("weth", expiry, uint256(ETH_PRICE));
        _setDefaultSVIForExpiry("weth", expiry);
    }

    function test_threeWayNoOIFee() public {
        uint256 callStrike = 2000e18;
        uint112 callId = getSubId(uint16(markets["weth"].id), expiry, callStrike, true);

        (int256 aliceBal, int256 bobBal, int256 charlieBal, int256 daveBal) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](3);

        transferBatch[0] = IAsset.BalanceTransfer({
            from: aliceAcc,
            to: bobAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[1] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[2] = IAsset.BalanceTransfer({
            from: charlieAcc,
            to: aliceAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        positionManager.batchTransfers(transferBatch, "");
        (aliceBal, bobBal, charlieBal, daveBal) = _getAllUSDXBalances();

        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT);
    }

    function test_threeWayTradeITMCall() public {
        uint256 oiFee = option.OIFee().multiplyDecimal(_getSpot());

        uint256 callStrike = 2000e18;
        uint112 callId = getSubId(uint16(markets["weth"].id), expiry, callStrike, true);

        (int256 aliceBal, int256 bobBal, int256 charlieBal, int256 daveBal) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](2);

        transferBatch[0] = IAsset.BalanceTransfer({
            from: aliceAcc,
            to: bobAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[1] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        positionManager.batchTransfers(transferBatch, "");

        vm.warp(expiry);
        int256 priceIncrease = 1000e18;

        _updateAllOracles(uint256(ETH_PRICE + priceIncrease));

        positionManager.exercise(aliceAcc);
        positionManager.exercise(bobAcc);
        positionManager.exercise(charlieAcc);

        (aliceBal, bobBal, charlieBal, daveBal) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT - uint256(priceIncrease) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT + uint256(priceIncrease) - oiFee);
    }

    function test_threeWayTradeITMPut() public {
        uint256 oiFee = option.OIFee().multiplyDecimal(_getSpot());

        uint256 putStrike = 2000e18;
        uint112 putId = getSubId(uint16(markets["weth"].id), expiry, putStrike, false);

        (int256 aliceBal, int256 bobBal, int256 charlieBal, int256 daveBal) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](2);

        transferBatch[0] =
            IAsset.BalanceTransfer({from: aliceAcc, to: bobAcc, asset: option, subId: putId, amount: amountOfContracts});

        transferBatch[1] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: putId,
            amount: amountOfContracts
        });

        positionManager.batchTransfers(transferBatch, "");

        vm.warp(expiry);

        int256 priceDecrease = 1000e18;
        _updateAllOracles(uint256(ETH_PRICE - priceDecrease));

        positionManager.exercise(aliceAcc);
        positionManager.exercise(bobAcc);
        positionManager.exercise(charlieAcc);

        (aliceBal, bobBal, charlieBal, daveBal) = _getAllUSDXBalances();

        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT - uint256(priceDecrease) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT + uint256(priceDecrease) - oiFee);
    }

    function test_threeWayOTMCall() public {
        uint256 oiFee = option.OIFee().multiplyDecimal(_getSpot());
        int256 premium = 1000e18;

        uint256 callStrike = 2000e18;
        uint112 callId = getSubId(uint16(markets["weth"].id), expiry, callStrike, true);

        (int256 aliceBal, int256 bobBal, int256 charlieBal,) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](4);

        transferBatch[0] = IAsset.BalanceTransfer({
            from: aliceAcc,
            to: bobAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[1] = IAsset.BalanceTransfer({from: bobAcc, to: aliceAcc, asset: usdx, subId: 0, amount: premium});

        transferBatch[2] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[3] =
            IAsset.BalanceTransfer({from: charlieAcc, to: bobAcc, asset: usdx, subId: 0, amount: premium});

        positionManager.batchTransfers(transferBatch, "");
        (aliceBal, bobBal, charlieBal,) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT + uint256(premium) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT - uint256(premium) - oiFee);

        vm.warp(expiry);

        int256 priceDecrease = 1000e18;
        _updateAllOracles(uint256(ETH_PRICE - priceDecrease));

        positionManager.exercise(aliceAcc);
        positionManager.exercise(bobAcc);
        positionManager.exercise(charlieAcc);

        (aliceBal, bobBal, charlieBal,) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT + uint256(premium) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT - uint256(premium) - oiFee);
    }

    function test_threeWayOTMPut() public {
        uint256 oiFee = option.OIFee().multiplyDecimal(_getSpot());
        int256 premium = 1000e18;

        uint256 putStrike = 2000e18;
        uint112 putId = getSubId(uint16(markets["weth"].id), expiry, putStrike, false);

        (int256 aliceBal, int256 bobBal, int256 charlieBal,) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](4);

        transferBatch[0] =
            IAsset.BalanceTransfer({from: aliceAcc, to: bobAcc, asset: option, subId: putId, amount: amountOfContracts});

        transferBatch[1] = IAsset.BalanceTransfer({from: bobAcc, to: aliceAcc, asset: usdx, subId: 0, amount: premium});

        transferBatch[2] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: putId,
            amount: amountOfContracts
        });

        transferBatch[3] =
            IAsset.BalanceTransfer({from: charlieAcc, to: bobAcc, asset: usdx, subId: 0, amount: premium});

        positionManager.batchTransfers(transferBatch, "");
        (aliceBal, bobBal, charlieBal,) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT + uint256(premium) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT - uint256(premium) - oiFee);

        vm.warp(expiry);

        int256 priceIncrease = 1000e18;
        _updateAllOracles(uint256(ETH_PRICE + priceIncrease));

        positionManager.exercise(aliceAcc);
        positionManager.exercise(bobAcc);
        positionManager.exercise(charlieAcc);

        (aliceBal, bobBal, charlieBal,) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT + uint256(premium) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT - uint256(premium) - oiFee);
    }

    function test_fourWayITMCall() public {
        uint256 oiFee = option.OIFee().multiplyDecimal(_getSpot());

        uint256 callStrike = 2000e18;
        uint112 callId = getSubId(uint16(markets["weth"].id), expiry, callStrike, true);

        (int256 aliceBal, int256 bobBal, int256 charlieBal, int256 daveBal) = _getAllUSDXBalances();

        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](3);

        transferBatch[0] = IAsset.BalanceTransfer({
            from: aliceAcc,
            to: bobAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[1] = IAsset.BalanceTransfer({
            from: bobAcc,
            to: charlieAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        transferBatch[2] = IAsset.BalanceTransfer({
            from: charlieAcc,
            to: daveAcc,
            asset: option,
            subId: callId,
            amount: amountOfContracts
        });

        positionManager.batchTransfers(transferBatch, "");

        vm.warp(expiry);

        int256 priceIncrease = 1000e18;

        _updateAllOracles(uint256(ETH_PRICE + priceIncrease));
        positionManager.exercise(aliceAcc);
        positionManager.exercise(bobAcc);
        positionManager.exercise(charlieAcc);
        positionManager.exercise(daveAcc);

        (aliceBal, bobBal, charlieBal, daveBal) = _getAllUSDXBalances();
        assertEq(uint256(aliceBal), DEFAULT_DEPOSIT - uint256(priceIncrease) - oiFee);
        assertEq(uint256(bobBal), DEFAULT_DEPOSIT);
        assertEq(uint256(charlieBal), DEFAULT_DEPOSIT);
        assertEq(uint256(daveBal), DEFAULT_DEPOSIT + uint256(priceIncrease) - oiFee);
    }

    function _getAllUSDXBalances()
        internal
        view
        returns (int256 aliceBal, int256 bobBal, int256 charlieBal, int256 daveBal)
    {
        aliceBal = getUSDXBalance(aliceAcc);
        bobBal = getUSDXBalance(bobAcc);
        charlieBal = getUSDXBalance(charlieAcc);
        daveBal = getUSDXBalance(daveAcc);
    }

    function _getSpot() internal view returns (uint256) {
        uint256 spot = markets["weth"].spotOracle.getSpot();
        return spot;
    }

    function _updateAllOracles(uint256 price) internal {
        _setSpotPrice("weth", uint96(price));

        _setSettlementPrice("weth", expiry, price);
    }
}
