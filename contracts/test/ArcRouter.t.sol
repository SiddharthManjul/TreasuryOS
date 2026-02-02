// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcRouter} from "../src/ArcRouter.sol";

contract ArcRouterTest is Test {
    ArcRouter public arcRouter;

    function setUp() public {
        arcRouter = new ArcRouter();
    }

    function test_Placeholder() public {
        // TODO: Implement tests
        assertTrue(true);
    }
}
