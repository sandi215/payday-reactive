// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PayDayReactive } from "../src/PayDayReactive.sol";

/// @notice Deploy PayDayReactive to Reactive Lasna (chain 5318007).
/// @dev forge script script/DeployReactive.s.sol:DeployReactive \
///        --rpc-url https://lasna-rpc.rnk.dev/ --broadcast \
///        --private-key $PRIVATE_KEY
///      The deployer needs lREACT (faucet: send Sepolia ETH to
///      0x9b9BB25f1A81078C544C829c5EB7822d747Cf434).
contract DeployReactive is Script {
    function run() public {
        vm.startBroadcast();
        PayDayReactive reactive = new PayDayReactive{ value: 1 ether }();
        vm.stopBroadcast();
        console.log("PayDayReactive deployed at:", address(reactive));
    }
}
