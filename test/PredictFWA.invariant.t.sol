// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PredictFWA} from "../src/PredictFWA.sol";

/// @dev Exercises four holders with an independent balance and allowance ledger.
contract PFWAHandler is Test {
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

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
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
        vm.prank(owner);
        (bool ok,) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        assertFalse(ok, "an overspend changed balances");
    }

    function rejectUnapprovedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", owner, to, 1));
        assertFalse(ok, "unapproved spend succeeded");
    }
}

contract PredictFWAInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PFWAHandler internal handler;
    PredictFWA internal token;

    function setUp() public {
        handler = new PFWAHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PFWAHandler.transfer.selector;
        selectors[1] = PFWAHandler.approve.selector;
        selectors[2] = PFWAHandler.transferFrom.selector;
        selectors[3] = PFWAHandler.rejectOverspend.selector;
        selectors[4] = PFWAHandler.rejectUnapprovedSpend.selector;
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
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
