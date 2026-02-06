// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PayrollManagerTest is Test {
    PayrollManager public payrollManager;
    Treasury public treasury;
    MockERC20 public usdc;

    address public admin = address(this);
    address public company = makeAddr("company");
    address public keeper = makeAddr("keeper");
    address public manager = makeAddr("manager");
    address public employee1 = makeAddr("employee1");
    address public employee2 = makeAddr("employee2");

    bytes32 public sessionId = keccak256("session1");
    uint256 public constant TOTAL_AMOUNT = 10_000e6;

    function setUp() public {
        treasury = new Treasury();
        payrollManager = new PayrollManager(address(treasury));
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Setup roles on Treasury
        treasury.grantRole(treasury.MANAGER_ROLE(), address(payrollManager));
        treasury.addSupportedToken(address(usdc));

        // Setup roles on PayrollManager
        payrollManager.grantRole(payrollManager.COMPANY_ROLE(), company);
        payrollManager.grantRole(payrollManager.KEEPER_ROLE(), keeper);

        // Fund treasury
        usdc.mint(admin, TOTAL_AMOUNT);
        usdc.approve(address(treasury), TOTAL_AMOUNT);
        treasury.deposit(address(usdc), TOTAL_AMOUNT);
    }

    // --- Session Creation Tests ---

    function test_CreateSession() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(session.id, sessionId);
        assertEq(session.company, company);
        assertEq(session.token, address(usdc));
        assertEq(session.totalAmount, TOTAL_AMOUNT);
        assertEq(session.employeeCount, 10);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Pending));
    }

    function test_CreateSessionLocksBalanceInTreasury() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        assertEq(treasury.availableBalance(address(usdc)), 0);
        assertEq(treasury.totalLockedBalance(address(usdc)), TOTAL_AMOUNT);
    }

    function test_CreateSessionRevertsForDuplicateId() public {
        vm.startPrank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT / 2, 5);

        vm.expectRevert(PayrollManager.SessionAlreadyExists.selector);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT / 2, 5);
        vm.stopPrank();
    }

    function test_CreateSessionRevertsForNonCompany() public {
        vm.prank(employee1);
        vm.expectRevert();
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);
    }

    // --- Session Start Tests ---

    function test_StartSession() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Active));
        assertGt(session.startTime, 0);
        assertTrue(payrollManager.isSessionActive(sessionId));
    }

    function test_StartSessionRevertsForInvalidStatus() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        vm.expectRevert(PayrollManager.InvalidStatus.selector);
        payrollManager.startSession(sessionId);
    }

    // --- Session Close Tests ---

    function test_CloseSession() public {
        bytes32 stateRoot = keccak256("stateRoot");

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Closing));
        assertEq(session.stateRoot, stateRoot);
        assertGt(session.endTime, 0);
    }

    function test_CloseSessionRevertsForZeroStateRoot() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        vm.expectRevert(PayrollManager.InvalidStateRoot.selector);
        payrollManager.closeSession(sessionId, bytes32(0));
    }

    // --- Session Settlement Tests ---

    function test_SettleSession() public {
        bytes32 stateRoot = keccak256("stateRoot");

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        vm.prank(keeper);
        payrollManager.settleSession(sessionId);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Settled));
    }

    function test_SettleSessionReleasesFunds() public {
        bytes32 stateRoot = keccak256("stateRoot");

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        vm.prank(keeper);
        payrollManager.settleSession(sessionId);

        assertEq(treasury.availableBalance(address(usdc)), TOTAL_AMOUNT);
        assertEq(treasury.totalLockedBalance(address(usdc)), 0);
    }

    // --- Session Cancellation Tests ---

    function test_CancelPendingSession() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.cancelSession(sessionId);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Cancelled));
        assertEq(treasury.availableBalance(address(usdc)), TOTAL_AMOUNT);
    }

    function test_CancelActiveSession() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.cancelSession(sessionId);

        PayrollManager.Session memory session = payrollManager.getSession(sessionId);
        assertEq(uint256(session.status), uint256(PayrollManager.SessionStatus.Cancelled));
    }

    function test_CancelSessionRevertsIfSettled() public {
        bytes32 stateRoot = keccak256("stateRoot");

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        vm.prank(keeper);
        payrollManager.settleSession(sessionId);

        vm.prank(company);
        vm.expectRevert(PayrollManager.InvalidStatus.selector);
        payrollManager.cancelSession(sessionId);
    }

    // --- Claim Payout Tests ---

    function test_ClaimPayout() public {
        // Create merkle tree
        bytes32 employeeId = keccak256("employee1");
        uint256 amount = 1000e6;
        bytes32 leaf = keccak256(abi.encodePacked(employeeId, employee1, amount));
        bytes32 stateRoot = leaf; // Single leaf tree

        // Setup session
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        // Fund PayrollManager for claim
        usdc.mint(address(payrollManager), amount);

        // Claim
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(employee1);
        payrollManager.claimPayout(sessionId, employeeId, employee1, amount, proof);

        assertTrue(payrollManager.claimed(sessionId, employeeId));
        assertEq(usdc.balanceOf(employee1), amount);
    }

    function test_ClaimPayoutRevertsForDoubleClaim() public {
        bytes32 employeeId = keccak256("employee1");
        uint256 amount = 1000e6;
        bytes32 leaf = keccak256(abi.encodePacked(employeeId, employee1, amount));
        bytes32 stateRoot = leaf;

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        usdc.mint(address(payrollManager), amount * 2);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(employee1);
        payrollManager.claimPayout(sessionId, employeeId, employee1, amount, proof);

        vm.prank(employee1);
        vm.expectRevert(PayrollManager.AlreadyClaimed.selector);
        payrollManager.claimPayout(sessionId, employeeId, employee1, amount, proof);
    }

    function test_ClaimPayoutRevertsForInvalidProof() public {
        bytes32 employeeId = keccak256("employee1");
        uint256 amount = 1000e6;
        bytes32 stateRoot = keccak256("differentRoot");

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(employee1);
        vm.expectRevert(PayrollManager.InvalidProof.selector);
        payrollManager.claimPayout(sessionId, employeeId, employee1, amount, proof);
    }

    // --- View Tests ---

    function test_GetSessionStatus() public {
        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        assertEq(uint256(payrollManager.getSessionStatus(sessionId)), uint256(PayrollManager.SessionStatus.Pending));
    }

    function test_VerifyAllocation() public {
        bytes32 employeeId = keccak256("employee1");
        uint256 amount = 1000e6;
        bytes32 leaf = keccak256(abi.encodePacked(employeeId, employee1, amount));
        bytes32 stateRoot = leaf;

        vm.prank(company);
        payrollManager.createSession(sessionId, address(usdc), TOTAL_AMOUNT, 10);

        vm.prank(company);
        payrollManager.startSession(sessionId);

        vm.prank(company);
        payrollManager.closeSession(sessionId, stateRoot);

        bytes32[] memory proof = new bytes32[](0);
        assertTrue(payrollManager.verifyAllocation(sessionId, employeeId, employee1, amount, proof));
    }
}
