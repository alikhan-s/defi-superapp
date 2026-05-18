pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ProtocolTimelock } from "../../src/governance/ProtocolTimelock.sol";
import { ProtocolGovernor } from "../../src/governance/ProtocolGovernor.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract MockGovToken is ERC20, ERC20Permit, ERC20Votes {
    constructor() ERC20("GovToken", "GOV") ERC20Permit("GovToken") { }

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

contract MockTreasury is AccessControl {
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    receive() external payable { }
    function withdrawETH(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) { }
}

contract GovernanceAttacksTest is Test {
    ProtocolTimelock public timelock;
    ProtocolGovernor public governor;
    MockGovToken public token;
    MockTreasury public treasury;

    address public attacker = address(0xBAD);
    address public user = address(1);

    function setUp() public {
        token = new MockGovToken();
        token.mint(user, 1_000_000 ether);
        vm.prank(user);
        token.delegate(user);

        treasury = new MockTreasury();

        address[] memory empty = new address[](0);
        timelock = new ProtocolTimelock(2 days, empty, empty, address(this));
        governor = new ProtocolGovernor(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        vm.roll(block.number + 1);
    }

    function test_RevertSubThresholdPropose() public {
        token.mint(attacker, 1);
        vm.prank(attacker);
        token.delegate(attacker);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(attacker);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Attack");
    }

    function test_BelowQuorumDefeated() public {
        token.mint(attacker, 20_000 ether);
        vm.prank(attacker);
        token.delegate(attacker);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(attacker);
        uint256 pid = governor.propose(targets, values, calldatas, "Attack");

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 345_601);

        vm.prank(attacker);
        governor.castVote(pid, 1);

        vm.warp(block.timestamp + 20 days);
        vm.roll(block.number + 2_419_201);

        assertEq(uint256(governor.state(pid)), 3);
    }

    function test_DirectTreasuryCallReverts() public {
        vm.prank(attacker);
        vm.expectRevert();
        treasury.withdrawETH(attacker, 1 ether);
    }

    function test_FlashLoanGovernanceAttackFails() public {
        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(user);
        uint256 pid = governor.propose(targets, values, calldatas, "Proposal");

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 345_601);

        token.mint(attacker, 5_000_000 ether);
        vm.prank(attacker);
        token.delegate(attacker);

        vm.prank(attacker);
        governor.castVote(pid, 1);

        bool hasVoted = governor.hasVoted(pid, attacker);
        assertTrue(hasVoted);

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(pid);
        assertEq(forVotes, 0);
    }

    function test_ProposerCanCancel() public {
        token.mint(attacker, 20_000 ether);
        vm.prank(attacker);
        token.delegate(attacker);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory desc = "Cancel me";

        vm.prank(attacker);
        uint256 pid = governor.propose(targets, values, calldatas, desc);

        vm.prank(attacker);
        governor.cancel(targets, values, calldatas, keccak256(bytes(desc)));

        assertEq(uint256(governor.state(pid)), 2);
    }
}
