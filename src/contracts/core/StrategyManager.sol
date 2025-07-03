// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IGovernor} from "../interfaces/IGovernor.sol";
import "../interfaces/ILendingManager.sol";

contract StrategyManager is IStrategyManager{

    mapping(address => address) public strategyToken;
    ILendingManager public immutable lendingManager;

    IGovernor public immutable governor;

    constructor(address _lendingManager, address _governor) {
        lendingManager = ILendingManager(_lendingManager);
        governor = _governor;
    }

    modifier onlyGovernor() {
        require(msg.sender == address(governor), "StrategyBase.onlyStrategyManager");
        _;
    }

    function deposit(address from, uint256 amount) external returns (uint256){
        // todo
        require(msg.sender == lendingManager, "Only ETHStrategy can call");
        require(address(this).balance >= amount, "Insufficient ETH balance");

        // Convert ETH to WETH and deposit to lending pool
        // Implementation depends on your WETH contract
        lendingManager.mint(WETH_ADDRESS, amount);
        return 0;
    }

    function withdraw(address from) external{
        // todo
        require(msg.sender == ethStrategy, "Only ETHStrategy can call");

        // Redeem from lending pool
        lendingManager.redeem(WETH_ADDRESS, amount);
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
        require(token == address(0), "not use 0 address");
        require(strategyToken[strategy] == address(0), "Address already exists in blacklist");
        strategyToken[strategy] = token;
        return true;
    }

    receive() external payable {}

}
