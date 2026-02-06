// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "./AccessControl.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title ArcRouter
/// @notice Cross-chain batch payouts via Arc Protocol
contract ArcRouter is AccessControl {
    // --- Errors ---
    error UnsupportedChain();
    error ZeroAddress();
    error ZeroAmount();
    error BridgeFailed();
    error ArrayLengthMismatch();

    // --- Structs ---
    struct PayoutInstruction {
        uint256 destChainId;
        address token;
        address recipient;
        uint256 amount;
        bytes32 employeeId;
    }

    struct PayoutResult {
        bytes32 employeeId;
        bool success;
        bytes32 bridgeTxId;
        uint256 actualAmount;
    }

    // --- State ---
    mapping(uint256 => bool) public supportedChains;
    mapping(uint256 => IBridgeAdapter) public bridgeAdapters;
    uint256 public baseBridgeFeeBps = 10; // 0.1%
    mapping(uint256 => uint256) public chainFeeOverrides;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    // --- Events ---
    event BatchPayoutInitiated(bytes32 indexed batchId, uint256 totalPayouts, uint256 totalAmount);
    event PayoutSent(
        bytes32 indexed batchId, bytes32 indexed employeeId, uint256 chainId, uint256 amount, bytes32 bridgeTxId
    );
    event PayoutFailed(bytes32 indexed batchId, bytes32 indexed employeeId, string reason);
    event ChainAdded(uint256 indexed chainId, address adapter);
    event ChainRemoved(uint256 indexed chainId);
    event BridgeAdapterSet(uint256 indexed chainId, address adapter);
    event BaseFeeSet(uint256 feeBps);
    event ChainFeeOverrideSet(uint256 indexed chainId, uint256 feeBps);

    // --- Admin Functions ---

    function addSupportedChain(uint256 chainId, address adapter) external onlyRole(ADMIN_ROLE) {
        if (adapter == address(0)) revert ZeroAddress();
        supportedChains[chainId] = true;
        bridgeAdapters[chainId] = IBridgeAdapter(adapter);
        emit ChainAdded(chainId, adapter);
    }

    function removeSupportedChain(uint256 chainId) external onlyRole(ADMIN_ROLE) {
        supportedChains[chainId] = false;
        delete bridgeAdapters[chainId];
        emit ChainRemoved(chainId);
    }

    function setBridgeAdapter(uint256 chainId, address adapter) external onlyRole(ADMIN_ROLE) {
        if (adapter == address(0)) revert ZeroAddress();
        bridgeAdapters[chainId] = IBridgeAdapter(adapter);
        emit BridgeAdapterSet(chainId, adapter);
    }

    function setBaseBridgeFee(uint256 feeBps) external onlyRole(ADMIN_ROLE) {
        baseBridgeFeeBps = feeBps;
        emit BaseFeeSet(feeBps);
    }

    function setChainFeeOverride(uint256 chainId, uint256 feeBps) external onlyRole(ADMIN_ROLE) {
        chainFeeOverrides[chainId] = feeBps;
        emit ChainFeeOverrideSet(chainId, feeBps);
    }

    // --- Payout Functions ---

    function batchPayout(PayoutInstruction[] calldata payouts)
        external
        onlyRole(MANAGER_ROLE)
        returns (PayoutResult[] memory results)
    {
        bytes32 batchId = keccak256(abi.encodePacked(block.timestamp, msg.sender, payouts.length));
        results = new PayoutResult[](payouts.length);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < payouts.length; i++) {
            PayoutInstruction calldata payout = payouts[i];
            totalAmount += payout.amount;

            results[i] = _executePayout(batchId, payout);
        }

        emit BatchPayoutInitiated(batchId, payouts.length, totalAmount);
        return results;
    }

    function singlePayout(PayoutInstruction calldata payout)
        external
        onlyRole(MANAGER_ROLE)
        returns (PayoutResult memory result)
    {
        bytes32 batchId = keccak256(abi.encodePacked(block.timestamp, msg.sender, payout.employeeId));
        return _executePayout(batchId, payout);
    }

    // --- Views ---

    function estimateFees(PayoutInstruction[] calldata payouts)
        external
        view
        returns (uint256 totalFees, uint256[] memory perPayoutFees)
    {
        perPayoutFees = new uint256[](payouts.length);

        for (uint256 i = 0; i < payouts.length; i++) {
            uint256 fee = getBridgeFee(payouts[i].destChainId, payouts[i].amount);
            perPayoutFees[i] = fee;
            totalFees += fee;
        }
    }

    function isSupportedChain(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId] || chainId == block.chainid;
    }

    function getBridgeFee(uint256 chainId, uint256 amount) public view returns (uint256) {
        // Same-chain transfers have no bridge fee
        if (chainId == block.chainid) return 0;

        uint256 feeBps = chainFeeOverrides[chainId];
        if (feeBps == 0) {
            feeBps = baseBridgeFeeBps;
        }

        return (amount * feeBps) / BPS_DENOMINATOR;
    }

    // --- Internal Functions ---

    function _executePayout(
        bytes32 batchId,
        PayoutInstruction calldata payout
    )
        internal
        returns (PayoutResult memory result)
    {
        result.employeeId = payout.employeeId;

        if (payout.recipient == address(0)) {
            result.success = false;
            emit PayoutFailed(batchId, payout.employeeId, "Zero recipient");
            return result;
        }

        if (payout.amount == 0) {
            result.success = false;
            emit PayoutFailed(batchId, payout.employeeId, "Zero amount");
            return result;
        }

        // Same-chain payout - direct transfer
        if (payout.destChainId == block.chainid) {
            SafeTransferLib.safeTransferFrom(payout.token, msg.sender, payout.recipient, payout.amount);

            result.success = true;
            result.actualAmount = payout.amount;
            result.bridgeTxId = bytes32(0);

            emit PayoutSent(batchId, payout.employeeId, payout.destChainId, payout.amount, bytes32(0));
            return result;
        }

        // Cross-chain payout
        if (!supportedChains[payout.destChainId]) {
            result.success = false;
            emit PayoutFailed(batchId, payout.employeeId, "Unsupported chain");
            return result;
        }

        IBridgeAdapter adapter = bridgeAdapters[payout.destChainId];
        if (address(adapter) == address(0)) {
            result.success = false;
            emit PayoutFailed(batchId, payout.employeeId, "No bridge adapter");
            return result;
        }

        // Calculate fee
        uint256 fee = getBridgeFee(payout.destChainId, payout.amount);
        uint256 amountAfterFee = payout.amount - fee;

        // Transfer tokens to this contract first
        SafeTransferLib.safeTransferFrom(payout.token, msg.sender, address(this), payout.amount);

        // Approve bridge adapter
        SafeTransferLib.safeApprove(payout.token, address(adapter), amountAfterFee);

        // Execute bridge
        try adapter.bridge(payout.token, payout.recipient, amountAfterFee, payout.destChainId) returns (
            bytes32 bridgeTxId
        ) {
            result.success = true;
            result.bridgeTxId = bridgeTxId;
            result.actualAmount = amountAfterFee;

            emit PayoutSent(batchId, payout.employeeId, payout.destChainId, amountAfterFee, bridgeTxId);
        } catch {
            // Refund on failure
            SafeTransferLib.safeTransfer(payout.token, msg.sender, payout.amount);

            result.success = false;
            emit PayoutFailed(batchId, payout.employeeId, "Bridge call failed");
        }

        return result;
    }
}
