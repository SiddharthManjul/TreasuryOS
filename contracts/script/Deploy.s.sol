// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {AccessControl} from "../src/AccessControl.sol";
import {OrbitalHook} from "../src/OrbitalHook.sol";
import {ArcRouter} from "../src/ArcRouter.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // TODO: Deploy contracts

        vm.stopBroadcast();
    }
}
