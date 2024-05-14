/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
*/
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./JwarpMUSDCSubaccount.sol";
import "../interfaces/IJUSDBank.sol";

contract JwarpMUSDCFactory is ERC20, Ownable {
    address public immutable template;
    address public immutable mUSDC;
    address public usdc;
    address public well;
    address public controller;
    address public jusdBank;
    address public flashLoanAddress;
    mapping(address => address) subaccountRegistry;

    using SafeERC20 for IERC20;

    modifier onlyFlashloan() {
        require(flashLoanAddress == msg.sender, "Ownable: caller is not the flashLoanAddress");
        _;
    }

    event NewWarpSubaccount(address indexed master, address subaccountAddress);

    constructor(
        address _mUSDC,
        address _controller,
        address _well,
        address _usdc,
        address _jusdBank,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
    {
        mUSDC = _mUSDC;
        controller = _controller;
        jusdBank = _jusdBank;
        well = _well;
        usdc = _usdc;
        template = address(new JwarpMUSDCSubaccount());
        JwarpMUSDCSubaccount(template).init(address(this), address(this), controller, mUSDC, well, usdc);
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function _newSubaccount(address owner) internal returns (address subaccount) {
        subaccount = Clones.clone(template);
        JwarpMUSDCSubaccount(subaccount).init(owner, address(this), controller, mUSDC, well, usdc);
        subaccountRegistry[owner] = subaccount;
        emit NewWarpSubaccount(owner, subaccount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if (from != jusdBank && to != jusdBank) {
            address toSubaccount = subaccountRegistry[to];
            address fromSubaccount = subaccountRegistry[from];
            if (toSubaccount == address(0)) {
                toSubaccount = _newSubaccount(to);
            }
            JwarpMUSDCSubaccount(fromSubaccount).claimReward();
            JwarpMUSDCSubaccount(fromSubaccount).transferMUSDC(toSubaccount, amount);
            super._transfer(from, to, amount);
        } else if (from == jusdBank && to != jusdBank) {
            address toSubaccount = subaccountRegistry[to];
            require(to == flashLoanAddress || toSubaccount != address(0), "no subaccount");
            super._transfer(from, to, amount);
        } else {
            // when to == jusdBank
            super._transfer(from, to, amount);
        }
    }

    function setFlashloan(address _flashloanAddress) external onlyOwner {
        flashLoanAddress = _flashloanAddress;
    }

    function getSubaccount(address master) external view returns (address) {
        return subaccountRegistry[master];
    }

    function mUSDCBalanceOf(address from) external view returns (uint256) {
        return IERC20(mUSDC).balanceOf(subaccountRegistry[from]);
    }

    function warp(uint256 amount) external {
        address subaccount = subaccountRegistry[msg.sender];
        if (subaccount == address(0)) {
            subaccount = _newSubaccount(msg.sender);
        }
        IERC20(mUSDC).safeTransferFrom(msg.sender, subaccount, amount);
        _mint(msg.sender, amount);
    }

    function unwarp(uint256 amount) external {
        address subaccount = subaccountRegistry[msg.sender];
        _burn(msg.sender, amount);
        JwarpMUSDCSubaccount(subaccount).claimReward();
        JwarpMUSDCSubaccount(subaccount).withdraw(amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function claimReward() external {
        address subaccount = subaccountRegistry[msg.sender];
        JwarpMUSDCSubaccount(subaccount).claimReward();
    }

    function transferMUSDCFrom(address from, address to, uint256 amount) external onlyFlashloan {
        address fromSubaccount = subaccountRegistry[from];
        JwarpMUSDCSubaccount(fromSubaccount).transferMUSDC(to, amount);
    }
}
