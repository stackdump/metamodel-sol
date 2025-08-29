// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Metamodel (Solidity port)
/// @notice Core data structs + identity hash (SHA-256) + CIDv1(base32 'b') for Petri-net-like models.
/// @dev This mirrors the Go version's semantics where practical/on-chain-friendly. Heavy string rendering omitted.
contract Metamodel {
    // ---------- Types ----------
    // TokenType: vector of per-object weights. We use int256 for EVM-native math.
    struct Place {
        string label;
        int256[] tokens;    // current (unused here but available)
        int256[] initial;   // initial
        int256[] capacity;  // 0 = unlimited
        uint256 x;
        uint256 y;
        bytes   binding;    // opaque
        uint256 offset;     // set on add
    }

    struct Transition {
        string label;
        uint256 x;
        uint256 y;
        uint256 offset;     // set on add
        // For parity with Go (unused in identity): rate + binding
        uint256 rate_e18;   // fixed-point, rate * 1e18
        bytes   binding;
    }

    struct Arrow {
        string source;      // label of place/transition
        string target;      // label of place/transition
        int256[] weight;    // aligned to objects length
        bool inhibit;
        bytes binding;      // opaque
    }

    // ---------- Storage ----------
    string[] public objects;                    // e.g. ["$token", "$allow", ...]
    Place[]  public places;
    Transition[] public transitions;
    Arrow[]  public arrows;

    // label -> index maps (existence check by hasX)
    mapping(bytes32 => uint256) private placeIndex;
    mapping(bytes32 => bool)    private hasPlace;

    mapping(bytes32 => uint256) private transIndex;
    mapping(bytes32 => bool)    private hasTrans;

    // ---------- Utilities ----------
    function _key(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function _requireObjectName(string memory name) internal pure {
        bytes memory b = bytes(name);
        require(b.length > 0 && b[0] == "$", "object names must start with $");
        // keep the rest simple; Solidity string validation is expensive
    }

    // ---------- Build / mutate ----------
    function addObjects(string[] memory objs) external {
        for (uint i = 0; i < objs.length; i++) {
            _requireObjectName(objs[i]);
            objects.push(objs[i]);
        }
    }

    function addPlace(
        string memory label,
        int256[] memory initial_,
        int256[] memory capacity_,
        uint256 x,
        uint256 y,
        bytes memory binding
    ) external returns (uint256 idx) {
        bytes32 k = _key(label);
        require(!hasPlace[k], "place exists");
        require(objects.length == 0 || initial_.length == objects.length, "initial size");
        require(objects.length == 0 || capacity_.length == objects.length, "capacity size");

        idx = places.length;
        places.push(Place({
            label: label,
            tokens: new int256, // unused
            initial: initial_,
            capacity: capacity_,
            x: x,
            y: y,
            binding: binding,
            offset: idx
        }));
        placeIndex[k] = idx;
        hasPlace[k] = true;
    }

    function addTransition(
        string memory label,
        uint256 x,
        uint256 y,
        uint256 rate_e18,
        bytes memory binding
    ) external returns (uint256 idx) {
        bytes32 k = _key(label);
        require(!hasTrans[k], "transition exists");
        idx = transitions.length;
        transitions.push(Transition({
            label: label,
            x: x,
            y: y,
            offset: idx,
            rate_e18: rate_e18,
            binding: binding
        }));
        transIndex[k] = idx;
        hasTrans[k] = true;
    }

    /// @notice Build a TokenType aligned to objects. If `objectLabel` is empty, slot 0 is used.
    function T(int256 val, string memory objectLabel) public view returns (int256[] memory out) {
        uint256 size = objects.length == 0 ? 1 : objects.length;
        out = new int256[](size);
        if (bytes(objectLabel).length == 0 || size == 1) {
            out[0] = val;
            return out;
        }
        for (uint i = 0; i < objects.length; i++) {
            if (keccak256(bytes(objects[i])) == keccak256(bytes(objectLabel))) {
                out[i] = val;
                return out;
            }
        }
        // if not found, default to index 0
        out[0] = val;
    }

    /// @notice Add an arrow. If `objectLabel` is empty, weight is placed in slot 0.
    function addArrow(
        string memory source,
        string memory target,
        int256 weightForObject,     // scalar
        string memory objectLabel,  // which object slot; "" => index 0
        bool inhibit,
        bytes memory binding
    ) external {
        require(_existsNode(source) && _existsNode(target), "bad endpoints");
        int256[] memory w = T(weightForObject, objectLabel);
        arrows.push(Arrow({
            source: source,
            target: target,
            weight: w,
            inhibit: inhibit,
            binding: binding
        }));
    }

    function _existsNode(string memory label) internal view returns (bool) {
        bytes32 k = _key(label);
        return hasPlace[k] || hasTrans[k];
    }

    // ---------- Identity hash (SHA-256) and CID ----------
    /// @notice Compute identity elements (sha256 over strings), then Merkle root.
    /// Mirrors: objects (sorted asc), place labels (sorted), transition labels (sorted),
    /// and arrows as "src --> tgt" or "src -|> tgt".
    function identityHash() public view returns (bytes32) {
        bytes32[] memory leaves = _collectLeaves();
        if (leaves.length == 0) return bytes32(0);
        return _merkleRoot(leaves);
    }

    function cid() external view returns (string memory) {
        bytes32 digest = identityHash(); // SHA-256 merkle root (already 32 bytes)
        return _shaToCid(digest);
    }

    // ----- leaf collection -----
    function _collectLeaves() internal view returns (bytes32[] memory) {
        // counts: objects + places + transitions + arrows
        uint256 n = objects.length + places.length + transitions.length + arrows.length;
        bytes32[] memory tmp = new bytes32[](n);
        uint256 p = 0;

        // objects (sorted)
        {
            string[] memory o = _copyStrings(objects);
            _sortStrings(o);
            for (uint i=0; i<o.length; i++) {
                tmp[p++] = sha256(bytes(o[i]));
            }
        }
        // places (by label, sorted)
        {
            string[] memory labels = new string[](places.length);
            for (uint i=0; i<places.length; i++) labels[i] = places[i].label;
            _sortStrings(labels);
            for (uint i=0; i<labels.length; i++) {
                tmp[p++] = sha256(bytes(labels[i]));
            }
        }
        // transitions (by label, sorted)
        {
            string[] memory labels = new string[](transitions.length);
            for (uint i=0; i<transitions.length; i++) labels[i] = transitions[i].label;
            _sortStrings(labels);
            for (uint i=0; i<labels.length; i++) {
                tmp[p++] = sha256(bytes(labels[i]));
            }
        }
        // arrows (edge string then sha256)
        for (uint i=0; i<arrows.length; i++) {
            Arrow storage a = arrows[i];
            bytes memory edge = abi.encodePacked(
                a.source,
                a.inhibit ? "-|>" : "-->",
                a.target
            );
            tmp[p++] = sha256(edge);
        }

        // trim (p == n)
        return tmp;
    }

    // ----- Merkle root over bytes32 leaves using SHA-256 on concatenation -----
    function _merkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        while (leaves.length > 1) {
            uint256 paired = (leaves.length + 1) / 2;
            bytes32[] memory next = new bytes32[](paired);
            uint256 j = 0;
            for (uint i=0; i<leaves.length; i += 2) {
                if (i + 1 < leaves.length) {
                    next[j++] = sha256(abi.encodePacked(leaves[i], leaves[i+1]));
                } else {
                    next[j++] = leaves[i]; // carry if odd
                }
            }
            leaves = next;
        }
        return leaves[0];
    }

    // ----- CIDv1 (raw) with multibase 'b' + base32lower (no padding) -----
    // Layout: 0x01 | 0x55 | 0x12 | 0x20 | digest(32)
    function _shaToCid(bytes32 digest) internal pure returns (string memory) {
        bytes memory cidBytes = new bytes(1 + 1 + 2 + 32);
        uint256 p = 0;
        cidBytes[p++] = 0x01; // version 1
        cidBytes[p++] = 0x55; // raw
        cidBytes[p++] = 0x12; // multihash: sha2-256
        cidBytes[p++] = 0x20; // length 32
        for (uint i=0; i<32; i++) {
            cidBytes[p++] = digest[i];
        }
        // multibase 'b' + base32lower (RFC4648, no padding)
        return string(abi.encodePacked("b", _base32LowerNoPad(cidBytes)));
    }

    // ----- Helpers: strings -----
    function _copyStrings(string[] memory src) internal pure returns (string[] memory dst) {
        dst = new string[](src.length);
        for (uint i=0; i<src.length; i++) dst[i] = src[i];
    }

    function _sortStrings(string[] memory arr) internal pure {
        // simple in-place insertion sort (small arrays expected)
        for (uint i=1; i<arr.length; i++) {
            string memory key = arr[i];
            uint j = i;
            while (j > 0 && _lt(key, arr[j-1])) {
                arr[j] = arr[j-1];
                j--;
            }
            arr[j] = key;
        }
    }

    function _lt(string memory a, string memory b) internal pure returns (bool) {
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        uint minLen = ba.length < bb.length ? ba.length : bb.length;
        for (uint i=0; i<minLen; i++) {
            if (ba[i] < bb[i]) return true;
            if (ba[i] > bb[i]) return false;
        }
        return ba.length < bb.length;
    }

    // ----- Base32 (lowercase), no padding -----
    function _base32LowerNoPad(bytes memory data) internal pure returns (string memory) {
        // RFC 4648 alphabet (lowercase)
        bytes memory ALPH = "abcdefghijklmnopqrstuvwxyz234567";

        // 5 bytes -> 8 chars chunks. We'll stream bits.
        uint256 len = data.length;
        if (len == 0) return "";

        // Worst-case length ceil((len * 8)/5)
        uint256 outLen = (len * 8 + 4) / 5;
        bytes memory out = new bytes(outLen);

        uint256 buffer;
        uint256 bits;   // number of bits in buffer
        uint256 outPos;

        for (uint i=0; i<len; i++) {
            buffer = (buffer << 8) | uint8(data[i]);
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                uint256 idx = (buffer >> bits) & 0x1F;
                out[outPos++] = ALPH[idx];
            }
        }
        if (bits > 0) {
            uint256 idx = (buffer << (5 - bits)) & 0x1F;
            out[outPos++] = ALPH[idx];
        }
        // outPos should equal outLen
        assembly { mstore(out, outPos) }
        return string(out);
    }
}
