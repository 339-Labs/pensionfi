// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title InterestRateModel
 * @notice Calculates interest rates based on utilization
 */
contract InterestRateModel {
    uint256 public constant BLOCKS_PER_YEAR = 2102400; // Assuming 15 second blocks
    uint256 public constant BASE_RATE = 0.02e18; // 2% base rate
    uint256 public constant MULTIPLIER = 0.1e18; // 10% multiplier
    uint256 public constant JUMP_MULTIPLIER = 1.09e18; // 109% jump multiplier
    uint256 public constant OPTIMAL_UTILIZATION = 0.8e18; // 80% optimal utilization

    /**
     * @notice Calculate borrow rate based on utilization
     * @param cash Amount of cash in the pool
     * @param borrows Amount of borrows
     * @param reserves Amount of reserves
     * @return Borrow rate per block
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        uint256 util = getUtilizationRate(cash, borrows, reserves);

        if (util <= OPTIMAL_UTILIZATION) {
            return (util * MULTIPLIER) / 1e18 + BASE_RATE;
        } else {
            uint256 normalRate = (OPTIMAL_UTILIZATION * MULTIPLIER) / 1e18 + BASE_RATE;
            uint256 excessUtil = util - OPTIMAL_UTILIZATION;
            return (excessUtil * JUMP_MULTIPLIER) / 1e18 + normalRate;
        }
    }

    /**
     * @notice Calculate supply rate based on borrow rate
     * @param cash Amount of cash in the pool
     * @param borrows Amount of borrows
     * @param reserves Amount of reserves
     * @param reserveFactor Reserve factor (e.g., 0.1e18 for 10%)
     * @return Supply rate per block
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactor
    ) public pure returns (uint256) {
        uint256 oneMinusReserveFactor = 1e18 - reserveFactor;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / 1e18;
        return (getUtilizationRate(cash, borrows, reserves) * rateToPool) / 1e18;
    }

    /**
     * @notice Calculate utilization rate
     */
    function getUtilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }
        return (borrows * 1e18) / (cash + borrows - reserves);
    }
}
