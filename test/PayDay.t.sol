// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PayDayReactive } from "../src/PayDayReactive.sol";
import { PayDayPayer } from "../src/PayDayPayer.sol";

/// @notice Tests for PayDay. The Reactive system contract (0x8888...8888) has no
///         code in the forge test env, so its calls are mocked where the test
///         needs to assert a callback was requested.
contract PayDayTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;

    uint256 internal constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal reactiveAddr = address(0xBEEF);

    PayDayReactive internal reactive;
    PayDayPayer internal payer;

    function setUp() public {
        vm.deal(address(this), 10 ether);
        // The real system contract has no code in the test env; give the
        // address minimal runtime code (STOP) so subscribe() calls succeed.
        vm.etch(SYSTEM_ADDR, hex"00");
        reactive = new PayDayReactive{ value: 1 ether }();
        payer = new PayDayPayer{ value: 1 ether }(IPayable(payable(address(this))), reactiveAddr);
    }

    function testCreatePlan() public {
        uint256 id = reactive.createPlan(bob, 0.01 ether, 60);
        assertEq(id, 0);
        (address owner, address recipient, uint256 amount, uint256 interval, uint256 nextDue, bool active) =
            reactive.plans(0);
        assertEq(owner, address(this));
        assertEq(recipient, bob);
        assertEq(amount, 0.01 ether);
        assertEq(interval, 60);
        assertEq(nextDue, block.timestamp + 60);
        assertTrue(active);
    }

    function testCreatePlanRejectsBadParams() public {
        vm.expectRevert(bytes("PayDayReactive: recipient zero"));
        reactive.createPlan(address(0), 0.01 ether, 60);
        vm.expectRevert(bytes("PayDayReactive: amount zero"));
        reactive.createPlan(bob, 0, 60);
        vm.expectRevert(bytes("PayDayReactive: interval too short"));
        reactive.createPlan(bob, 0.01 ether, 59);
    }

    function testCancelPlanOnlyOwner() public {
        reactive.createPlan(bob, 0.01 ether, 60);
        vm.prank(alice);
        vm.expectRevert(bytes("PayDayReactive: not plan owner"));
        reactive.cancelPlan(0);
        reactive.cancelPlan(0);
        (, , , , , bool active) = reactive.plans(0);
        assertFalse(active);
    }

    function testReactRevertsForNonSystem() public {
        vm.prank(alice);
        vm.expectRevert();
        reactive.react(_cronLog());
    }

    function testReactIgnoresNonCronTopic() public {
        reactive.setPayer(address(payer));
        reactive.createPlan(bob, 0.01 ether, 60);
        vm.warp(block.timestamp + 3600);
        IReactive.LogRecord memory log = _cronLog();
        log.topic0 = 0xdeadbeef;
        vm.prank(SYSTEM_ADDR);
        reactive.react(log);
        (, , , , uint256 nextDue, ) = reactive.plans(0);
        assertEq(nextDue, block.timestamp + 60 - 3600); // unchanged, no callback requested
    }

    function testPokeRequestsCallbackForDuePlan() public {
        reactive.setPayer(address(payer));
        reactive.createPlan(bob, 0.01 ether, 60);
        vm.warp(block.timestamp + 61);
        vm.mockCall(SYSTEM_ADDR, ISystemContract.requestCallbackV_1_0.selector, abi.encode());
        vm.expectCall(SYSTEM_ADDR, abi.encodeWithSelector(ISystemContract.requestCallbackV_1_0.selector));
        reactive.poke();
        (, , , , uint256 nextDue, ) = reactive.plans(0);
        assertEq(nextDue, block.timestamp + 60 - 61 + 60); // advanced by one interval
    }

    function testPokeSkipsNotDuePlans() public {
        reactive.setPayer(address(payer));
        reactive.createPlan(bob, 0.01 ether, 3600);
        vm.expectCall(SYSTEM_ADDR, abi.encodeWithSelector(ISystemContract.requestCallbackV_1_0.selector), 0);
        reactive.poke();
    }

    function testPayerPaysFromEscrow() public {
        uint256 before = bob.balance;
        // This contract is the callback proxy, so calling pay() directly is a
        // valid stand-in for a real callback.
        payer.pay(reactiveAddr, bob, 0.01 ether, 0);
        assertEq(bob.balance, before + 0.01 ether);
        assertEq(address(payer).balance, 0.99 ether);
    }

    function testPayerSkipsWhenEscrowShort() public {
        uint256 before = bob.balance;
        payer.pay(reactiveAddr, bob, 2 ether, 1); // escrow is only 1 ether
        assertEq(bob.balance, before);
    }

    function testPayerRejectsWrongSender() public {
        vm.prank(alice);
        vm.expectRevert();
        payer.pay(reactiveAddr, bob, 0.01 ether, 0);
    }

    function testPayerRejectsWrongReactive() public {
        vm.expectRevert();
        payer.pay(address(0xDEAD), bob, 0.01 ether, 0);
    }

    function _cronLog() internal view returns (IReactive.LogRecord memory log) {
        log = IReactive.LogRecord({
            chainId: block.chainid,
            contractAddress: address(0),
            topic0: CRON100_TOPIC_0,
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: "",
            blockNumber: block.number,
            opCode: 0,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }
}
