// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcRouter} from "../src/ArcRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockBridgeAdapter} from "./mocks/MockBridgeAdapter.sol";

contract ArcRouterTest is Test {
    ArcRouter public arcRouter;
    MockERC20 public usdc;
    MockBridgeAdapter public bridgeAdapter;

    address public admin = address(this);
    address public manager = makeAddr("manager");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");

    uint256 public constant DEST_CHAIN_ID = 42_161; // Arbitrum
    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        arcRouter = new ArcRouter();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        bridgeAdapter = new MockBridgeAdapter();

        // Setup roles
        arcRouter.grantRole(arcRouter.MANAGER_ROLE(), manager);

        // Add supported chain
        arcRouter.addSupportedChain(DEST_CHAIN_ID, address(bridgeAdapter));

        // Fund manager
        usdc.mint(manager, INITIAL_BALANCE);
    }

    // --- Same-chain Payout Tests ---

    function test_SinglePayoutSameChain() public {
        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 1000e6);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertTrue(result.success);
        assertEq(result.actualAmount, 1000e6);
        assertEq(usdc.balanceOf(recipient1), 1000e6);
    }

    function test_BatchPayoutSameChain() public {
        ArcRouter.PayoutInstruction[] memory payouts = new ArcRouter.PayoutInstruction[](2);
        payouts[0] = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });
        payouts[1] = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: recipient2,
            amount: 2000e6,
            employeeId: keccak256("emp2")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 3000e6);
        ArcRouter.PayoutResult[] memory results = arcRouter.batchPayout(payouts);
        vm.stopPrank();

        assertTrue(results[0].success);
        assertTrue(results[1].success);
        assertEq(usdc.balanceOf(recipient1), 1000e6);
        assertEq(usdc.balanceOf(recipient2), 2000e6);
    }

    // --- Cross-chain Payout Tests ---

    function test_SinglePayoutCrossChain() public {
        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: DEST_CHAIN_ID,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 1000e6);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertTrue(result.success);
        // 0.1% fee = 1e6
        assertEq(result.actualAmount, 999e6);
        assertTrue(result.bridgeTxId != bytes32(0));
    }

    function test_CrossChainPayoutDeductsFee() public {
        uint256 amount = 10_000e6;
        uint256 expectedFee = amount * 10 / 10_000; // 0.1%
        uint256 expectedAfterFee = amount - expectedFee;

        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: DEST_CHAIN_ID,
            token: address(usdc),
            recipient: recipient1,
            amount: amount,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), amount);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertEq(result.actualAmount, expectedAfterFee);
    }

    // --- Fee Calculation Tests ---

    function test_GetBridgeFeeReturnsZeroForSameChain() public view {
        uint256 fee = arcRouter.getBridgeFee(block.chainid, 1000e6);
        assertEq(fee, 0);
    }

    function test_GetBridgeFeeUsesBaseFee() public view {
        uint256 amount = 10_000e6;
        uint256 expectedFee = amount * 10 / 10_000;
        assertEq(arcRouter.getBridgeFee(DEST_CHAIN_ID, amount), expectedFee);
    }

    function test_GetBridgeFeeUsesChainOverride() public {
        arcRouter.setChainFeeOverride(DEST_CHAIN_ID, 50); // 0.5%

        uint256 amount = 10_000e6;
        uint256 expectedFee = amount * 50 / 10_000;
        assertEq(arcRouter.getBridgeFee(DEST_CHAIN_ID, amount), expectedFee);
    }

    function test_EstimateFees() public view {
        ArcRouter.PayoutInstruction[] memory payouts = new ArcRouter.PayoutInstruction[](2);
        payouts[0] = ArcRouter.PayoutInstruction({
            destChainId: DEST_CHAIN_ID,
            token: address(usdc),
            recipient: recipient1,
            amount: 10_000e6,
            employeeId: keccak256("emp1")
        });
        payouts[1] = ArcRouter.PayoutInstruction({
            destChainId: block.chainid, // same chain, no fee
            token: address(usdc),
            recipient: recipient2,
            amount: 5000e6,
            employeeId: keccak256("emp2")
        });

        (uint256 totalFees, uint256[] memory perPayoutFees) = arcRouter.estimateFees(payouts);

        assertEq(perPayoutFees[0], 10e6); // 0.1% of 10k
        assertEq(perPayoutFees[1], 0); // same chain
        assertEq(totalFees, 10e6);
    }

    // --- Error Handling Tests ---

    function test_PayoutFailsForUnsupportedChain() public {
        uint256 unsupportedChainId = 999;

        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: unsupportedChainId,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 1000e6);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertFalse(result.success);
    }

    function test_PayoutFailsForZeroRecipient() public {
        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: address(0),
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 1000e6);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertFalse(result.success);
    }

    function test_PayoutFailsForZeroAmount() public {
        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: recipient1,
            amount: 0,
            employeeId: keccak256("emp1")
        });

        vm.prank(manager);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);

        assertFalse(result.success);
    }

    function test_PayoutFailsWhenBridgeFails() public {
        bridgeAdapter.setShouldFail(true);

        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: DEST_CHAIN_ID,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.startPrank(manager);
        usdc.approve(address(arcRouter), 1000e6);
        ArcRouter.PayoutResult memory result = arcRouter.singlePayout(payout);
        vm.stopPrank();

        assertFalse(result.success);
        // Should refund on failure
        assertEq(usdc.balanceOf(manager), INITIAL_BALANCE);
    }

    // --- Access Control Tests ---

    function test_PayoutRevertsForNonManager() public {
        ArcRouter.PayoutInstruction memory payout = ArcRouter.PayoutInstruction({
            destChainId: block.chainid,
            token: address(usdc),
            recipient: recipient1,
            amount: 1000e6,
            employeeId: keccak256("emp1")
        });

        vm.prank(recipient1);
        vm.expectRevert();
        arcRouter.singlePayout(payout);
    }

    // --- Admin Tests ---

    function test_AddSupportedChain() public {
        uint256 newChainId = 10;
        MockBridgeAdapter newAdapter = new MockBridgeAdapter();

        arcRouter.addSupportedChain(newChainId, address(newAdapter));

        assertTrue(arcRouter.isSupportedChain(newChainId));
    }

    function test_RemoveSupportedChain() public {
        arcRouter.removeSupportedChain(DEST_CHAIN_ID);
        assertFalse(arcRouter.supportedChains(DEST_CHAIN_ID));
    }

    function test_SetBaseBridgeFee() public {
        arcRouter.setBaseBridgeFee(20); // 0.2%
        assertEq(arcRouter.baseBridgeFeeBps(), 20);
    }

    function test_IsSupportedChainReturnsTrueForCurrentChain() public view {
        assertTrue(arcRouter.isSupportedChain(block.chainid));
    }
}
