// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { GovernanceToken } from "../../src/tokens/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    GovernanceToken internal token;

    uint256 internal constant INITIAL_SUPPLY = 100_000_000e18;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // Private key for signing (alice)
    uint256 internal alicePk;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // Give alice a deterministic private key so we can sign EIP-712 messages.
        alicePk = 0xA11CE;
        alice = vm.addr(alicePk);

        token = new GovernanceToken("Governance Token", "GOV", INITIAL_SUPPLY, admin);
    }

    // -------------------------------------------------------------------------
    // 1. Initial mint
    // -------------------------------------------------------------------------

    function test_initialMint_recipientBalance() public view {
        assertEq(token.balanceOf(admin), INITIAL_SUPPLY);
    }

    function test_initialMint_totalSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    // -------------------------------------------------------------------------
    // 2. Standard ERC-20 operations
    // -------------------------------------------------------------------------

    function test_transfer_updatesBalances() public {
        uint256 amount = 1000e18;
        vm.prank(admin);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(admin), INITIAL_SUPPLY - amount);
    }

    function test_approve_and_transferFrom() public {
        uint256 amount = 500e18;
        vm.prank(admin);
        token.approve(alice, amount);

        assertEq(token.allowance(admin, alice), amount);

        vm.prank(alice);
        token.transferFrom(admin, bob, amount);

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(admin, alice), 0);
    }

    // -------------------------------------------------------------------------
    // 3. Delegation
    // -------------------------------------------------------------------------

    function test_selfDelegate_votingPowerEqualsBalance() public {
        vm.prank(admin);
        token.delegate(admin);

        assertEq(token.getVotes(admin), INITIAL_SUPPLY);
    }

    function test_delegateToAnother_transfersVotingPower() public {
        // alice gets some tokens then delegates to bob
        vm.prank(admin);
        token.transfer(alice, 1000e18);

        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.getVotes(bob), 1000e18);
        assertEq(token.getVotes(alice), 0);
    }

    function test_delegateBySig() public {
        vm.prank(admin);
        token.transfer(alice, 2000e18);

        uint256 nonce = token.nonces(alice);
        uint256 expiry = block.timestamp + 1 days;

        bytes32 domainSep = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"), bob, nonce, expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        token.delegateBySig(bob, nonce, expiry, v, r, s);

        assertEq(token.getVotes(bob), 2000e18);
        assertEq(token.delegates(alice), bob);
    }

    // -------------------------------------------------------------------------
    // 4. Voting power checkpoints
    // -------------------------------------------------------------------------

    function test_getVotes_afterTransfer() public {
        vm.prank(admin);
        token.delegate(admin);

        vm.prank(admin);
        token.transfer(alice, 1000e18);

        assertEq(token.getVotes(admin), INITIAL_SUPPLY - 1000e18);
    }

    function test_getPastVotes_afterRoll() public {
        vm.prank(admin);
        token.delegate(admin);

        uint256 snapshot = block.number;
        vm.roll(block.number + 1);

        // transfer happens at block snapshot+1
        vm.prank(admin);
        token.transfer(alice, 1000e18);

        // votes at snapshot should still be full supply
        assertEq(token.getPastVotes(admin, snapshot), INITIAL_SUPPLY);

        // advance one more block so the new checkpoint is finalised
        vm.roll(block.number + 1);
        assertEq(token.getPastVotes(admin, block.number - 1), INITIAL_SUPPLY - 1000e18);
    }

    // -------------------------------------------------------------------------
    // 5. Permit (ERC-2612)
    // -------------------------------------------------------------------------

    function test_permit_setsAllowance() public {
        vm.prank(admin);
        token.transfer(alice, 5000e18);

        uint256 value = 500e18;
        uint256 deadline = block.timestamp + 1 days;
        uint256 nonce = token.nonces(alice);

        bytes32 domainSep = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                bob,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        token.permit(alice, bob, value, deadline, v, r, s);

        assertEq(token.allowance(alice, bob), value);
    }

    function test_permit_expired_reverts() public {
        vm.warp(1000);
        uint256 deadline = 999; // already expired

        bytes32 digest = keccak256("dummy");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        vm.expectRevert();
        token.permit(alice, bob, 1e18, deadline, v, r, s);
    }

    // -------------------------------------------------------------------------
    // 6. Supply cap / constructor guards
    // -------------------------------------------------------------------------

    function test_constructor_rejectsZeroSupply() public {
        vm.expectRevert(GovernanceToken.ZeroInitialSupply.selector);
        new GovernanceToken("T", "T", 0, admin);
    }

    function test_constructor_rejectsZeroRecipient() public {
        vm.expectRevert(GovernanceToken.ZeroRecipient.selector);
        new GovernanceToken("T", "T", 1e18, address(0));
    }

    function test_noAdditionalMint_supplyFixed() public view {
        // There is no public mint function; total supply must remain constant.
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_decimals_is18() public view {
        assertEq(token.decimals(), 18);
    }
}
