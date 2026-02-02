// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury public treasury;

    function setUp() public {
        treasury = new Treasury();
    }

    function test_Placeholder() public {
        // TODO: Implement tests
        assertTrue(true);
    }
}
