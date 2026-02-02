// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AccessControl} from "../src/AccessControl.sol";

contract AccessControlTest is Test {
    AccessControl public accessControl;

    function setUp() public {
        accessControl = new AccessControl();
    }

    function test_Placeholder() public {
        // TODO: Implement tests
        assertTrue(true);
    }
}
