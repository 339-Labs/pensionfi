// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IGovernor} from "../interfaces/IGovernor.sol";
import "../market/CToken.sol";

contract StrategyManager is IStrategyManager{

    mapping(address => address) public tokenStrategy;
    CToken public immutable ctoken;

    IGovernor public immutable governor;

    constructor(address _ctoken, address _governor) {
        ctoken = CToken(_ctoken);
        governor = _governor;
    }

    modifier onlyGovernor() {
        require(msg.sender == address(governor), "StrategyBase.onlyStrategyManager");
        _;
    }

    function deposit(address from, uint256 amount) external returns (uint256){
        // todo
        require(msg.sender == ctoken, "Only ETHStrategy can call");
        require(address(this).balance >= amount, "Insufficient ETH balance");

        // Convert ETH to WETH and deposit to lending pool
        // Implementation depends on your WETH contract
        ctoken.mint(WETH_ADDRESS, amount);
        return 0;
    }

    function withdraw(address from) external{
        // todo
        require(msg.sender == ethStrategy, "Only ETHStrategy can call");

        // Redeem from lending pool
        ctoken.redeem(WETH_ADDRESS, amount);
    }

    /**
     * @notice Get earned interest from lending
     */
    function getEarnedInterest() external view returns (uint256) {
        // Calculate interest earned
        // Implementation depends on your specific requirements
        return 0;
    }

    function claim(address from) external{
        // todo
    }

    function modifyUser(address strategy,address source,address target) external onlyGovernor returns (bool){
        require(strategy != address(0), "Invalid strategy address");
        require(source != address(0), "Invalid source address");
        require(target != address(0), "Invalid target address");
        require(source != target, "Source and target addresses cannot be same");
        (bool success, bytes memory returnData) = strategy.call(
            abi.encodeWithSignature("modifyUser(address,address)", source, target)
        );
        return success;
    }

    function addStrategy(address strategy,address token) external onlyGovernor returns (bool){
        require(strategy == address(0), "not use 0 address");
        require(tokenStrategy[token] == address(0), "Address already exists in blacklist");
        tokenStrategy[strategy] = token;
        return true;
    }

    receive() external payable {}

}
