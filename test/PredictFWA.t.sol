// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PredictFWA} from "../src/PredictFWA.sol";

contract RejectsCallbacks {
    fallback() external {
        revert("ERC-20 transfers must not call the recipient");
    }
}

contract PredictFWATest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    PredictFWA internal token;
    address internal deployer;
    address internal holder;
    address internal spender;
    address internal recipient;
    address internal stranger;

    function setUp() public {
        deployer = makeAddr("deployer");
        holder = makeAddr("holder");
        spender = makeAddr("spender");
        recipient = makeAddr("recipient");
        stranger = makeAddr("stranger");
        vm.prank(deployer);
        token = new PredictFWA();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "PredictFWA");
        assertEq(token.symbol(), "PFWA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(deployer);
        PredictFWA fresh = new PredictFWA();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        uint256 amount = 123 * 10 ** 18 + 7;
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, holder, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(holder, amount));

        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(holder, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(stranger, recipient, 0);
        vm.prank(stranger);
        assertTrue(token.transfer(recipient, 0));
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractDoesNotInvokeRecipient() public {
        RejectsCallbacks receiver = new RejectsCallbacks();
        vm.prank(deployer);
        assertTrue(token.transfer(address(receiver), 100));
        assertEq(token.balanceOf(address(receiver)), 100);
        assertEq(token.balanceOf(deployer), SUPPLY - 100);
    }

    function test_transferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    function test_transferFromZeroCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(holder, 0);
    }

    function test_transferBeyondBalanceRevertsAtomically() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(holder, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyAccountCannotTransferPositiveAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transfer(holder, 1);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_approveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 50);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 50));
        assertEq(token.allowance(deployer, spender), 50);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanExceedCurrentBalance() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_approvalReplacesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(spender, 100);
        token.approve(spender, 7);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 7);
    }

    function test_revokedAllowanceCannotBeSpent() public {
        vm.startPrank(deployer);
        token.approve(spender, 100);
        token.approve(spender, 0);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 100);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_approveFromZeroCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 100);
    }

    function test_transferFromEmitsTransferAndConsumesFiniteAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, recipient, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 40));

        assertEq(token.allowance(deployer, spender), 60);
        assertEq(token.balanceOf(deployer), SUPPLY - 40);
        assertEq(token.balanceOf(recipient), 40);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_spendingExactAllowanceThenSpendingAgainReverts() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 100));
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.balanceOf(recipient), 100);
        assertEq(token.balanceOf(deployer), SUPPLY - 100);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 10));
        assertTrue(token.transferFrom(deployer, recipient, 20));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(recipient), 30);
        assertEq(token.balanceOf(deployer), SUPPLY - 30);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transferFrom(deployer, stranger, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(stranger), 0);
    }

    function test_deployerCannotSpendAnotherHoldersBalanceWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(holder, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 100));
        vm.prank(deployer);
        token.transferFrom(holder, deployer, 100);
        assertEq(token.balanceOf(holder), 100);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 100));
    }

    function test_allowanceIsSpecificToApprovedSpender() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 100));
        vm.prank(stranger);
        token.transferFrom(deployer, recipient, 100);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromExceedingAllowanceRevertsAtomically() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 100, 101));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 101);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_insufficientBalanceRestoresAllowanceOnRevert() public {
        vm.prank(holder);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 100));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 100);
        assertEq(token.allowance(holder, spender), 100);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_transferFromToZeroRestoresAllowanceOnRevert() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 100);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_transferFromToSameHolderStillConsumesAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 40));
        assertEq(token.allowance(deployer, spender), 60);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromByHolderStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_noMintBurnOrInitializationEntrypoints() public {
        bytes[8] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", stranger, SUPPLY),
            abi.encodeWithSignature("mint(uint256)", SUPPLY),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("issue(uint256)", SUPPLY),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", deployer, 1),
            abi.encodeWithSignature("initialize(address)", stranger),
            abi.encodeWithSignature("setMinter(address)", stranger)
        ];
        for (uint256 i; i < calls.length; ++i) {
            _assertUnsupportedForBothCallers(calls[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(deployer), SUPPLY);
            assertEq(token.balanceOf(stranger), 0);
        }
    }

    function test_noAdminCanSeizeFreezeOrUpgrade() public {
        vm.prank(deployer);
        token.transfer(holder, 100);
        bytes[9] memory calls = [
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", holder),
            abi.encodeWithSignature("freeze(address)", holder),
            abi.encodeWithSignature("setBlacklist(address,bool)", holder, true),
            abi.encodeWithSignature("disableTransfers()"),
            abi.encodeWithSignature("seize(address)", holder),
            abi.encodeWithSignature("transferOwnership(address)", stranger),
            abi.encodeWithSignature("setOwner(address)", stranger),
            abi.encodeWithSignature("upgradeTo(address)", stranger)
        ];
        for (uint256 i; i < calls.length; ++i) {
            _assertUnsupportedForBothCallers(calls[i]);
            assertEq(token.balanceOf(holder), 100);
            assertEq(token.totalSupply(), SUPPLY);
        }
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 100));
        assertEq(token.balanceOf(recipient), 100);
    }

    function test_directEtherPaymentIsRejected() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), token.totalSupply());
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferDoesNotCreateTokens(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(holder, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
    }

    function testFuzz_approveReplacesAllowance(address approvedSpender, uint256 first, uint256 second) public {
        vm.assume(approvedSpender != address(0));
        vm.startPrank(deployer);
        assertTrue(token.approve(approvedSpender, first));
        assertTrue(token.approve(approvedSpender, second));
        vm.stopPrank();
        assertEq(token.allowance(deployer, approvedSpender), second);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromUsesOnlyApprovedAmount(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, spent));
        assertEq(token.allowance(deployer, spender), approved - spent);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.balanceOf(recipient), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromExceedingAllowanceCannotMoveTokens(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY - 1);
        spent = bound(spent, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, spent)
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, spent);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testFuzz_transferFromWithAllowanceBeyondBalanceRollsBack(uint256 balance, uint256 spent) public {
        balance = bound(balance, 0, SUPPLY - 1);
        spent = bound(spent, balance + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(spender, spent);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, spent));
        vm.prank(spender);
        token.transferFrom(holder, recipient, spent);
        assertEq(token.allowance(holder, spender), spent);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertUnsupportedForBothCallers(bytes memory data) private {
        vm.prank(deployer);
        (bool deployerSucceeded,) = address(token).call(data);
        assertFalse(deployerSucceeded, "deployer reached an unexpected privileged entrypoint");
        vm.prank(stranger);
        (bool strangerSucceeded,) = address(token).call(data);
        assertFalse(strangerSucceeded, "stranger reached an unexpected privileged entrypoint");
    }
}
