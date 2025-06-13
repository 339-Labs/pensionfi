// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStrategyManager {

    function deposit(address from, uint256 amount) external returns (uint256);

    function withdraw(address from) external;

    function claim(address from) external;

    function modifyUser(address strategy,address source,address target) external returns (bool);

    function addStrategy(address strategy,address token) external returns (bool);

}
