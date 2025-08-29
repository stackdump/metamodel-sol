// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./GRC20Model.sol";

interface IGRC20 {
    // ERC-20 compatible surface (GRC-style)
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address owner, address to, uint256 amount) external returns (bool);

    // Optional extensions
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;

    // Semantics / model introspection
    function modelAddress() external view returns (address);
    function modelCID() external view returns (string memory);

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract GRC20 is IGRC20 {
    // --- token metadata ---
    string private _name;
    string private _symbol;
    uint8  private _decimals;

    // --- core accounting ---
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // --- roles ---
    address public immutable owner;      // admin / minter
    address public immutable deployer;   // who deployed

    // --- semantics (Petri-net model instance) ---
    GRC20Model private _model;
    string public immutable MODEL_CID;   // cached for easy verification

    // --- modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // --- ctor ---
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address owner_,
        uint256 initialSupply // minted to owner_
    ) {
        require(owner_ != address(0), "owner zero");
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        owner = owner_;
        deployer = msg.sender;

        // Instantiate the semantic model ([$allow, $token] ordering inside)
        _model = new GRC20Model();
        MODEL_CID = _model.cid();

        // Mint initial supply per “behavior-first” spec (to owner)
        _mint(owner_, initialSupply);
    }

    // --- metadata ---
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function decimals() external view override returns (uint8) { return _decimals; }

    // --- supply + balances ---
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view override returns (uint256) { return _balances[a]; }

    // --- allowances ---
    function allowance(address a, address s) external view override returns (uint256) {
        return _allowances[a][s];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        require(current >= amount, "allowance");
        unchecked { _allowances[from][msg.sender] = current - amount; }
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        _transfer(from, to, amount);
        return true;
    }

    // --- mint/burn (owner-controlled mint; self burn) ---
    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    // --- model visibility ---
    function modelAddress() external view override returns (address) {
        return address(_model);
    }

    function modelCID() external view override returns (string memory) {
        return MODEL_CID;
    }

    // --- internals ---
    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "to=0");
        uint256 fromBal = _balances[from];
        require(fromBal >= amount, "balance");
        unchecked { _balances[from] = fromBal - amount; }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address a, address s, uint256 amount) internal {
        require(s != address(0), "spender=0");
        _allowances[a][s] = amount;
        emit Approval(a, s, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "to=0");
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 bal = _balances[from];
        require(bal >= amount, "balance");
        unchecked { _balances[from] = bal - amount; }
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
