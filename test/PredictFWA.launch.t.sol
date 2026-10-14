// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PredictFWA} from "../src/PredictFWA.sol";

/// @dev Local test fixture only. It models CREATE2 and token movements, not a live pool or factory.
contract PFWAFactoryHarness {
    function deploy(bytes32 salt) external returns (PredictFWA) {
        return new PredictFWA{salt: salt}();
    }

    function move(PredictFWA token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract PredictFWALaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    PFWAFactoryHarness internal factory;
    address internal requester;

    function setUp() public {
        factory = new PFWAFactoryHarness();
        requester = makeAddr("launch requester");
    }

    function testFuzz_create2MintsWholeSupplyToImmediateDeployer(bytes32 salt) public {
        address predicted = computeCreate2Address(salt, keccak256(type(PredictFWA).creationCode), address(factory));
        vm.prank(requester, requester);
        PredictFWA token = factory.deploy(salt);

        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0, "transaction origin must not receive the mint");
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_launchAllocationsClaimsAndTradingTransfersAreExact() public {
        PredictFWA token = factory.deploy(keccak256("PFWA launch"));
        address distributor = makeAddr("distributor fixture");
        address poolManager = makeAddr("pool manager fixture");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        address router = makeAddr("router fixture");

        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;
        assertTrue(factory.move(token, distributor, swarmShare));
        assertTrue(factory.move(token, poolManager, poolShare));
        assertTrue(factory.move(token, requester, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        uint256 traded = 123_456 * 10 ** 18 + 1;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, traded));
        assertEq(token.balanceOf(trader), traded);
        assertEq(token.balanceOf(poolManager), poolShare - traded);

        vm.prank(trader);
        assertTrue(token.approve(router, traded));
        vm.prank(router);
        assertTrue(token.transferFrom(trader, poolManager, traded));
        assertEq(token.allowance(trader, router), 0);
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(claimant) + token.balanceOf(poolManager) + token.balanceOf(requester), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeIsDeployableAndContainsNoDestructiveOrDelegateOpcodes() public {
        PredictFWA token = factory.deploy(keccak256("PFWA bytecode"));
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);

        // Skip PUSH data so embedded constants are not mistaken for executable opcodes.
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
