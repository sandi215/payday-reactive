// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PayDayReactive } from "../src/PayDayReactive.sol";

/// @notice Wire PayDayReactive (Lasna) to PayDayPayer (Base Sepolia).
/// @dev forge script script/SetPayer.s.sol:SetPayer \
///        --rpc-url https://lasna-rpc.rnk.dev/ --broadcast \
///        --private-key $PRIVATE_KEY
///      Env: REACTIVE_ADDR, PAYER_ADDR.
contract SetPayer is Script {
    function run() public {
        address reactiveAddr = vm.envAddress("REACTIVE_ADDR");
        address payerAddr = vm.envAddress("PAYER_ADDR");
        vm.startBroadcast();
        PayDayReactive(payable(reactiveAddr)).setPayer(payerAddr);
        vm.stopBroadcast();
        console.log("PayDayReactive wired to payer:", payerAddr);
    }
}
