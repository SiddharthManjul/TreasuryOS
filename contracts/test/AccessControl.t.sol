// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AccessControl} from "../src/AccessControl.sol";

contract AccessControlTest is Test {
    AccessControl public accessControl;

    address public admin = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        accessControl = new AccessControl();
    }

    // --- Role Constants Tests ---

    function test_RoleConstants() public view {
        assertEq(accessControl.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
        assertEq(accessControl.COMPANY_ROLE(), keccak256("COMPANY_ROLE"));
        assertEq(accessControl.KEEPER_ROLE(), keccak256("KEEPER_ROLE"));
        assertEq(accessControl.MANAGER_ROLE(), keccak256("MANAGER_ROLE"));
        assertEq(accessControl.EMERGENCY_ROLE(), keccak256("EMERGENCY_ROLE"));
    }

    // --- Deployer Role Tests ---

    function test_DeployerHasDefaultAdminRole() public view {
        assertTrue(accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_DeployerHasAdminRole() public view {
        assertTrue(accessControl.hasRole(accessControl.ADMIN_ROLE(), admin));
    }

    // --- Role Admin Tests ---

    function test_AdminRoleManagesCompanyRole() public view {
        assertEq(accessControl.getRoleAdmin(accessControl.COMPANY_ROLE()), accessControl.ADMIN_ROLE());
    }

    function test_AdminRoleManagesKeeperRole() public view {
        assertEq(accessControl.getRoleAdmin(accessControl.KEEPER_ROLE()), accessControl.ADMIN_ROLE());
    }

    function test_AdminRoleManagesManagerRole() public view {
        assertEq(accessControl.getRoleAdmin(accessControl.MANAGER_ROLE()), accessControl.ADMIN_ROLE());
    }

    function test_AdminRoleManagesEmergencyRole() public view {
        assertEq(accessControl.getRoleAdmin(accessControl.EMERGENCY_ROLE()), accessControl.ADMIN_ROLE());
    }

    // --- Grant/Revoke Tests ---

    function test_AdminCanGrantCompanyRole() public {
        accessControl.grantRole(accessControl.COMPANY_ROLE(), user1);
        assertTrue(accessControl.hasRole(accessControl.COMPANY_ROLE(), user1));
    }

    function test_AdminCanGrantKeeperRole() public {
        accessControl.grantRole(accessControl.KEEPER_ROLE(), user1);
        assertTrue(accessControl.hasRole(accessControl.KEEPER_ROLE(), user1));
    }

    function test_AdminCanGrantManagerRole() public {
        accessControl.grantRole(accessControl.MANAGER_ROLE(), user1);
        assertTrue(accessControl.hasRole(accessControl.MANAGER_ROLE(), user1));
    }

    function test_AdminCanGrantEmergencyRole() public {
        accessControl.grantRole(accessControl.EMERGENCY_ROLE(), user1);
        assertTrue(accessControl.hasRole(accessControl.EMERGENCY_ROLE(), user1));
    }

    function test_AdminCanRevokeRole() public {
        accessControl.grantRole(accessControl.COMPANY_ROLE(), user1);
        accessControl.revokeRole(accessControl.COMPANY_ROLE(), user1);
        assertFalse(accessControl.hasRole(accessControl.COMPANY_ROLE(), user1));
    }

    function test_NonAdminCannotGrantRoles() public {
        bytes32 role = accessControl.COMPANY_ROLE();
        vm.prank(user1);
        vm.expectRevert();
        accessControl.grantRole(role, user2);
    }

    function test_NonAdminCannotRevokeRoles() public {
        bytes32 role = accessControl.COMPANY_ROLE();
        accessControl.grantRole(role, user1);

        vm.prank(user2);
        vm.expectRevert();
        accessControl.revokeRole(role, user1);
    }

    // --- Renounce Tests ---

    function test_UserCanRenounceOwnRole() public {
        bytes32 role = accessControl.COMPANY_ROLE();
        accessControl.grantRole(role, user1);

        vm.prank(user1);
        accessControl.renounceRole(role, user1);

        assertFalse(accessControl.hasRole(role, user1));
    }

    function test_UserCannotRenounceOthersRole() public {
        bytes32 role = accessControl.COMPANY_ROLE();
        accessControl.grantRole(role, user1);

        vm.prank(user2);
        vm.expectRevert();
        accessControl.renounceRole(role, user1);
    }

    // --- Multiple Roles Tests ---

    function test_UserCanHaveMultipleRoles() public {
        accessControl.grantRole(accessControl.COMPANY_ROLE(), user1);
        accessControl.grantRole(accessControl.KEEPER_ROLE(), user1);
        accessControl.grantRole(accessControl.MANAGER_ROLE(), user1);

        assertTrue(accessControl.hasRole(accessControl.COMPANY_ROLE(), user1));
        assertTrue(accessControl.hasRole(accessControl.KEEPER_ROLE(), user1));
        assertTrue(accessControl.hasRole(accessControl.MANAGER_ROLE(), user1));
    }
}
