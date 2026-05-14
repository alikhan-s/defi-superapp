// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Required env vars:
//   GOV_TOKEN_ADDRESS  — address of the deployed GovernanceToken (Phase 1)
//   TREASURY_ADDRESS   — address of the deployed TreasuryV1 proxy   (Phase 6)
//   PRIVATE_KEY        — optional; falls back to Anvil's default key #0 when unset
//
// The script wires governance on top of pre-deployed token + treasury:
//   1. Deploys ProtocolTimelock and ProtocolGovernor
//   2. Grants PROPOSER_ROLE on the timelock to the governor and EXECUTOR_ROLE to anyone
//   3. Hands DEFAULT_ADMIN_ROLE on the treasury to the timelock and renounces the deployer's
//   4. Writes deployments/<chainId>.json with all four addresses
import { Script, console } from "forge-std/Script.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { ProtocolGovernor } from "../src/governance/ProtocolGovernor.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DeployGovernance is Script {
    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        address govTokenAddress = vm.envAddress("GOV_TOKEN_ADDRESS");
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        require(govTokenAddress != address(0), "GOV_TOKEN_ADDRESS not set");
        require(treasuryAddress != address(0), "TREASURY_ADDRESS not set");

        vm.startBroadcast(deployerPrivateKey);

        address[] memory emptyArray = new address[](0);
        ProtocolTimelock timelock = new ProtocolTimelock(2 days, emptyArray, emptyArray, deployer);
        ProtocolGovernor governor = new ProtocolGovernor(IVotes(govTokenAddress), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        IAccessControl treasury = IAccessControl(treasuryAddress);
        treasury.grantRole(0x00, address(timelock)); // DEFAULT_ADMIN_ROLE
        treasury.renounceRole(0x00, deployer);

        vm.stopBroadcast();

        string memory json = "governance_deploy";
        vm.serializeAddress(json, "Timelock", address(timelock));
        vm.serializeAddress(json, "Governor", address(governor));
        vm.serializeAddress(json, "GovernanceToken", govTokenAddress);
        string memory finalJson = vm.serializeAddress(json, "Treasury", treasuryAddress);

        string memory dirPath = string.concat(vm.projectRoot(), "/deployments");
        vm.createDir(dirPath, true);
        string memory filePath = string.concat(dirPath, "/", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, filePath);

        console.log("Deployed to:", filePath);
    }
}
