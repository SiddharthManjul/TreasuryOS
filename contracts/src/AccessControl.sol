// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl as OZAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AccessControl
/// @notice Role-based permissions for TreasuryOS
contract AccessControl is OZAccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant COMPANY_ROLE = keccak256("COMPANY_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // ADMIN_ROLE manages all other roles
        _setRoleAdmin(COMPANY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(KEEPER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, ADMIN_ROLE);
    }
}
