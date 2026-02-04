// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount, address to) external;
    function emergencyWithdraw(address token, address to) external;

    function provideToOrbital(address token, uint256 amount) external;
    function withdrawFromOrbital(address token, uint256 amount) external;

    function lockForPayroll(bytes32 sessionId, address token, uint256 amount) external;
    function releasePayroll(bytes32 sessionId, address token) external;

    function availableBalance(address token) external view returns (uint256);
    function totalLockedBalance(address token) external view returns (uint256);
    function allocatedBalance(address token) external view returns (uint256);
    function totalBalance(address token) external view returns (uint256);
    function supportedTokens(address token) external view returns (bool);
}
