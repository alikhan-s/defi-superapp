pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { TreasuryV1 } from "../../src/treasury/TreasuryV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RejectETH {
    receive() external payable {
        revert("Rejecting ETH");
    }
}

contract TreasuryV1Test is Test {
    TreasuryV1 public treasury;
    MockToken public token;

    address public admin = address(1);
    address public fundManager = address(2);
    address public upgrader = address(3);
    address public pauser = address(4);
    address public user = address(5);

    function setUp() public {
        TreasuryV1 impl = new TreasuryV1();
        bytes memory data = abi.encodeCall(TreasuryV1.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        treasury = TreasuryV1(payable(address(proxy)));
        token = new MockToken();

        vm.startPrank(admin);
        treasury.grantRole(treasury.FUND_MANAGER_ROLE(), fundManager);
        treasury.grantRole(treasury.UPGRADER_ROLE(), upgrader);
        treasury.grantRole(treasury.PAUSER_ROLE(), pauser);
        vm.stopPrank();
    }

    function test_InitializeOnce() public {
        vm.expectRevert();
        treasury.initialize(admin);
    }

    function testFuzz_WithdrawETH(uint256 amount) public {
        vm.assume(amount > 0 && amount < 10_000 ether);
        vm.deal(address(treasury), amount);

        vm.prank(fundManager);
        treasury.withdrawETH(user, amount);

        assertEq(user.balance, amount);
        assertEq(treasury.totalETHWithdrawn(), amount);
    }

    function test_WithdrawETH_RevertsIfNotFundManager() public {
        vm.deal(address(treasury), 1 ether);
        vm.expectRevert();
        vm.prank(user);
        treasury.withdrawETH(user, 1 ether);
    }

    function test_WithdrawERC20() public {
        token.mint(address(treasury), 1000);

        vm.prank(fundManager);
        treasury.withdrawERC20(address(token), user, 500);

        assertEq(token.balanceOf(user), 500);
        assertEq(treasury.totalERC20Withdrawn(address(token)), 500);
    }

    function test_CallValueSuccessCheck() public {
        vm.deal(address(treasury), 1 ether);
        RejectETH rejecter = new RejectETH();

        vm.expectRevert(TreasuryV1.ETHTransferFailed.selector);
        vm.prank(fundManager);
        treasury.withdrawETH(address(rejecter), 1 ether);
    }

    function test_PauseBlocksWithdrawals() public {
        vm.deal(address(treasury), 1 ether);

        vm.prank(pauser);
        treasury.pause();

        vm.expectRevert();
        vm.prank(fundManager);
        treasury.withdrawETH(user, 1 ether);
    }

    function test_BalanceViews() public {
        vm.deal(address(treasury), 2 ether);
        token.mint(address(treasury), 1000);

        assertEq(treasury.balanceOfETH(), 2 ether);
        assertEq(treasury.balanceOfERC20(address(token)), 1000);
    }
}
