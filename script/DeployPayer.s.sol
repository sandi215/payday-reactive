// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { PayDayPayer } from "../src/PayDayPayer.sol";

/// @notice Deploy PayDayPayer to Base Sepolia (chain 84532).
/// @dev forge script script/DeployPayer.s.sol:DeployPayer \
///        --rpc-url https://sepolia.base.org --broadcast \
///        --private-key $PRIVATE_KEY
///      Env: REACTIVE_ADDR (PayDayReactive address on Lasna).
///      Seeds the escrow with 0.0002 ether (wallet holds ~0.0005 ETH on
///      Base Sepolia; demo plan amount is 0.0001 ether).
contract DeployPayer is Script {
    // Base Sepolia callback proxy (from Reactive docs).
    address internal constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() public {
        address reactiveAddr = vm.envAddress("REACTIVE_ADDR");
        vm.startBroadcast();
        PayDayPayer payer = new PayDayPayer{ value: 0.0002 ether }(
            IPayable(payable(BASE_SEPOLIA_PROXY)),
            reactiveAddr
        );
        vm.stopBroadcast();
        console.log("PayDayPayer deployed at:", address(payer));
    }
}
