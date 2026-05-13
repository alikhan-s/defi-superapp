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

    function withdrawETH(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool s,) = to.call{ value: amount }("");
        require(s);
    }
}

contract FullLifecycleTest is Test {
    ProtocolTimelock public timelock;
    ProtocolGovernor public governor;
    MockGovToken public token;
    MockTreasury public treasury;

    address public alice = address(1);
    address public bob = address(2);
    address public charlie = address(3);
    address public recipient = address(4);

    function setUp() public {
        token = new MockGovToken();
        token.mint(alice, 1_000_000 ether);
        token.mint(bob, 1_000_000 ether);
        token.mint(charlie, 1_000_000 ether);

        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(charlie);
        token.delegate(charlie);

        treasury = new MockTreasury();
        vm.deal(address(treasury), 10 ether);

        address[] memory empty = new address[](0);
        timelock = new ProtocolTimelock(2 days, empty, empty, address(this));
        governor = new ProtocolGovernor(IVotes(address(token)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), address(timelock));
        treasury.renounceRole(treasury.DEFAULT_ADMIN_ROLE(), address(this));

        vm.roll(block.number + 1);
    }

    function test_GovernanceLifecycle() public {
        address[] memory targets = new address[](1);
        targets[0] = address(treasury);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(treasury.withdrawETH.selector, recipient, 1 ether);

        string memory description = "Send 1 ETH to recipient";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 345_601);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);
        vm.prank(charlie);
        governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + 20 days);
        vm.roll(block.number + 2_419_201);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 3 days);
        vm.roll(block.number + 100_000);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(recipient.balance, 1 ether);

        vm.startPrank(alice);
        vm.expectRevert();
        treasury.withdrawETH(recipient, 1 ether);
        vm.stopPrank();
    }

    // ---- Coverage gap closers for ProtocolGovernor view overrides ----

    function test_proposalThreshold_externalView() public view {
        // proposalThreshold = totalSupply / 100 = 3_000_000 / 100 = 30_000 ether
        assertEq(governor.proposalThreshold(), 30_000 ether);
    }

    function test_proposalNeedsQueuing_returnsTrueForTimelockedGovernor() public {
        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(treasury.withdrawETH.selector, recipient, 1 ether);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "needs queuing");

        // With GovernorTimelockControl, any proposal requires queuing.
        assertTrue(governor.proposalNeedsQueuing(proposalId));
    }
}
