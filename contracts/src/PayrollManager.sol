// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "./AccessControl.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title PayrollManager
/// @notice Payroll session lifecycle, merkle verification, and settlements
contract PayrollManager is AccessControl {
    // --- Errors ---
    error SessionAlreadyExists();
    error SessionNotFound();
    error InvalidStatus();
    error InvalidStateRoot();
    error InvalidProof();
    error AlreadyClaimed();
    error ZeroAmount();
    error ZeroAddress();

    // --- Enums ---
    enum SessionStatus {
        Pending,
        Active,
        Closing,
        Settled,
        Cancelled
    }

    // --- Structs ---
    struct Session {
        bytes32 id;
        address company;
        address token;
        uint256 totalAmount;
        uint256 employeeCount;
        uint256 startTime;
        uint256 endTime;
        bytes32 stateRoot;
        SessionStatus status;
    }

    // --- State ---
    ITreasury public treasury;
    mapping(bytes32 => Session) public sessions;
    mapping(bytes32 => mapping(bytes32 => bool)) public claimed;

    // --- Events ---
    event SessionCreated(bytes32 indexed sessionId, address indexed company, address indexed token, uint256 totalAmount);
    event SessionStarted(bytes32 indexed sessionId, uint256 startTime);
    event SessionClosed(bytes32 indexed sessionId, bytes32 stateRoot, uint256 endTime);
    event SessionSettled(bytes32 indexed sessionId);
    event SessionCancelled(bytes32 indexed sessionId);
    event PayoutClaimed(
        bytes32 indexed sessionId, bytes32 indexed employeeId, address recipient, uint256 amount
    );

    constructor(address _treasury) {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = ITreasury(_treasury);
    }

    // --- Session Lifecycle ---

    function createSession(
        bytes32 sessionId,
        address token,
        uint256 totalAmount,
        uint256 employeeCount
    ) external onlyRole(COMPANY_ROLE) {
        if (sessions[sessionId].company != address(0)) revert SessionAlreadyExists();
        if (totalAmount == 0) revert ZeroAmount();
        if (!treasury.supportedTokens(token)) revert ZeroAddress();

        sessions[sessionId] = Session({
            id: sessionId,
            company: msg.sender,
            token: token,
            totalAmount: totalAmount,
            employeeCount: employeeCount,
            startTime: 0,
            endTime: 0,
            stateRoot: bytes32(0),
            status: SessionStatus.Pending
        });

        treasury.lockForPayroll(sessionId, token, totalAmount);

        emit SessionCreated(sessionId, msg.sender, token, totalAmount);
    }

    function startSession(bytes32 sessionId) external onlyRole(COMPANY_ROLE) {
        Session storage session = sessions[sessionId];
        if (session.company == address(0)) revert SessionNotFound();
        if (session.status != SessionStatus.Pending) revert InvalidStatus();

        session.status = SessionStatus.Active;
        session.startTime = block.timestamp;

        emit SessionStarted(sessionId, block.timestamp);
    }

    function closeSession(
        bytes32 sessionId,
        bytes32 stateRoot
    ) external onlyRole(COMPANY_ROLE) {
        Session storage session = sessions[sessionId];
        if (session.company == address(0)) revert SessionNotFound();
        if (session.status != SessionStatus.Active) revert InvalidStatus();
        if (stateRoot == bytes32(0)) revert InvalidStateRoot();

        session.status = SessionStatus.Closing;
        session.stateRoot = stateRoot;
        session.endTime = block.timestamp;

        emit SessionClosed(sessionId, stateRoot, block.timestamp);
    }

    function settleSession(bytes32 sessionId) external onlyRole(KEEPER_ROLE) {
        Session storage session = sessions[sessionId];
        if (session.company == address(0)) revert SessionNotFound();
        if (session.status != SessionStatus.Closing) revert InvalidStatus();

        session.status = SessionStatus.Settled;
        treasury.releasePayroll(sessionId, session.token);

        emit SessionSettled(sessionId);
    }

    function cancelSession(bytes32 sessionId) external onlyRole(COMPANY_ROLE) {
        Session storage session = sessions[sessionId];
        if (session.company == address(0)) revert SessionNotFound();
        if (session.status == SessionStatus.Settled || session.status == SessionStatus.Cancelled) {
            revert InvalidStatus();
        }

        session.status = SessionStatus.Cancelled;
        treasury.releasePayroll(sessionId, session.token);

        emit SessionCancelled(sessionId);
    }

    // --- Employee Claims ---

    function claimPayout(
        bytes32 sessionId,
        bytes32 employeeId,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        Session storage session = sessions[sessionId];
        if (session.company == address(0)) revert SessionNotFound();
        if (session.status != SessionStatus.Closing && session.status != SessionStatus.Settled) {
            revert InvalidStatus();
        }
        if (claimed[sessionId][employeeId]) revert AlreadyClaimed();
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bytes32 leaf = keccak256(abi.encodePacked(employeeId, recipient, amount));
        if (!MerkleProof.verify(merkleProof, session.stateRoot, leaf)) revert InvalidProof();

        claimed[sessionId][employeeId] = true;

        SafeTransferLib.safeTransfer(session.token, recipient, amount);

        emit PayoutClaimed(sessionId, employeeId, recipient, amount);
    }

    // --- Views ---

    function getSession(bytes32 sessionId) external view returns (Session memory) {
        return sessions[sessionId];
    }

    function isSessionActive(bytes32 sessionId) external view returns (bool) {
        return sessions[sessionId].status == SessionStatus.Active;
    }

    function getSessionStatus(bytes32 sessionId) external view returns (SessionStatus) {
        return sessions[sessionId].status;
    }

    function verifyAllocation(
        bytes32 sessionId,
        bytes32 employeeId,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        Session storage session = sessions[sessionId];
        bytes32 leaf = keccak256(abi.encodePacked(employeeId, recipient, amount));
        return MerkleProof.verify(merkleProof, session.stateRoot, leaf);
    }
}
