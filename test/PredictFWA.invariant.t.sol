// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PredictFWA} from "../src/PredictFWA.sol";

/// @dev Exercises four holders with an independent balance and allowance ledger.
contract PFWAHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PredictFWA public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new PredictFWA();
        uint256 share = token.totalSupply() / actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("PFWA invariant actor ", vm.toString(i)));
            actors[i] = actor;
            expectedBalance[actor] = share;
            require(token.transfer(actor, share), "fixture funding failed");
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, balance < approved ? balance : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] = approved - amount;
        }
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectOverspend(uint256 ownerSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        _assertRejection(
            owner,
            abi.encodeCall(IERC20.transfer, (to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
    }

    function rejectUnapprovedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        _assertRejection(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    /// @dev Give zero, dust, exact-balance, and unlimited approvals substantial sequence coverage.
    /// A raw uint256 approval alone would usually be much larger than any holder's balance.
    function approveAtBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 kind) external {
        address owner = actors[ownerSeed % actors.length];
        uint256[6] memory amounts =
            [uint256(0), uint256(1), expectedBalance[owner], SUPPLY, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[kind % amounts.length]);
    }

    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) public {
        address from = actors[fromSeed % actors.length];
        transfer(fromSeed, toSeed, expectedBalance[from]);
    }

    /// @dev Exercise exhaustion even if randomly chosen approvals would otherwise allow large spends.
    function spendExactAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        approve(ownerSeed, spenderSeed, amount);
        transferFrom(ownerSeed, spenderSeed, toSeed, amount);
        assertEq(token.allowance(owner, spender), 0, "exact spend did not exhaust allowance");
        _assertRejection(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    /// @dev The transfer fails after allowance validation; the approval must survive unchanged.
    function rejectApprovedOverdraw(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, expectedBalance[owner] + 1, type(uint256).max);
        uint256 approved = infinite ? type(uint256).max : amount;
        approve(ownerSeed, spenderSeed, approved);
        _assertRejection(
            spender,
            abi.encodeCall(IERC20.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
        assertEq(token.allowance(owner, spender), approved, "failed transfer consumed allowance");
    }

    function rejectInvalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        uint256 amount = bound(amountSeed, 0, limit);
        bytes memory data = delegated
            ? abi.encodeCall(IERC20.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(IERC20.transfer, (address(0), amount));
        _assertRejection(
            delegated ? spender : owner,
            data,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _assertRejection(
            owner,
            abi.encodeCall(IERC20.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _assertRejection(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool ok, bytes memory reason) = address(token).call(data);
        assertFalse(ok, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected revert reason");
        // No ghost update: all balances and allowances must still match the independent ledger.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PredictFWAInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PFWAHandler internal handler;
    PredictFWA internal token;

    function setUp() public {
        handler = new PFWAHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = PFWAHandler.transfer.selector;
        selectors[1] = PFWAHandler.approve.selector;
        selectors[2] = PFWAHandler.transferFrom.selector;
        selectors[3] = PFWAHandler.rejectOverspend.selector;
        selectors[4] = PFWAHandler.rejectUnapprovedSpend.selector;
        selectors[5] = PFWAHandler.approveAtBoundary.selector;
        selectors[6] = PFWAHandler.transferEntireBalance.selector;
        selectors[7] = PFWAHandler.spendExactAllowance.selector;
        selectors[8] = PFWAHandler.rejectApprovedOverdraw.selector;
        selectors[9] = PFWAHandler.rejectInvalidRecipient.selector;
        selectors[10] = PFWAHandler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalSupplyAndAggregateBalancesStayFixed() public view {
        uint256 aggregate;
        for (uint256 i; i < 4; ++i) {
            aggregate += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(aggregate, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev A terminal liveness check: every holder can still move its full balance after any sequence.
    /// Use handler actions so its ledger stays consistent with this final consolidation as well.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.transferEntireBalance(i, (i + 1) % 4);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY, "some supply could not be transferred");
        invariant_totalSupplyAndAggregateBalancesStayFixed();
        invariant_balancesAndAllowancesMatchIndependentLedger();
    }

    function test_boundaryApprovalsAndRejectedOperationsSequence() public {
        for (uint256 kind; kind < 6; ++kind) {
            handler.approveAtBoundary(0, 1, kind);
            handler.rejectInvalidRecipient(0, 1, 1, true);
            handler.rejectInvalidRecipient(0, 1, 1, false);
            handler.rejectZeroSpender(0, type(uint256).max);
            handler.transferFrom(0, 1, 2, 1);
            invariant_balancesAndAllowancesMatchIndependentLedger();
            invariant_totalSupplyAndAggregateBalancesStayFixed();
        }
        handler.rejectApprovedOverdraw(0, 1, 0, SUPPLY, false);
        handler.rejectApprovedOverdraw(0, 1, 2, type(uint256).max, true);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
        invariant_balancesAndAllowancesMatchIndependentLedger();
        invariant_totalSupplyAndAggregateBalancesStayFixed();
    }

    function test_fullBalanceTransfersAndAllowanceExhaustionSequence() public {
        handler.transferEntireBalance(0, 1);
        assertEq(token.balanceOf(handler.actors(0)), 0);
        assertEq(token.balanceOf(handler.actors(1)), SUPPLY / 2);
        handler.spendExactAllowance(1, 2, 3, SUPPLY / 2);
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(3)), SUPPLY * 3 / 4);
        invariant_balancesAndAllowancesMatchIndependentLedger();
        invariant_totalSupplyAndAggregateBalancesStayFixed();
        afterInvariant();
    }
}
