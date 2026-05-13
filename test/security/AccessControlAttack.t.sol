/**
 * @notice ACCESS CONTROL CASE STUDY
 * VulnerableTreasury.sol exposes a PUBLIC withdrawETH function with no role checks.
 * Attack: Any external user can call withdrawETH and drain the protocol's funds.
 * Fix: TreasuryV1.sol inherits AccessControlUpgradeable and strictly restricts
 * withdrawETH using `onlyRole(FUND_MANAGER_ROLE)`.
 */
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { VulnerableTreasury } from "../../src/security/VulnerableTreasury.sol";
import { TreasuryV1 } from "../../src/treasury/TreasuryV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AccessControlAttackTest is Test {
    VulnerableTreasury public vulnerable;
    TreasuryV1 public secureTreasury;
    address public attacker = address(0xBAD);
    address public admin = address(1);

    function setUp() public {
        vulnerable = new VulnerableTreasury();
        vm.deal(address(vulnerable), 10 ether);

        TreasuryV1 impl = new TreasuryV1();
        bytes memory data = abi.encodeCall(TreasuryV1.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        secureTreasury = TreasuryV1(payable(address(proxy)));
        vm.deal(address(secureTreasury), 10 ether);
    }

    function test_vulnerable_anyoneCanDrain() public {
        vm.startPrank(attacker);
        vulnerable.withdrawETH(attacker, 10 ether);
        vm.stopPrank();

        assertEq(attacker.balance, 10 ether);
        assertEq(address(vulnerable).balance, 0);
    }

    function test_fixed_unauthorizedReverts() public {
        vm.startPrank(attacker);
        bytes4 selector = IAccessControl.AccessControlUnauthorizedAccount.selector;
        bytes32 role = secureTreasury.FUND_MANAGER_ROLE();
        vm.expectRevert(abi.encodeWithSelector(selector, attacker, role));
        secureTreasury.withdrawETH(attacker, 10 ether);
        vm.stopPrank();
    }
}
