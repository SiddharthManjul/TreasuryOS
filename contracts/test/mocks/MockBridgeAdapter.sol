// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBridgeAdapter} from "../../src/interfaces/IBridgeAdapter.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract MockBridgeAdapter is IBridgeAdapter {
    bool public shouldFail;
    uint256 public feePerBridge = 1e6; // 1 USDC flat fee
    uint256 public bridgeCount;

    mapping(bytes32 => bool) public bridgedTxs;

    event Bridged(address token, address recipient, uint256 amount, uint256 destChainId, bytes32 txId);

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFeePerBridge(uint256 _fee) external {
        feePerBridge = _fee;
    }

    function bridge(
        address token,
        address recipient,
        uint256 amount,
        uint256 destChainId
    )
        external
        override
        returns (bytes32 bridgeTxId)
    {
        if (shouldFail) {
            revert("Bridge failed");
        }

        // Transfer tokens from caller
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);

        // Generate tx ID
        bridgeTxId = keccak256(abi.encodePacked(block.timestamp, recipient, amount, destChainId, bridgeCount++));
        bridgedTxs[bridgeTxId] = true;

        emit Bridged(token, recipient, amount, destChainId, bridgeTxId);
    }

    function estimateFee(uint256, uint256) external view override returns (uint256) {
        return feePerBridge;
    }
}
