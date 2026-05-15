// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Post-deployment verifier.
// Reads deployments/<chainId>.json and asserts that ownership/parameters match expectations.
// Writes a human-readable report to docs/post-deployment-report.md.

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { ChainlinkPriceOracle } from "../src/oracle/ChainlinkPriceOracle.sol";
import { ProtocolGovernor } from "../src/governance/ProtocolGovernor.sol";
import { ProtocolTimelock } from "../src/governance/ProtocolTimelock.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PostDeployCheck is Script {
    using stdJson for string;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // Expected Governor constants (must match ProtocolGovernor constructor)
    uint256 internal constant EXPECTED_VOTING_DELAY = 345_600;
    uint256 internal constant EXPECTED_VOTING_PERIOD = 2_419_200;
    uint256 internal constant EXPECTED_QUORUM_NUMERATOR = 4;
    uint256 internal constant EXPECTED_TIMELOCK_DELAY = 2 days;

    string internal _report;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk == 0 ? address(0) : vm.addr(pk);

        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        address governor = json.readAddress(".Governor");
        address timelock = json.readAddress(".Timelock");
        address govToken = json.readAddress(".GovernanceToken");
        address oracle = json.readAddress(".Oracle");

        _line("# Post-deployment Report");
        _line(string.concat("Chain ID: ", vm.toString(block.chainid)));
        _line(string.concat("Block:    ", vm.toString(block.number)));
        _line("");

        // --- ownership: every privileged contract's DEFAULT_ADMIN_ROLE -> Timelock ---
        // Extracted to its own frame to keep run()'s local count under the stack limit.
        _assertOwnership(json, timelock, deployer);

        // --- timelock parameters ---
        uint256 minDelay = ProtocolTimelock(payable(timelock)).getMinDelay();
        _check(
            string.concat("Timelock minDelay == 2 days  (got ", vm.toString(minDelay), ")"),
            minDelay == EXPECTED_TIMELOCK_DELAY
        );

        // --- governor parameters ---
        ProtocolGovernor g = ProtocolGovernor(payable(governor));
        _check(
            string.concat("Governor votingDelay == ", vm.toString(EXPECTED_VOTING_DELAY)),
            g.votingDelay() == EXPECTED_VOTING_DELAY
        );
        _check(
            string.concat("Governor votingPeriod == ", vm.toString(EXPECTED_VOTING_PERIOD)),
            g.votingPeriod() == EXPECTED_VOTING_PERIOD
        );
        _check(
            string.concat("Governor quorumNumerator == ", vm.toString(EXPECTED_QUORUM_NUMERATOR)),
            g.quorumNumerator() == EXPECTED_QUORUM_NUMERATOR
        );
        _check("Governor.token() == GovernanceToken", address(g.token()) == govToken);
        _check(
            string.concat(
                "Governor proposalThreshold == totalSupply/100  (got ", vm.toString(g.proposalThreshold()), ")"
            ),
            g.proposalThreshold() == (10_000_000 ether / 100)
        );

        // --- oracle freshness ---
        ChainlinkPriceOracle o = ChainlinkPriceOracle(oracle);
        string memory cfgPath = string.concat(vm.projectRoot(), "/script/config/", vm.toString(block.chainid), ".json");
        string memory cfg = vm.readFile(cfgPath);
        address weth = cfg.readAddress(".tokens.weth");
        address usdc = cfg.readAddress(".tokens.usdc");

        uint256 wethPrice = o.getPriceSafe(weth, 86_400);
        _check(string.concat("Oracle ETH price > 0  (got ", vm.toString(wethPrice), ")"), wethPrice > 0);
        uint256 usdcPrice = o.getPriceSafe(usdc, 86_400);
        _check(string.concat("Oracle USDC price > 0 (got ", vm.toString(usdcPrice), ")"), usdcPrice > 0);

        // Persist report
        string memory outPath = string.concat(vm.projectRoot(), "/docs/post-deployment-report.md");
        vm.writeFile(outPath, _report);
        console.log("Wrote", outPath);
    }

    function _assertOwnership(string memory json, address timelock, address deployer) internal {
        address treasuryProxy = json.readAddress(".TreasuryProxy");
        address lendingPool = json.readAddress(".LendingPool");
        address pairFactory = json.readAddress(".PairFactory");
        address yieldVault = json.readAddress(".YieldVault");
        address oracle = json.readAddress(".Oracle");
        address lpNFT = json.readAddress(".LPPositionNFT");
        address samplePair = json.readAddress(".SamplePair");

        _check("Treasury admin == Timelock", _hasAdmin(treasuryProxy, timelock));
        _check("LendingPool admin == Timelock", _hasAdmin(lendingPool, timelock));
        _check("PairFactory admin == Timelock", _hasAdmin(pairFactory, timelock));
        _check("YieldVault admin == Timelock", _hasAdmin(yieldVault, timelock));
        _check("Oracle admin == Timelock", _hasAdmin(oracle, timelock));
        _check("LPPositionNFT admin == Timelock", _hasAdmin(lpNFT, timelock));
        _check("SamplePair admin == Timelock", _hasAdmin(samplePair, timelock));

        if (deployer != address(0)) {
            _check("Deployer renounced Treasury admin", !_hasAdmin(treasuryProxy, deployer));
            _check("Deployer renounced LendingPool admin", !_hasAdmin(lendingPool, deployer));
            _check("Deployer renounced PairFactory admin", !_hasAdmin(pairFactory, deployer));
            _check("Deployer renounced YieldVault admin", !_hasAdmin(yieldVault, deployer));
            _check("Deployer renounced Oracle admin", !_hasAdmin(oracle, deployer));
            _check("Deployer renounced LPPositionNFT admin", !_hasAdmin(lpNFT, deployer));
            _check("Deployer renounced SamplePair admin", !_hasAdmin(samplePair, deployer));
            _check("Deployer renounced Timelock admin", !_hasAdmin(timelock, deployer));
        }
    }

    function _hasAdmin(address target, address account) internal view returns (bool) {
        return IAccessControl(target).hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    function _check(string memory name, bool ok) internal {
        if (ok) {
            _line(string.concat("- [x] ", name));
        } else {
            _line(string.concat("- [ ] **FAIL: ", name, "**"));
            revert(string.concat("PostDeployCheck failed: ", name));
        }
    }

    function _line(string memory s) internal {
        _report = string.concat(_report, s, "\n");
    }
}
