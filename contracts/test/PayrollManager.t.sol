// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PayrollManager} from "../src/PayrollManager.sol";

contract PayrollManagerTest is Test {
    PayrollManager public payrollManager;

    function setUp() public {
        payrollManager = new PayrollManager();
    }

    function test_Placeholder() public {
        // TODO: Implement tests
        assertTrue(true);
    }
}
