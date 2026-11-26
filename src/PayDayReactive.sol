// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title PayDayReactive — recurring payments on autopilot (Reactive Lasna)
/// @notice Subscribes to CRON100 ticks (~every 2 minutes on Lasna). On each tick,
///          it scans payment plans and requests a callback to PayDayPayer on
///          Base Sepolia for every plan that is due. No bot, no server, no keeper.
/// @dev Built for the Reactive Omni Buildathon, track "Set It and Forget It".
///      NOTE: not yet compiled/tested — see NOTES.md (dependency install was
///      flagged by an execution-risk check; awaiting a go-ahead).
contract PayDayReactive is AbstractReactive {
    /// @notice Legacy system contract that emits the Cron events.
    address internal constant LEGACY_SYSTEM_ADDR = 0x0000000000000000000000000000000000fffFfF;

    /// @notice Topic 0 of the Cron100 event (every 100 blocks, ~2 minutes on Lasna).
    uint256 internal constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    /// @notice Base Sepolia chain id (destination chain for callbacks).
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @notice Gas limit requested for each callback on Base Sepolia.
    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice Max callbacks requested per CRON tick (bounds gas per react() call).
    uint256 internal constant MAX_CALLBACKS_PER_TICK = 10;

    /// @notice Minimum plan interval (60 seconds — short enough for the demo).
    uint256 internal constant MIN_INTERVAL_SECONDS = 60;

    address public owner;

    address public payer;

    struct Plan {
        address owner;
        address recipient;
        uint256 amount;
        uint256 intervalSeconds;
        uint256 nextDue;
        bool active;
    }

    Plan[] public plans;

    event PlanCreated(
        uint256 indexed planId,
        address indexed owner,
        address indexed recipient,
        uint256 amount,
        uint256 intervalSeconds,
        uint256 nextDue
    );
    event PlanCancelled(uint256 indexed planId);
    event PaymentRequested(uint256 indexed planId, address indexed recipient, uint256 amount);
    event PayerSet(address indexed payer);

    modifier onlyOwner() {
        require(msg.sender == owner, "PayDayReactive: not owner");
        _;
    }

    /// @notice Subscribes to CRON100 on deployment. Payable so the contract can
    ///         be funded with lREACT at deployment (reactive txs cost gas).
    constructor() payable {
        owner = msg.sender;
        _subscribeToCron();
    }

    /// @notice Create a recurring payment plan. The first payment is due after
    ///         one interval; the escrow lives on PayDayPayer (Base Sepolia).
    function createPlan(address recipient_, uint256 amount_, uint256 intervalSeconds_)
        external
        returns (uint256 planId)
    {
        require(recipient_ != address(0), "PayDayReactive: recipient zero");
        require(amount_ > 0, "PayDayReactive: amount zero");
        require(intervalSeconds_ >= MIN_INTERVAL_SECONDS, "PayDayReactive: interval too short");
        planId = plans.length;
        plans.push(
            Plan({
                owner: msg.sender,
                recipient: recipient_,
                amount: amount_,
                intervalSeconds: intervalSeconds_,
                nextDue: block.timestamp + intervalSeconds_,
                active: true
            })
        );
        emit PlanCreated(planId, msg.sender, recipient_, amount_, intervalSeconds_, block.timestamp + intervalSeconds_);
    }

    /// @notice Cancel a plan (only its owner). Already-requested callbacks are unaffected.
    function cancelPlan(uint256 planId_) external {
        require(planId_ < plans.length, "PayDayReactive: bad plan");
        Plan storage plan = plans[planId_];
        require(msg.sender == plan.owner, "PayDayReactive: not plan owner");
        require(plan.active, "PayDayReactive: already inactive");
        plan.active = false;
        emit PlanCancelled(planId_);
    }

    /// @notice Set (or change) the PayDayPayer contract on Base Sepolia.
    function setPayer(address payer_) external onlyOwner {
        require(payer_ != address(0), "PayDayReactive: payer zero");
        payer = payer_;
        emit PayerSet(payer_);
    }

    /// @notice Process due plans on demand (owner only). Deterministic demo path:
    ///         requesting a callback does not require an incoming event.
    function poke() external onlyOwner {
        _processDue();
    }

    /// @notice Pause automation (unsubscribe from CRON ticks).
    function pause() external onlyOwner {
        SYSTEM.unsubscribe(block.chainid, LEGACY_SYSTEM_ADDR, CRON100_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @notice Resume automation (settle any debt, then resubscribe to CRON ticks).
    function resume() external onlyOwner {
        _coverDebt();
        _subscribeToCron();
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function settleDebt() external {
        _coverDebt();
    }

    /// @notice Number of plans created so far.
    function planCount() external view returns (uint256) {
        return plans.length;
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Only CRON100 ticks drive the scheduler; anything else is ignored
        // without reverting (a revert would still be billed).
        if (log_.topic0 == CRON100_TOPIC_0) {
            _processDue();
        }
    }

    function _subscribeToCron() internal {
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON100_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    function _processDue() internal {
        require(payer != address(0), "PayDayReactive: payer not set");
        uint256 sent;
        for (uint256 i = 0; i < plans.length && sent < MAX_CALLBACKS_PER_TICK; i++) {
            Plan storage plan = plans[i];
            if (plan.active && block.timestamp >= plan.nextDue) {
                _requestPayment(i, plan);
                // Advance by one interval; if several intervals were missed the
                // plan fires again on the next tick until caught up.
                plan.nextDue += plan.intervalSeconds;
                sent++;
            }
        }
    }

    function _requestPayment(uint256 planId_, Plan storage plan_) internal {
        bytes memory payload = abi.encodeWithSignature(
            "pay(address,address,uint256,uint256)",
            address(0), // placeholder — Reactive replaces it with this contract's address
            plan_.recipient,
            plan_.amount,
            planId_
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA_CHAIN_ID,
                recipient: payer,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        emit PaymentRequested(planId_, plan_.recipient, plan_.amount);
    }
}
