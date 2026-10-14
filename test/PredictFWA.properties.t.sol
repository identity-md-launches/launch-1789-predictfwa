// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PredictFWA} from "src/PredictFWA.sol";

/// @dev An intermediary with no tokens or approvals unless a test explicitly grants them.
contract PFWAForwarder {
    function transfer(PredictFWA token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function approve(PredictFWA token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transferFrom(PredictFWA token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Complements the basic ERC-20 tests with boundary and multi-transaction properties.
/// forge-config: default.fuzz.runs = 1024
contract PredictFWAPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PredictFWA internal token;
    address internal deployer;
    address internal holder;
    address internal spender;
    address internal recipient;

    function setUp() public {
        deployer = makeAddr("property deployer");
        holder = makeAddr("property holder");
        spender = makeAddr("property spender");
        recipient = makeAddr("property recipient");
        vm.prank(deployer);
        token = new PredictFWA();
    }

    function test_oneBaseUnitCanBeTransferredAndReturned() public {
        vm.prank(deployer);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);

        vm.prank(holder);
        assertTrue(token.transfer(deployer, 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxUintTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(recipient, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCannotOverdrawAndRemainsUsableAfterFailure() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, type(uint256).max);

        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_infiniteApprovalCanBeRevokedAfterUse() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        vm.prank(deployer);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedToOneBaseUnit() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 2);
        assertEq(token.allowance(deployer, spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_zeroDelegatedTransferToZeroRejectsFiniteAndInfiniteApprovals() public {
        uint256[3] memory approvals = [uint256(0), uint256(17), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(deployer);
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(deployer, address(0), 0);
            assertEq(token.allowance(deployer, spender), approvals[i]);
            assertEq(token.balanceOf(deployer), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_selfApprovalAllowsDelegatedSelfTransferButConsumesAllowance() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(deployer, SUPPLY));
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        vm.stopPrank();
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, deployer, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_sendingTokensToTokenContractDoesNotBurnThem() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_forwarderCannotSpendTransactionOriginsBalance() public {
        PFWAForwarder forwarder = new PFWAForwarder();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(forwarder), 0, 1)
        );
        vm.prank(deployer, deployer);
        forwarder.transfer(token, recipient, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(forwarder)), 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_forwarderCannotSpendTransactionOriginsAllowance() public {
        PFWAForwarder forwarder = new PFWAForwarder();
        vm.prank(deployer);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(forwarder), 0, 1)
        );
        vm.prank(spender, spender);
        forwarder.transferFrom(token, deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), 2);
        assertEq(token.allowance(deployer, address(forwarder)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(deployer);
        assertTrue(token.approve(address(forwarder), 1));
        vm.prank(spender, spender);
        assertTrue(forwarder.transferFrom(token, deployer, recipient, 1));
        assertEq(token.allowance(deployer, address(forwarder)), 0);
        assertEq(token.allowance(deployer, spender), 2);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_forwardedApprovalBelongsToForwarder() public {
        PFWAForwarder forwarder = new PFWAForwarder();
        vm.prank(deployer, deployer);
        assertTrue(forwarder.approve(token, spender, type(uint256).max));
        assertEq(token.allowance(address(forwarder), spender), type(uint256).max);
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testFuzz_transferCycleRestoresBalancesAndPreservesApproval(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(deployer);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), amount);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(recipient);
        assertTrue(token.transfer(deployer, amount));

        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedSpendingEqualsSingleSpending(uint256 approved, uint256 amount, uint256 first)
        public
    {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        first = bound(first, 0, amount);
        vm.prank(deployer);
        PredictFWA single = new PredictFWA();
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, approved));
        assertTrue(single.approve(spender, approved));
        vm.stopPrank();
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, recipient, first));
        assertTrue(token.transferFrom(deployer, recipient, amount - first));
        assertTrue(single.transferFrom(deployer, recipient, amount));
        vm.stopPrank();

        assertEq(token.balanceOf(deployer), single.balanceOf(deployer));
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.allowance(deployer, spender), single.allowance(deployer, spender));
        assertEq(token.allowance(deployer, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_returnedTokensDoNotRestoreSpentAllowance(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY);
        first = bound(first, 1, approved);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, first));
        vm.prank(recipient);
        assertTrue(token.transfer(deployer, first));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, approved - first));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);

        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - (approved - first));
        assertEq(token.balanceOf(recipient), approved - first);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFundingWithoutReapproval(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), amount);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(deployer);
        assertTrue(token.transfer(holder, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransfersCannotBypassBalanceChecks(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.transfer(holder, balance));
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount);
        vm.expectRevert(reason);
        vm.prank(holder);
        token.transfer(holder, amount);
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(holder, holder, amount);

        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
