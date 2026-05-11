pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TreasuryV2} from "../treasury/TreasuryV2.sol";
import {TreasuryV1} from "../treasury/TreasuryV1.sol";

contract UpgradeTreasury is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        TreasuryV2 newImplementation = new TreasuryV2();
        
        TreasuryV1 proxy = TreasuryV1(payable(proxyAddress));
        proxy.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        console.log("TreasuryV2 Implementation:", address(newImplementation));
        console.log("Upgraded Proxy:", proxyAddress);
    }
}