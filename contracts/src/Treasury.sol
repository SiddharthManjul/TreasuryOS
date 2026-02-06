// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "./AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title Treasury
/// @notice Fund custody, deposits, withdrawals, and OrbitalHook integration
contract Treasury is AccessControl, Pausable {
    // --- Errors ---
    error TokenNotSupported();
    error InsufficientBalance();
    error ZeroAmount();
    error ZeroAddress();
    error SessionAlreadyLocked();
    error SessionNotLocked();

    // --- State ---
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenBalances;
    mapping(bytes32 => mapping(address => uint256)) public lockedBalances;
    mapping(address => uint256) public orbitalAllocations;
    mapping(address => uint256) public totalLockedPerToken;

    address public orbitalHook;

    // --- Events ---
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event LockedForPayroll(bytes32 indexed sessionId, address indexed token, uint256 amount);
    event ReleasedPayroll(bytes32 indexed sessionId, address indexed token, uint256 amount);
    event ProvidedToOrbital(address indexed token, uint256 amount);
    event WithdrawnFromOrbital(address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event OrbitalHookSet(address indexed hook);

    // --- Admin Functions ---

    function addSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    function setOrbitalHook(address hook) external onlyRole(ADMIN_ROLE) {
        if (hook == address(0)) revert ZeroAddress();
        orbitalHook = hook;
        emit OrbitalHookSet(hook);
    }

    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    // --- Core Functions ---

    function deposit(address token, uint256 amount) external whenNotPaused {
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount == 0) revert ZeroAmount();

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        tokenBalances[token] += amount;

        emit Deposited(token, msg.sender, amount);
    }

    function withdraw(address token, uint256 amount, address to) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (availableBalance(token) < amount) revert InsufficientBalance();

        tokenBalances[token] -= amount;
        SafeTransferLib.safeTransfer(token, to, amount);

        emit Withdrawn(token, to, amount);
    }

    function emergencyWithdraw(address token, address to) external onlyRole(EMERGENCY_ROLE) {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();

        tokenBalances[token] = 0;
        totalLockedPerToken[token] = 0;
        orbitalAllocations[token] = 0;

        SafeTransferLib.safeTransfer(token, to, balance);

        emit Withdrawn(token, to, balance);
    }

    // --- OrbitalHook Integration ---

    function provideToOrbital(address token, uint256 amount) external onlyRole(KEEPER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (availableBalance(token) < amount) revert InsufficientBalance();

        tokenBalances[token] -= amount;
        orbitalAllocations[token] += amount;

        if (orbitalHook != address(0)) {
            SafeTransferLib.safeApprove(token, orbitalHook, amount);
        }

        emit ProvidedToOrbital(token, amount);
    }

    function withdrawFromOrbital(address token, uint256 amount) external onlyRole(KEEPER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (orbitalAllocations[token] < amount) revert InsufficientBalance();

        orbitalAllocations[token] -= amount;
        tokenBalances[token] += amount;

        emit WithdrawnFromOrbital(token, amount);
    }

    // --- Payroll Integration ---

    function lockForPayroll(
        bytes32 sessionId,
        address token,
        uint256 amount
    )
        external
        onlyRole(MANAGER_ROLE)
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();
        if (lockedBalances[sessionId][token] != 0) revert SessionAlreadyLocked();
        if (availableBalance(token) < amount) revert InsufficientBalance();

        tokenBalances[token] -= amount;
        lockedBalances[sessionId][token] = amount;
        totalLockedPerToken[token] += amount;

        emit LockedForPayroll(sessionId, token, amount);
    }

    function releasePayroll(bytes32 sessionId, address token) external onlyRole(MANAGER_ROLE) whenNotPaused {
        uint256 amount = lockedBalances[sessionId][token];
        if (amount == 0) revert SessionNotLocked();

        lockedBalances[sessionId][token] = 0;
        totalLockedPerToken[token] -= amount;
        tokenBalances[token] += amount;

        emit ReleasedPayroll(sessionId, token, amount);
    }

    // --- Views ---

    function availableBalance(address token) public view returns (uint256) {
        return tokenBalances[token];
    }

    function totalLockedBalance(address token) external view returns (uint256) {
        return totalLockedPerToken[token];
    }

    function allocatedBalance(address token) external view returns (uint256) {
        return orbitalAllocations[token];
    }

    function totalBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
