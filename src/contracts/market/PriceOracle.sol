// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @notice Simple price oracle for collateral valuation
 */
contract PriceOracle is Ownable {
    mapping(address => uint256) public prices;

    /**
     * @notice Set price for a token
     * @param token Token address
     * @param price Price in USD scaled by 1e18
     */
    function setPrice(address token, uint256 price) external onlyOwner {
        prices[token] = price;
    }

    /**
     * @notice Get price for a token
     * @param token Token address
     * @return Price in USD scaled by 1e18
     */
    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }
}

