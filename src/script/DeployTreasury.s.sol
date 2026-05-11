pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreasuryV1} from "../treasury/TreasuryV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTreasury is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address admin = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        TreasuryV1 implementation = new TreasuryV1();
        
        bytes memory data = abi.encodeCall(TreasuryV1.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        vm.stopBroadcast();

        console.log("TreasuryV1 Implementation:", address(implementation));
        console.log("Treasury Proxy:", address(proxy));
        console.log("Admin Address:", admin);
    }
}