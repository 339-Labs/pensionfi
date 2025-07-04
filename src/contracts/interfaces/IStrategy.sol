// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStrategy {

    function deposit(address from, uint256 amount) external returns (bool);

    function withdrawQueue(address from) external returns (bool);

    function claimQueue(address from) external returns (bool);

    function withdraw(address from) external;

    function claim(address from) external;

    function modifyUser(address source,address target) external returns (bool);

    function readUserInfo(address from) external view returns(uint256,uint256,uint256,uint256);

    function transferToMarket(uint256 amount, address market) external ;

}
