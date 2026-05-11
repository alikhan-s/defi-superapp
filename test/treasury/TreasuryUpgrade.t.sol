pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TreasuryV1} from "../../src/treasury/TreasuryV1.sol";
import {TreasuryV2} from "../../src/treasury/TreasuryV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TreasuryUpgradeTest is Test {
    TreasuryV1 public proxyV1;
    MockToken public token;
    
    address public admin = address(1);
    address public fundManager = address(2);
    address public upgrader = address(3);
    address public user = address(4);

    function setUp() public {
        TreasuryV1 impl = new TreasuryV1();
        bytes memory data = abi.encodeCall(TreasuryV1.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        proxyV1 = TreasuryV1(payable(address(proxy)));
        token = new MockToken();

        vm.startPrank(admin);
        proxyV1.grantRole(proxyV1.FUND_MANAGER_ROLE(), fundManager);
        proxyV1.grantRole(proxyV1.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
    }

    function test_UpgradeToV2AndPreserveState() public {
        vm.deal(address(proxyV1), 10 ether);
        token.mint(address(proxyV1), 5000);

        vm.prank(fundManager);
        proxyV1.withdrawETH(user, 2 ether);

        TreasuryV2 implV2 = new TreasuryV2();

        vm.prank(upgrader);
        proxyV1.upgradeToAndCall(address(implV2), "");

        TreasuryV2 proxyV2 = TreasuryV2(payable(address(proxyV1)));

        assertEq(address(proxyV2).balance, 8 ether);
        assertEq(proxyV2.totalETHWithdrawn(), 2 ether);
        assertTrue(proxyV2.hasRole(proxyV2.FUND_MANAGER_ROLE(), fundManager));
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000;

        vm.prank(fundManager);
        proxyV2.batchWithdrawERC20(tokens, user, amounts);

        assertEq(token.balanceOf(user), 1000);
        assertTrue(proxyV2.lastBatchTimestamp() > 0);
    }

    function test_UpgradeRevertsIfNotUpgrader() public {
        TreasuryV2 implV2 = new TreasuryV2();

        vm.expectRevert();
        vm.prank(user);
        proxyV1.upgradeToAndCall(address(implV2), "");
    }
}