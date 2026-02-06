// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";
import {PayrollManager} from "../src/PayrollManager.sol";
import {ArcRouter} from "../src/ArcRouter.sol";

/// @title DeployScript
/// @notice Deploys TreasuryOS contracts (excluding OrbitalHook which requires PoolManager)
contract DeployScript is Script {
    // Deployed contracts
    Treasury public treasury;
    PayrollManager public payrollManager;
    ArcRouter public arcRouter;

    // Configuration
    address public admin;
    address public keeper;
    address public company;
    address public emergency;

    // Mainnet stablecoins
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public {
        // Load configuration from environment
        admin = vm.envOr("ADMIN_ADDRESS", msg.sender);
        keeper = vm.envOr("KEEPER_ADDRESS", msg.sender);
        company = vm.envOr("COMPANY_ADDRESS", msg.sender);
        emergency = vm.envOr("EMERGENCY_ADDRESS", msg.sender);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Admin:", admin);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Treasury
        treasury = new Treasury();
        console.log("Treasury deployed at:", address(treasury));

        // 2. Deploy PayrollManager
        payrollManager = new PayrollManager(address(treasury));
        console.log("PayrollManager deployed at:", address(payrollManager));

        // 3. Deploy ArcRouter
        arcRouter = new ArcRouter();
        console.log("ArcRouter deployed at:", address(arcRouter));

        // 4. Configure Treasury
        _configureTreasury();

        // 5. Configure PayrollManager
        _configurePayrollManager();

        // 6. Configure ArcRouter
        _configureArcRouter();

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary();
    }

    function _configureTreasury() internal {
        // Add supported tokens (mainnet)
        if (block.chainid == 1) {
            treasury.addSupportedToken(USDC_MAINNET);
            treasury.addSupportedToken(USDT_MAINNET);
            treasury.addSupportedToken(DAI_MAINNET);
        }

        // Grant roles
        treasury.grantRole(treasury.KEEPER_ROLE(), keeper);
        treasury.grantRole(treasury.MANAGER_ROLE(), address(payrollManager));
        treasury.grantRole(treasury.EMERGENCY_ROLE(), emergency);

        if (admin != msg.sender) {
            treasury.grantRole(treasury.ADMIN_ROLE(), admin);
        }

        console.log("Treasury configured");
    }

    function _configurePayrollManager() internal {
        // Grant roles
        payrollManager.grantRole(payrollManager.COMPANY_ROLE(), company);
        payrollManager.grantRole(payrollManager.KEEPER_ROLE(), keeper);

        if (admin != msg.sender) {
            payrollManager.grantRole(payrollManager.ADMIN_ROLE(), admin);
        }

        console.log("PayrollManager configured");
    }

    function _configureArcRouter() internal {
        // Grant roles
        payrollManager.grantRole(payrollManager.MANAGER_ROLE(), address(arcRouter));

        if (admin != msg.sender) {
            arcRouter.grantRole(arcRouter.ADMIN_ROLE(), admin);
        }

        console.log("ArcRouter configured");
    }

    function _logDeploymentSummary() internal view {
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Treasury:", address(treasury));
        console.log("PayrollManager:", address(payrollManager));
        console.log("ArcRouter:", address(arcRouter));
        console.log("");
        console.log("=== Role Assignments ===");
        console.log("Admin:", admin);
        console.log("Keeper:", keeper);
        console.log("Company:", company);
        console.log("Emergency:", emergency);
    }
}

/// @title DeployLocal
/// @notice Deploy to local Anvil with mock tokens
contract DeployLocal is Script {
    function run() public {
        vm.startBroadcast();

        // Deploy Treasury
        Treasury treasury = new Treasury();
        console.log("Treasury:", address(treasury));

        // Deploy PayrollManager
        PayrollManager payrollManager = new PayrollManager(address(treasury));
        console.log("PayrollManager:", address(payrollManager));

        // Deploy ArcRouter
        ArcRouter arcRouter = new ArcRouter();
        console.log("ArcRouter:", address(arcRouter));

        // Configure
        treasury.grantRole(treasury.MANAGER_ROLE(), address(payrollManager));
        treasury.grantRole(treasury.KEEPER_ROLE(), msg.sender);
        treasury.grantRole(treasury.EMERGENCY_ROLE(), msg.sender);

        payrollManager.grantRole(payrollManager.COMPANY_ROLE(), msg.sender);
        payrollManager.grantRole(payrollManager.KEEPER_ROLE(), msg.sender);

        arcRouter.grantRole(arcRouter.MANAGER_ROLE(), msg.sender);

        vm.stopBroadcast();
    }
}
