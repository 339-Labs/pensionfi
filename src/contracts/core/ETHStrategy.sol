// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStrategy} from "../interfaces/IStrategy.sol";
import {IStrategyManager} from "../interfaces/IStrategyManager.sol";
import {PensionfiERC20} from "../core/PensionfiERC20.sol";

contract ETHStrategy is IStrategy,PensionfiERC20 {

    uint256 public constant INITIAL_TIMESTAMP = 1735689600;
    uint256 public constant INITIAL_BLOCK = 1735689600;

    uint256 public value;
    uint256 public oneDayBlock;
    uint256 public constant oneDaySeconds = 86400;
    IStrategyManager public immutable strategyManager;

    struct Record {
        uint256 amount;
        uint256 timestamp;
        uint256 block;
    }

    struct UserInfo {
        uint256 withdrawRequestTime;
        uint256 withdrawRequestBlock;
        uint256 claimRequestTime;
        uint256 claimRequestBlock;
        Record[] deposits;
        Record[] claims;
    }

    mapping(address => UserInfo) public userInfo;

    mapping(address => bool) public blackAddress;

    modifier onlyStrategyManager() {
        require(msg.sender == address(strategyManager), "StrategyBase.onlyStrategyManager");
        _;
    }

    function initialize(IStrategyManager _strategyManager,uint256 _blocksPerDay) external {
        __PensionfiERC20_init("Pensionfi ETH", "PfETH");
        strategyManager = _strategyManager;
        oneDayBlock = _blocksPerDay;
    }

    function _deposit(address from, uint256 amount) private returns (bool){
        _mint(from,amount);
        UserInfo storage sourceInfo = userInfo[from];
        sourceInfo.deposits.push(Record({
            amount: amount,
            timestamp: block.timestamp,
            block:block.number
        }));
        value +=amount;
        return true;
    }

    function _withdraw(address from) private {
        UserInfo storage sourceInfo = userInfo[from];
        require(sourceInfo.withdrawRequestTime > 0 && sourceInfo.withdrawRequestTime != INITIAL_TIMESTAMP,"please. to queue withdraw");

        require(block.timestamp > sourceInfo.withdrawRequestTime + oneDaySeconds * 7,"please. waiting 7 day");
        require(block.number > sourceInfo.withdrawRequestBlock + oneDayBlock * 7,"please. waiting 7 day");

        uint256 value = 0;
        for (uint i = 0; i < sourceInfo.deposits.length; i++) {
            value += sourceInfo.deposits[i].amount;
        }

        delete sourceInfo.deposits;
        delete sourceInfo.claims;
        delete sourceInfo.withdrawRequestBlock;
        delete sourceInfo.claimRequestBlock;
        delete sourceInfo.claimRequestTime;
        delete sourceInfo.withdrawRequestTime;

        (bool success, ) = from.call{value: value}("");
        require(success, "withdraw failed");
    }

    function _claim(address from)  {
        UserInfo storage sourceInfo = userInfo[from];
        require(sourceInfo.claimRequestTime >= 0 && sourceInfo.claimRequestTime != INITIAL_TIMESTAMP,"please. to queue claim");

        require(block.timestamp > sourceInfo.claimRequestTime + oneDaySeconds * 7,"please. waiting 7 day");
        require(block.number > sourceInfo.claimRequestBlock + oneDayBlock * 7,"please. waiting 7 day");

        // todo

    }

    function deposit(address from, uint256 amount) external onlyStrategyManager returns (bool) {

        UserInfo storage sourceInfo = userInfo[from];

        uint256 lastDepositsTime = sourceInfo.deposits[sourceInfo.deposits.length-1].timestamp;
        require(block.timestamp > lastDepositsTime + oneDaySeconds*365 ,"Deposit completed – Time not yet reached. waiting one year");

        uint256 lastDepositsBlock = sourceInfo.deposits[sourceInfo.deposits.length-1].block;
        require(block.number > lastDepositsBlock + oneDayBlock*365,"Deposit completed – block not yet reached. waiting one year");

        require(sourceInfo.deposits.length<=15,"Deposit completed 15 times. not Deposit");

        return _deposit(from,amount);
    }


    function withdrawQueue(address from) external onlyStrategyManager returns (bool){
        UserInfo storage sourceInfo = userInfo[from];

        require(sourceInfo.deposits.length>0,"no deposit");

        require(sourceInfo.withdrawRequestTime == 0 || sourceInfo.withdrawRequestTime == INITIAL_TIMESTAMP,"wait. queueing");

        sourceInfo.withdrawRequestTime = block.timestamp;
        sourceInfo.withdrawRequestBlock = block.number;

        return true;
    }


    function claimQueue(address from) external onlyStrategyManager returns (bool){

        UserInfo storage sourceInfo = userInfo[from];

        require(sourceInfo.deposits.length > 15,"not claimed,Deposit not complete");

        require(sourceInfo.claims.length < 20,"You have already claimed");

        uint256 lastDepositsTime = sourceInfo.deposits[sourceInfo.deposits.length-1].timestamp;
        require(block.timestamp > lastDepositsTime + oneDaySeconds * 365 * 5,"Too early to claim – Time not yet reached. waiting 5 year");

        uint256 lastDepositsBlock = sourceInfo.deposits[sourceInfo.deposits.length-1].block;
        require(block.number > lastDepositsBlock + oneDayBlock * 356 * 5,"Too early to claim – block not yet reached. waiting 5 year");

        require(sourceInfo.claimRequestTime == 0 || sourceInfo.claimRequestTime == INITIAL_TIMESTAMP,"wait. queueing");

        uint256 lastClaimsTime = sourceInfo.claims[sourceInfo.claims.length-1].timestamp;
        require(block.timestamp > lastClaimsTime + oneDaySeconds*30,"Too early to claim – time lock. waiting 30 day");

        uint256 lastClaimsBlock = sourceInfo.claims[sourceInfo.claims.length-1].block;
        require(block.number > lastClaimsBlock + oneDayBlock*30,"Too early to claim – block lock. waiting 30 day");

        sourceInfo.claimRequestTime = block.timestamp;
        sourceInfo.claimRequestBlock = block.number;

        return true;
    }

    function withdraw(address from) external onlyStrategyManager{
        _withdraw(from);
    }

    function claim(address from) external onlyStrategyManager{
        _claim(from);
    }

    function modifyUser(address source,address target) external onlyStrategyManager returns (bool){

        UserInfo storage targetInfo = userInfo[target];
        require(targetInfo.deposits.length == 0,"address exit. please use other address");

        UserInfo storage sourceInfo = userInfo[source];

        targetInfo.withdrawRequestTime = INITIAL_TIMESTAMP;
        targetInfo.withdrawRequestBlock = sourceInfo.withdrawRequestBlock;
        targetInfo.claimRequestTime = INITIAL_TIMESTAMP;
        targetInfo.claimRequestBlock = sourceInfo.claimRequestBlock;

        for (uint i = 0; i < sourceInfo.deposits.length; i++) {
            targetInfo.deposits.push(sourceInfo.deposits[i]);
        }

        for (uint i = 0; i < sourceInfo.claims.length; i++) {
            targetInfo.claims.push(sourceInfo.claims[i]);
        }

        blackAddress[source] = false;

        return true;
    }

    function readUserInfo(address from) external view returns (uint256,uint256 ,uint256 ,uint256){
        UserInfo storage sourceInfo = userInfo[from];
        return (sourceInfo.withdrawRequestTime,sourceInfo.claimRequestTime,sourceInfo.deposits.length,sourceInfo.claims.length);
    }


    function transferToMarket(uint256 amount, address market) external onlyStrategyManager {
        require(amount > 0, "Transfer amount must be positive");
        require(amount <= address(this).balance, "Insufficient balance");
        require(market != address(0), "Invalid comptroller address");
        // 转移ETH到market
        (bool success, ) = address.call{value: amount}("");
        require(success, "ETH transfer failed");
    }


    receive() external payable{}


}
