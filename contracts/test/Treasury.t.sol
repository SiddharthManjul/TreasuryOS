// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TreasuryTest is Test {
    Treasury public treasury;
    MockERC20 public usdc;
    MockERC20 public usdt;

    address public admin = address(this);
    address public keeper = makeAddr("keeper");
    address public manager = makeAddr("manager");
    address public emergency = makeAddr("emergency");
    address public user = makeAddr("user");

    uint256 public constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        treasury = new Treasury();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);

        // Setup roles
        treasury.grantRole(treasury.KEEPER_ROLE(), keeper);
        treasury.grantRole(treasury.MANAGER_ROLE(), manager);
        treasury.grantRole(treasury.EMERGENCY_ROLE(), emergency);

        // Add supported tokens
        treasury.addSupportedToken(address(usdc));
        treasury.addSupportedToken(address(usdt));

        // Mint tokens
        usdc.mint(user, INITIAL_BALANCE);
        usdc.mint(admin, INITIAL_BALANCE);
    }

    // --- Deposit Tests ---

    function test_Deposit() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        assertEq(treasury.availableBalance(address(usdc)), 1000e6);
        assertEq(treasury.totalBalance(address(usdc)), 1000e6);
    }

    function test_DepositEmitsEvent() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);

        vm.expectEmit(true, true, false, true);
        emit Treasury.Deposited(address(usdc), user, 1000e6);

        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();
    }

    function test_DepositRevertsForUnsupportedToken() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "UNS", 18);
        unsupported.mint(user, 1000e18);

        vm.startPrank(user);
        unsupported.approve(address(treasury), 1000e18);

        vm.expectRevert(Treasury.TokenNotSupported.selector);
        treasury.deposit(address(unsupported), 1000e18);
        vm.stopPrank();
    }

    function test_DepositRevertsForZeroAmount() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);

        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.deposit(address(usdc), 0);
        vm.stopPrank();
    }

    // --- Withdraw Tests ---

    function test_Withdraw() public {
        // First deposit
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        // Then withdraw as admin
        treasury.withdraw(address(usdc), 500e6, admin);

        assertEq(treasury.availableBalance(address(usdc)), 500e6);
        assertEq(usdc.balanceOf(admin), INITIAL_BALANCE + 500e6);
    }

    function test_WithdrawRevertsForNonAdmin() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);

        vm.expectRevert();
        treasury.withdraw(address(usdc), 500e6, user);
        vm.stopPrank();
    }

    function test_WithdrawRevertsForInsufficientBalance() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.expectRevert(Treasury.InsufficientBalance.selector);
        treasury.withdraw(address(usdc), 2000e6, admin);
    }

    // --- Emergency Withdraw Tests ---

    function test_EmergencyWithdraw() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(emergency);
        treasury.emergencyWithdraw(address(usdc), emergency);

        assertEq(usdc.balanceOf(emergency), 1000e6);
        assertEq(treasury.totalBalance(address(usdc)), 0);
    }

    function test_EmergencyWithdrawWorksWhenPaused() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        // Pause
        vm.prank(emergency);
        treasury.pause();

        // Emergency withdraw still works
        vm.prank(emergency);
        treasury.emergencyWithdraw(address(usdc), emergency);

        assertEq(usdc.balanceOf(emergency), 1000e6);
    }

    function test_EmergencyWithdrawRevertsForNonEmergency() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        treasury.emergencyWithdraw(address(usdc), user);
    }

    // --- Lock/Release Tests ---

    function test_LockForPayroll() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        bytes32 sessionId = keccak256("session1");

        vm.prank(manager);
        treasury.lockForPayroll(sessionId, address(usdc), 500e6);

        assertEq(treasury.availableBalance(address(usdc)), 500e6);
        assertEq(treasury.totalLockedBalance(address(usdc)), 500e6);
        assertEq(treasury.lockedBalances(sessionId, address(usdc)), 500e6);
    }

    function test_LockForPayrollRevertsForInsufficientBalance() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        bytes32 sessionId = keccak256("session1");

        vm.prank(manager);
        vm.expectRevert(Treasury.InsufficientBalance.selector);
        treasury.lockForPayroll(sessionId, address(usdc), 2000e6);
    }

    function test_LockForPayrollRevertsForDuplicateSession() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        bytes32 sessionId = keccak256("session1");

        vm.startPrank(manager);
        treasury.lockForPayroll(sessionId, address(usdc), 500e6);

        vm.expectRevert(Treasury.SessionAlreadyLocked.selector);
        treasury.lockForPayroll(sessionId, address(usdc), 100e6);
        vm.stopPrank();
    }

    function test_ReleasePayroll() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        bytes32 sessionId = keccak256("session1");

        vm.prank(manager);
        treasury.lockForPayroll(sessionId, address(usdc), 500e6);

        vm.prank(manager);
        treasury.releasePayroll(sessionId, address(usdc));

        assertEq(treasury.availableBalance(address(usdc)), 1000e6);
        assertEq(treasury.totalLockedBalance(address(usdc)), 0);
    }

    function test_ReleasePayrollRevertsForUnlockedSession() public {
        bytes32 sessionId = keccak256("session1");

        vm.prank(manager);
        vm.expectRevert(Treasury.SessionNotLocked.selector);
        treasury.releasePayroll(sessionId, address(usdc));
    }

    // --- Orbital Integration Tests ---

    function test_ProvideToOrbital() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(keeper);
        treasury.provideToOrbital(address(usdc), 500e6);

        assertEq(treasury.availableBalance(address(usdc)), 500e6);
        assertEq(treasury.allocatedBalance(address(usdc)), 500e6);
    }

    function test_WithdrawFromOrbital() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(keeper);
        treasury.provideToOrbital(address(usdc), 500e6);

        vm.prank(keeper);
        treasury.withdrawFromOrbital(address(usdc), 300e6);

        assertEq(treasury.availableBalance(address(usdc)), 800e6);
        assertEq(treasury.allocatedBalance(address(usdc)), 200e6);
    }

    // --- Pause Tests ---

    function test_PauseBlocksDeposit() public {
        vm.prank(emergency);
        treasury.pause();

        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);

        vm.expectRevert();
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();
    }

    function test_PauseBlocksWithdraw() public {
        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        vm.prank(emergency);
        treasury.pause();

        vm.expectRevert();
        treasury.withdraw(address(usdc), 500e6, admin);
    }

    function test_Unpause() public {
        vm.prank(emergency);
        treasury.pause();

        vm.prank(emergency);
        treasury.unpause();

        vm.startPrank(user);
        usdc.approve(address(treasury), 1000e6);
        treasury.deposit(address(usdc), 1000e6);
        vm.stopPrank();

        assertEq(treasury.availableBalance(address(usdc)), 1000e6);
    }

    // --- Token Management Tests ---

    function test_AddSupportedToken() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);

        treasury.addSupportedToken(address(dai));
        assertTrue(treasury.supportedTokens(address(dai)));
    }

    function test_RemoveSupportedToken() public {
        treasury.removeSupportedToken(address(usdc));
        assertFalse(treasury.supportedTokens(address(usdc)));
    }

    function test_SetOrbitalHook() public {
        address hook = makeAddr("orbitalHook");
        treasury.setOrbitalHook(hook);
        assertEq(treasury.orbitalHook(), hook);
    }
}
