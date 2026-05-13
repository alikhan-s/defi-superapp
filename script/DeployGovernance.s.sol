pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { ProtocolGovernor } from "../src/governance/ProtocolGovernor.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract DummyToken is ERC20, ERC20Permit, ERC20Votes {
    constructor() ERC20("Dummy", "DUM") ERC20Permit("Dummy") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

contract DummyTreasury is AccessControl {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}

contract DeployGovernance is Script {
    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        DummyToken govToken = new DummyToken();
        govToken.mint(deployer, 1_000_000 ether);

        DummyTreasury treasury = new DummyTreasury();

        address[] memory emptyArray = new address[](0);

        ProtocolTimelock timelock = new ProtocolTimelock(2 days, emptyArray, emptyArray, deployer);

        ProtocolGovernor governor = new ProtocolGovernor(IVotes(address(govToken)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), address(timelock));
        treasury.renounceRole(treasury.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        string memory json = "governance_deploy";
        vm.serializeAddress(json, "Timelock", address(timelock));
        vm.serializeAddress(json, "Governor", address(governor));
        vm.serializeAddress(json, "GovernanceToken", address(govToken));
        string memory finalJson = vm.serializeAddress(json, "Treasury", address(treasury));

        string memory dirPath = string.concat(vm.projectRoot(), "/deployments");
        vm.createDir(dirPath, true);
        string memory filePath = string.concat(dirPath, "/", vm.toString(block.chainid), ".json");
        vm.writeJson(finalJson, filePath);

        console.log("Deployed to:", filePath);
    }
}
