// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title PayDayPayer — escrow + payout side of PayDay (Base Sepolia)
/// @notice Holds escrowed ETH and pays recipients when PayDayReactive (Lasna)
///         requests a callback. Authenticates every call twice: the caller must
///         be the Base Sepolia callback proxy, and the injected sender must be
///         the authorized PayDayReactive contract.
/// @dev Built for the Reactive Omni Buildathon, track "Set It and Forget It".
///      NOTE: not yet compiled/tested — see NOTES.md (dependency install was
///      flagged by an execution-risk check; awaiting a go-ahead).
contract PayDayPayer is AbstractCallback {
    event Paid(uint256 indexed planId, address indexed recipient, uint256 amount);
    event PaymentSkipped(uint256 indexed planId, address indexed recipient, uint256 amount, string reason);
    event Funded(address indexed from, uint256 amount);

    /// @notice `callbackProxy_` is the Base Sepolia callback proxy;
    ///         `callbackSender_` is the PayDayReactive contract on Lasna.
    ///         Payable so the escrow can be seeded at deployment.
    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    /// @notice Pay `amount_` to `recipient_` from escrow. Called by the callback
    ///         proxy on behalf of the authorized reactive contract.
    /// @dev If the escrow is short or the transfer fails, the payment is skipped
    ///      (event emitted) instead of reverting — a failed callback is billed
    ///      either way, so there is no reason to burn extra gas on a revert.
    function pay(address reactive_, address recipient_, uint256 amount_, uint256 planId_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (address(this).balance < amount_) {
            emit PaymentSkipped(planId_, recipient_, amount_, "insufficient escrow");
            return;
        }
        (bool ok, ) = payable(recipient_).call{ value: amount_ }("");
        if (!ok) {
            emit PaymentSkipped(planId_, recipient_, amount_, "transfer failed");
            return;
        }
        emit Paid(planId_, recipient_, amount_);
    }

    /// @notice Top up the escrow.
    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
