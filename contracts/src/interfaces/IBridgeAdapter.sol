// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBridgeAdapter {
    function bridge(
        address token,
        address recipient,
        uint256 amount,
        uint256 destChainId
    ) external returns (bytes32 bridgeTxId);

    function estimateFee(uint256 destChainId, uint256 amount) external view returns (uint256);
}
