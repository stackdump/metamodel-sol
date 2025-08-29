// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// assumes Metamodel.sol (the base contract I provided) is available in your project
import "./Metamodel.sol";

contract GRC20Model is Metamodel {
    // ---- Tunables (from your modelOpts) ----
    int256 constant TRANSFER_AMT   = 10;
    int256 constant APPROVE_AMT    = 400;
    int256 constant SPEND_AMT      = 100;
    int256 constant MINT_AMT       = 5;
    int256 constant BURN_AMT       = 2;

    int256 constant SUPPLY_INITIAL    = 0;
    int256 constant OWNER_BALANCE     = 1100;
    int256 constant RECIPIENT_BALANCE = 0;
    int256 constant ALLOW_INITIAL     = 0;
    int256 constant MINTER_INITIAL    = 1;
    int256 constant SPENDER_INITIAL   = 1;   // “dummy spender” to enable transferFrom

    string constant OBJ_ALLOW = "$allow";
    string constant OBJ_TOKEN = "$token";

    constructor() {
        // Objects: inverted view — "$allow" first, then "$token"
        string;
        objs[0] = OBJ_ALLOW;
        objs[1] = OBJ_TOKEN;
        addObjects(objs);

        // ---- Places ----
        // Helper: empty capacity (0 = unlimited) sized to objects
        int256[] memory cap = _zeroTT();

        // $owner { initial: Token=1100 }
        addPlace("$owner",    T(OWNER_BALANCE, OBJ_TOKEN), cap, 43,  266, "");

        // $recipient { initial: Token=0 }
        addPlace("$recipient", T(RECIPIENT_BALANCE, OBJ_TOKEN), cap, 782, 442, "");

        // $spender { initial: Allow=1 }
        addPlace("$spender",  T(SPENDER_INITIAL, OBJ_ALLOW), cap, 44,  443, "");

        // allow(owner->spender) { initial: Allow=0 }
        addPlace("allow(owner->spender)", T(ALLOW_INITIAL, OBJ_ALLOW), cap, 525, 275, "");

        // supply { initial: Token=0 }
        addPlace("supply",    T(SUPPLY_INITIAL, OBJ_TOKEN), cap, 513, 111, "");

        // $burned { initial: 0 }
        addPlace("$burned",   _zeroTT(), cap, 764, 111, "");

        // $minter { initial: Allow=1 }
        addPlace("$minter",   T(MINTER_INITIAL, OBJ_ALLOW), cap, 50,  113, "");

        // $void { initial: 0 }
        addPlace("$void",     _zeroTT(), cap, 941, 274, "");

        // ---- Transitions ----
        addTransition("transfer",       349, 444, 0, "");
        addTransition("approveAdd",     345, 277, 0, "");
        addTransition("approveZero",    680, 275, 0, "");
        addTransition("transferFrom",   619, 444, 0, "");
        addTransition("spendAllowance", 799, 275, 0, "");
        addTransition("mint",           347, 185, 0, "");
        addTransition("burn",           345, 113, 0, "");

        // ---- Arrows / Inhibits ----
        // transfer
        addArrow("$owner", "transfer", TRANSFER_AMT, OBJ_TOKEN, false, "");
        addArrow("transfer", "$recipient", TRANSFER_AMT, OBJ_TOKEN, false, "");

        // approveAdd & approveZero paths on $allow
        addArrow("approveAdd", "$owner", 0, OBJ_ALLOW, true, ""); // inhibit
        addArrow("approveAdd", "allow(owner->spender)", APPROVE_AMT, OBJ_ALLOW, false, "");
        addArrow("allow(owner->spender)", "approveZero", SPEND_AMT, OBJ_ALLOW, false, "");
        addArrow("approveZero", "$void", SPEND_AMT, OBJ_ALLOW, false, "");

        // transferFrom requiring both Token and Allow
        addArrow("$owner", "transferFrom", TRANSFER_AMT, OBJ_TOKEN, false, "");
        addArrow("allow(owner->spender)", "transferFrom", TRANSFER_AMT, OBJ_ALLOW, false, "");
        addArrow("transferFrom", "$recipient", TRANSFER_AMT, OBJ_TOKEN, false, "");

        // spendAllowance drain path
        addArrow("allow(owner->spender)", "spendAllowance", SPEND_AMT, OBJ_ALLOW, false, "");
        addArrow("spendAllowance", "$void", SPEND_AMT, OBJ_ALLOW, false, "");

        // mint/burn with minter inhibit
        addArrow("mint", "$minter", 0, OBJ_ALLOW, true, ""); // inhibit
        addArrow("mint", "$owner",  MINT_AMT, OBJ_TOKEN, false, "");
        addArrow("mint", "supply",  MINT_AMT, OBJ_TOKEN, false, "");

        addArrow("$owner", "burn", BURN_AMT, OBJ_TOKEN, false, "");
        addArrow("supply", "burn", BURN_AMT, OBJ_TOKEN, false, "");
        addArrow("burn", "$burned", BURN_AMT, OBJ_TOKEN, false, "");

        // transferFrom also inhibited by $spender
        addArrow("transferFrom", "$spender", 0, OBJ_ALLOW, true, "");
    }

    // convenience getter for your build artifact / cross-check
    function getCID() external view returns (string memory) {
        return cid();
    }

    // make a per-object-length zero vector for initial/capacity
    function _zeroTT() internal view returns (int256[] memory a) {
        uint256 n = objects.length == 0 ? 1 : objects.length;
        a = new int256[](n);
    }
}
