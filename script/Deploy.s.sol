// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Production deployment orchestrator.
//
// Required env vars:
//   PRIVATE_KEY                  deployer key (must be funded on target chain)
//   ARBITRUM_SEPOLIA_RPC_URL     RPC endpoint (also used by forge --rpc-url)
//   ARBISCAN_API_KEY             only required when --verify is passed
//
// Per-chain config: script/config/<chainId>.json
//   tokens.weth, tokens.usdc (must be non-zero before broadcast)
//   feeds.ethUsd, feeds.usdcUsd, feeds.stalenessSeconds
//
// Idempotency: If deployments/<chainId>.json exists, any address with non-empty
// bytecode is reused; only missing pieces are deployed.

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { GovernanceToken } from "../src/tokens/GovernanceToken.sol";
import { ChainlinkPriceOracle } from "../src/oracle/ChainlinkPriceOracle.sol";
import { LPPositionNFT } from "../src/tokens/LPPositionNFT.sol";
import { PairFactory } from "../src/amm/PairFactory.sol";
import { LendingPool } from "../src/lending/LendingPool.sol";
import { YieldVault, ILendingPool } from "../src/vault/YieldVault.sol";
import { TreasuryV1 } from "../src/treasury/TreasuryV1.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { ProtocolGovernor } from "../src/governance/ProtocolGovernor.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    using stdJson for string;

    struct Deployed {
        address governanceToken;
        address oracle;
        address lpNFT;
        address pairFactory;
        address samplePair;
        address lendingPool;
        address yieldVault;
        address treasuryProxy;
        address timelock;
        address governor;
    }

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    uint256 internal constant INITIAL_SUPPLY = 10_000_000 ether;
    uint256 internal constant TIMELOCK_DELAY = 2 days;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        (address weth, address usdc, address ethFeed, address usdcFeed, uint256 staleness) = _loadConfig();
        require(weth != address(0), "config.tokens.weth is zero");
        require(usdc != address(0), "config.tokens.usdc is zero");
        require(ethFeed != address(0), "config.feeds.ethUsd is zero");
        require(usdcFeed != address(0), "config.feeds.usdcUsd is zero");

        Deployed memory d = _loadExisting();

        vm.startBroadcast(pk);

        if (!_isContract(d.governanceToken)) {
            d.governanceToken = address(new GovernanceToken("Protocol Governance", "PGOV", INITIAL_SUPPLY, deployer));
        }
        if (!_isContract(d.oracle)) {
            ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(deployer);
            oracle.addFeed(weth, ethFeed, staleness);
            oracle.addFeed(usdc, usdcFeed, staleness);
            d.oracle = address(oracle);
        }
        if (!_isContract(d.lpNFT)) {
            d.lpNFT = address(new LPPositionNFT(deployer));
        }
        if (!_isContract(d.pairFactory)) {
            PairFactory factory = new PairFactory(d.lpNFT, deployer);
            // Factory needs DEFAULT_ADMIN_ROLE on lpNFT so it can grant MINTER_ROLE to each new pair.
            LPPositionNFT(d.lpNFT).grantRole(DEFAULT_ADMIN_ROLE, address(factory));
            d.pairFactory = address(factory);
        }
        if (!_isContract(d.samplePair)) {
            d.samplePair = PairFactory(d.pairFactory).createPair(weth, usdc);
        }
        if (!_isContract(d.lendingPool)) {
            d.lendingPool = address(
                new LendingPool(
                    weth,
                    usdc,
                    d.oracle,
                    8000, // 80% liquidation threshold
                    1000, // 10% liquidation bonus
                    100, // 1% base rate
                    1000, // 10% slope1
                    deployer
                )
            );
        }
        if (!_isContract(d.yieldVault)) {
            d.yieldVault = address(
                new YieldVault(IERC20(usdc), ILendingPool(d.lendingPool), "Yield Vault USDC", "yvUSDC", deployer)
            );
        }
        if (!_isContract(d.treasuryProxy)) {
            TreasuryV1 treasuryImpl = new TreasuryV1();
            bytes memory init = abi.encodeCall(TreasuryV1.initialize, (deployer));
            d.treasuryProxy = address(new ERC1967Proxy(address(treasuryImpl), init));
        }
        if (!_isContract(d.timelock)) {
            address[] memory empty = new address[](0);
            d.timelock = address(new ProtocolTimelock(TIMELOCK_DELAY, empty, empty, deployer));
        }
        if (!_isContract(d.governor)) {
            d.governor = address(new ProtocolGovernor(IVotes(d.governanceToken), ProtocolTimelock(payable(d.timelock))));
        }

        ProtocolTimelock timelock = ProtocolTimelock(payable(d.timelock));
        if (!timelock.hasRole(PROPOSER_ROLE, d.governor)) timelock.grantRole(PROPOSER_ROLE, d.governor);
        if (!timelock.hasRole(EXECUTOR_ROLE, address(0))) timelock.grantRole(EXECUTOR_ROLE, address(0));
        if (!timelock.hasRole(CANCELLER_ROLE, d.governor)) timelock.grantRole(CANCELLER_ROLE, d.governor);

        _handoff(d.treasuryProxy, deployer, d.timelock);
        _handoff(d.lendingPool, deployer, d.timelock);
        _handoff(d.pairFactory, deployer, d.timelock);
        _handoff(d.yieldVault, deployer, d.timelock);

        if (timelock.hasRole(DEFAULT_ADMIN_ROLE, deployer)) {
            timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
        }

        vm.stopBroadcast();

        _writeDeployments(d);

        console.log("=== Deployment complete ===");
        console.log("GovernanceToken:", d.governanceToken);
        console.log("Oracle:         ", d.oracle);
        console.log("LPPositionNFT:  ", d.lpNFT);
        console.log("PairFactory:    ", d.pairFactory);
        console.log("SamplePair:     ", d.samplePair);
        console.log("LendingPool:    ", d.lendingPool);
        console.log("YieldVault:     ", d.yieldVault);
        console.log("TreasuryProxy:  ", d.treasuryProxy);
        console.log("Timelock:       ", d.timelock);
        console.log("Governor:       ", d.governor);
    }

    function _handoff(address target, address deployer, address timelock) internal {
        IAccessControl ac = IAccessControl(target);
        if (!ac.hasRole(DEFAULT_ADMIN_ROLE, timelock)) ac.grantRole(DEFAULT_ADMIN_ROLE, timelock);
        if (ac.hasRole(DEFAULT_ADMIN_ROLE, deployer)) ac.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
    }

    function _isContract(address a) internal view returns (bool) {
        if (a == address(0)) return false;
        uint256 size;
        assembly {
            size := extcodesize(a)
        }
        return size > 0;
    }

    function _loadConfig()
        internal
        view
        returns (address weth, address usdc, address ethFeed, address usdcFeed, uint256 staleness)
    {
        string memory path = string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        weth = json.readAddress(".tokens.weth");
        usdc = json.readAddress(".tokens.usdc");
        ethFeed = json.readAddress(".feeds.ethUsd");
        usdcFeed = json.readAddress(".feeds.usdcUsd");
        staleness = json.readUint(".feeds.stalenessSeconds");
    }

    function _loadExisting() internal view returns (Deployed memory d) {
        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        try vm.readFile(path) returns (string memory json) {
            d.governanceToken = _readOr(json, ".GovernanceToken");
            d.oracle = _readOr(json, ".Oracle");
            d.lpNFT = _readOr(json, ".LPPositionNFT");
            d.pairFactory = _readOr(json, ".PairFactory");
            d.samplePair = _readOr(json, ".SamplePair");
            d.lendingPool = _readOr(json, ".LendingPool");
            d.yieldVault = _readOr(json, ".YieldVault");
            d.treasuryProxy = _readOr(json, ".TreasuryProxy");
            d.timelock = _readOr(json, ".Timelock");
            d.governor = _readOr(json, ".Governor");
        } catch {
            // no prior deployment
        }
    }

    function _readOr(string memory json, string memory key) internal view returns (address) {
        try this.readAddrExternal(json, key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    function readAddrExternal(string memory json, string memory key) external pure returns (address) {
        return json.readAddress(key);
    }

    function _writeDeployments(Deployed memory d) internal {
        string memory key = "deploy";
        vm.serializeAddress(key, "GovernanceToken", d.governanceToken);
        vm.serializeAddress(key, "Oracle", d.oracle);
        vm.serializeAddress(key, "LPPositionNFT", d.lpNFT);
        vm.serializeAddress(key, "PairFactory", d.pairFactory);
        vm.serializeAddress(key, "SamplePair", d.samplePair);
        vm.serializeAddress(key, "LendingPool", d.lendingPool);
        vm.serializeAddress(key, "YieldVault", d.yieldVault);
        vm.serializeAddress(key, "TreasuryProxy", d.treasuryProxy);
        vm.serializeAddress(key, "Timelock", d.timelock);
        string memory finalJson = vm.serializeAddress(key, "Governor", d.governor);

        string memory dirPath = string.concat(vm.projectRoot(), "/deployments");
        vm.createDir(dirPath, true);
        vm.writeJson(finalJson, string.concat(dirPath, "/", vm.toString(block.chainid), ".json"));
    }
}
