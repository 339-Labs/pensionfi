// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILendingManager {
    function listMarket(
        address underlying,
        string memory cTokenName,
        string memory cTokenSymbol,
        address interestRateModel,
        uint256 collateralFactor,
        uint256 reserveFactor
    ) external;

    /**
     * @notice Supply tokens to the pool
     * @param underlying Underlying token address
     * @param mintAmount Amount to supply
     */
    function mint(address underlying, uint256 mintAmount) external;

    /**
     * @notice Redeem tokens from the pool
     * @param underlying Underlying token address
     * @param redeemTokens Amount of cTokens to redeem
     */
    function redeem(address underlying, uint256 redeemTokens) external;

    /**
     * @notice Borrow tokens from the pool
     * @param underlying Underlying token address
     * @param borrowAmount Amount to borrow
     */
    function borrow(address underlying, uint256 borrowAmount) external ;

    /**
     * @notice Repay borrowed tokens
     * @param underlying Underlying token address
     * @param repayAmount Amount to repay
     */
    function repayBorrow(address underlying, uint256 repayAmount) external;

    /**
     * @notice Liquidate an undercollateralized borrow
     * @param borrower Address of the borrower
     * @param underlying Underlying token to repay
     * @param repayAmount Amount to repay
     * @param cTokenCollateral cToken collateral to seize
     */
    function liquidateBorrow(address borrower, address underlying, uint256 repayAmount, address cTokenCollateral) external ;

    /**
     * @notice Accrue interest for a market-t
     * @param underlying Underlying token address
     */
    function accrueInterest(address underlying) public ;


    /**
     * @notice Get account liquidity
     */
    function getAccountLiquidity(address user) public view returns (int256);

    /**
     * @notice Get hypothetical account liquidity
     */
    function getHypotheticalLiquidity(address user, address modifyToken, uint256 redeemTokens, uint256 borrowAmount) internal view returns (int256) ;

    /**
     * @notice Calculate seize tokens for liquidation
     */
    function calculateSeizeTokens(address underlying, address cTokenCollateral, uint256 repayAmount) internal view returns (uint256) ;

    /**
     * @notice Get total borrows for a market-t
     */
    function totalBorrows() external view returns (uint256) ;

    /**
     * @notice Get total reserves for a market-t
     */
    function totalReserves() external view returns (uint256) ;

    /**
     * @notice Get market-t information
     */
    function getMarketInfo(address underlying) external view returns (
        address cToken,
        uint256 totalSupply,
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 exchangeRate,
        uint256 borrowRate,
        uint256 supplyRate
    );

    /**
     * @notice Get user account information
     */
    function getUserAccountInfo(address user) external view returns (int256 liquidity, uint256 totalCollateralValue, uint256 totalBorrowValue) ;
}
