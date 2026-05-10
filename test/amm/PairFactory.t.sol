// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { PairFactory } from "../../src/amm/PairFactory.sol";
import { Pair } from "../../src/amm/Pair.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";
import { MockERC20 } from "./helpers/MockERC20.sol";

contract PairFactoryTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    PairFactory internal factory;
    LPPositionNFT internal lpNFT;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        lpNFT = new LPPositionNFT(admin);
        factory = new PairFactory(address(lpNFT), admin);

        // Grant factory DEFAULT_ADMIN_ROLE on lpNFT so it can assign MINTER_ROLE to pairs.
        // Cache the role constant before pranking so the prank isn't consumed by the getter call.
        bytes32 defaultAdminRole = lpNFT.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        lpNFT.grantRole(defaultAdminRole, address(factory));

        tokenA = new MockERC20("TokenA", "TA", 18);
        tokenB = new MockERC20("TokenB", "TB", 18);
        tokenC = new MockERC20("TokenC", "TC", 18);
    }

    // -------------------------------------------------------------------------
    // 1. Constructor guards
    // -------------------------------------------------------------------------

    function test_constructor_rejectsZeroNFT() public {
        vm.expectRevert(PairFactory.ZeroAddress.selector);
        new PairFactory(address(0), admin);
    }

    function test_constructor_rejectsZeroAdmin() public {
        vm.expectRevert(PairFactory.ZeroAddress.selector);
        new PairFactory(address(lpNFT), address(0));
    }

    // -------------------------------------------------------------------------
    // 2. createPair — basic deployment
    // -------------------------------------------------------------------------

    function test_createPair_deploysPair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertNotEq(pair, address(0), "pair deployed");
    }

    function test_createPair_storesBidirectionalMapping() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function test_createPair_appendsToAllPairs() public {
        factory.createPair(address(tokenA), address(tokenB));

        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), factory.getPair(address(tokenA), address(tokenB)));
    }

    function test_createPair_sortedRegardlessOfInputOrder() public {
        address pairAB = factory.createPair(address(tokenA), address(tokenB));

        // A second factory instance, tokens in reversed order
        PairFactory factory2 = new PairFactory(address(lpNFT), admin);
        bytes32 defaultAdmin = lpNFT.DEFAULT_ADMIN_ROLE(); // cache before prank
        vm.prank(admin);
        lpNFT.grantRole(defaultAdmin, address(factory2));
        address pairBA = factory2.createPair(address(tokenB), address(tokenA));

        // Sorted order inside both deployments should be the same
        (address t0A,) = (Pair(pairAB).token0(), Pair(pairAB).token1());
        (address t0B,) = (Pair(pairBA).token0(), Pair(pairBA).token1());
        assertEq(t0A, t0B, "token0 is always the lower address");
    }

    function test_createPair_duplicateReverts() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(PairFactory.PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_createPair_identicalTokensReverts() public {
        vm.expectRevert(PairFactory.IdenticalTokens.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_createPair_zeroTokenReverts() public {
        vm.expectRevert(PairFactory.ZeroAddress.selector);
        factory.createPair(address(0), address(tokenA));
    }

    function test_createPair_grantsMinterRoleToPair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(lpNFT.hasRole(MINTER_ROLE, pair), "pair must have MINTER_ROLE");
    }

    function test_createPair_emitsPairCreated() public {
        (address token0, address token1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        vm.expectEmit(true, true, false, false);
        emit PairFactory.PairCreated(token0, token1, address(0), 0, false);
        factory.createPair(address(tokenA), address(tokenB));
    }

    // -------------------------------------------------------------------------
    // 3. createPairDeterministic — CREATE2
    // -------------------------------------------------------------------------

    function test_createPairDeterministic_deploysAtPredictedAddress() public {
        bytes32 salt = keccak256("salt1");

        address predicted = factory.computePairAddress(address(tokenA), address(tokenB), salt);
        address actual = factory.createPairDeterministic(address(tokenA), address(tokenB), salt);

        assertEq(actual, predicted, "CREATE2 address must match prediction");
    }

    function test_createPairDeterministic_reverseTokenOrderSameAddress() public {
        bytes32 salt = keccak256("salt2");

        address fromAB = factory.computePairAddress(address(tokenA), address(tokenB), salt);
        address fromBA = factory.computePairAddress(address(tokenB), address(tokenA), salt);
        assertEq(fromAB, fromBA, "prediction is order-independent");
    }

    function test_createPairDeterministic_differentSaltsDifferentAddresses() public {
        bytes32 salt1 = keccak256("s1");
        bytes32 salt2 = keccak256("s2");

        // Need different token pairs because token pair uniqueness prevents two deployments
        address pred1 = factory.computePairAddress(address(tokenA), address(tokenB), salt1);
        address pred2 = factory.computePairAddress(address(tokenA), address(tokenC), salt2);
        assertNotEq(pred1, pred2);
    }

    function test_createPairDeterministic_duplicateReverts() public {
        bytes32 salt = keccak256("dup");
        factory.createPairDeterministic(address(tokenA), address(tokenB), salt);

        vm.expectRevert(PairFactory.PairExists.selector);
        factory.createPairDeterministic(address(tokenA), address(tokenB), salt);
    }

    function test_createPairDeterministic_create2FailedReverts() public {
        bytes32 salt = keccak256("force-fail");

        // Plant bytecode at the predicted address so CREATE2 returns address(0)
        address predicted = factory.computePairAddress(address(tokenA), address(tokenB), salt);
        vm.etch(predicted, bytes("code"));

        vm.expectRevert(PairFactory.Create2Failed.selector);
        factory.createPairDeterministic(address(tokenA), address(tokenB), salt);
    }

    // -------------------------------------------------------------------------
    // 4. Multiple pairs
    // -------------------------------------------------------------------------

    function test_multiplePairs_allPairsGrows() public {
        factory.createPair(address(tokenA), address(tokenB));
        factory.createPair(address(tokenA), address(tokenC));
        factory.createPair(address(tokenB), address(tokenC));

        assertEq(factory.allPairsLength(), 3);
    }

    function test_multiplePairs_separateMappings() public {
        address pairAB = factory.createPair(address(tokenA), address(tokenB));
        address pairAC = factory.createPair(address(tokenA), address(tokenC));

        assertNotEq(pairAB, pairAC);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pairAB);
        assertEq(factory.getPair(address(tokenA), address(tokenC)), pairAC);
    }
}
