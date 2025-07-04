// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/ILendingManager.sol";

/**
 * @title LendingManager.sol
 * @notice Main lending pool contract with Compound-like functionality
 */
contract LendingManager is ReentrancyGuard, Ownable,ILendingManager {
    using Math for uint256;

    struct Market {
        LendingToken cToken;                        // 对应的cToken合约
        InterestRateModel interestRateModel;        // 利率模型
        uint256 collateralFactor; // e.g., 0.75e18 for 75%  // 抵押率（如75%）
        uint256 reserveFactor; // e.g., 0.1e18 for 10%       // 储备金率（如10%）
        uint256 borrowIndex;                        // 借款利率累积指数
        uint256 totalBorrows;                       // 总借款金额
        uint256 totalReserves;                      // 总储备金
        uint256 lastAccrualBlock;                   // 上次计息区块
        bool isListed;                              // 是否已上线
    }

    struct BorrowSnapshot {
        uint256 principal;      // 本金
        uint256 interestIndex;  // 借款时的利率指数
    }

    mapping(address => Market) public markets;
    mapping(address => mapping(address => BorrowSnapshot)) public accountBorrows;
    mapping(address => mapping(address => uint256)) public accountCollateral;

    PriceOracle public priceOracle;
    uint256 public constant CLOSE_FACTOR = 0.5e18; // 50% close factor
    uint256 public constant LIQUIDATION_INCENTIVE = 1.08e18; // 8% liquidation incentive

    address[] public allMarkets;

    event MarketListed(address indexed cToken, address indexed underlying);
    event Mint(address indexed user, uint256 mintAmount, uint256 mintTokens);
    event Redeem(address indexed user, uint256 redeemAmount, uint256 redeemTokens);
    event Borrow(address indexed user, uint256 borrowAmount);
    event RepayBorrow(address indexed user, uint256 repayAmount);
    event LiquidateBorrow(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        address indexed cTokenCollateral,
        uint256 seizeTokens
    );

    constructor(address _priceOracle) {
        priceOracle = PriceOracle(_priceOracle);
    }

    /**
     * @notice List a new market-t
     * @param underlying Underlying token address
     * @param cTokenName Name for the cToken
     * @param cTokenSymbol Symbol for the cToken
     * @param interestRateModel Interest rate model address
     * @param collateralFactor Collateral factor (scaled by 1e18)
     * @param reserveFactor Reserve factor (scaled by 1e18)
     */
    function listMarket(
        address underlying,
        string memory cTokenName,
        string memory cTokenSymbol,
        address interestRateModel,
        uint256 collateralFactor,
        uint256 reserveFactor
    ) external onlyOwner {
        require(!markets[underlying].isListed, "Market already listed");
        require(collateralFactor <= 1e18, "Invalid collateral factor");
        require(reserveFactor <= 1e18, "Invalid reserve factor");

        LendingToken cToken = new LendingToken(
            underlying,
            address(this),
            cTokenName,
            cTokenSymbol
        );

        markets[underlying] = Market({
            cToken: cToken,
            interestRateModel: InterestRateModel(interestRateModel),
            collateralFactor: collateralFactor,
            reserveFactor: reserveFactor,
            borrowIndex: 1e18,
            totalBorrows: 0,
            totalReserves: 0,
            lastAccrualBlock: block.number,
            isListed: true
        });

        allMarkets.push(underlying);

        emit MarketListed(address(cToken), underlying);
    }

    /**
     * @notice Supply tokens to the pool
     * @param underlying Underlying token address
     * @param mintAmount Amount to supply
     */
    function mint(address underlying, uint256 mintAmount) external nonReentrant {
        require(markets[underlying].isListed, "Market not listed");
        require(mintAmount > 0, "Mint amount must be greater than 0");

        accrueInterest(underlying);

        Market storage market = markets[underlying];
        IERC20 token = IERC20(underlying);

        // Transfer tokens from user
        token.transferFrom(msg.sender, address(this), mintAmount);

        // Calculate cTokens to mint
        uint256 exchangeRate = market.cToken.exchangeRateStored();
        uint256 mintTokens = (mintAmount * 1e18) / exchangeRate;

        // Mint cTokens
        market.cToken.mint(msg.sender, mintTokens);

        // Update user collateral
        accountCollateral[msg.sender][underlying] += mintTokens;

        emit Mint(msg.sender, mintAmount, mintTokens);
    }

    /**
     * @notice Redeem tokens from the pool
     * @param underlying Underlying token address
     * @param redeemTokens Amount of cTokens to redeem
     */
    function redeem(address underlying, uint256 redeemTokens) external nonReentrant {
        require(markets[underlying].isListed, "Market not listed");
        require(redeemTokens > 0, "Redeem amount must be greater than 0");

        accrueInterest(underlying);

        Market storage market = markets[underlying];

        // Check if user has enough cTokens
        require(
            accountCollateral[msg.sender][underlying] >= redeemTokens,
            "Insufficient balance"
        );

        // Calculate underlying amount to redeem
        uint256 exchangeRate = market.cToken.exchangeRateStored();
        uint256 redeemAmount = (redeemTokens * exchangeRate) / 1e18;

        // Check if redemption is allowed (sufficient collateral)
        require(redeemAllowed(msg.sender, underlying, redeemTokens), "Insufficient collateral");

        // Burn cTokens
        market.cToken.burn(msg.sender, redeemTokens);

        // Update user collateral
        accountCollateral[msg.sender][underlying] -= redeemTokens;

        // Transfer underlying tokens to user
        IERC20(underlying).transfer(msg.sender, redeemAmount);

        emit Redeem(msg.sender, redeemAmount, redeemTokens);
    }

    /**
     * @notice Borrow tokens from the pool
     * @param underlying Underlying token address
     * @param borrowAmount Amount to borrow
     */
    function borrow(address underlying, uint256 borrowAmount) external nonReentrant {
        require(markets[underlying].isListed, "Market not listed");
        require(borrowAmount > 0, "Borrow amount must be greater than 0");

        accrueInterest(underlying);

        Market storage market = markets[underlying];

        // Check if borrow is allowed
        require(borrowAllowed(msg.sender, underlying, borrowAmount), "Insufficient collateral");

        // Update borrow balance
        BorrowSnapshot storage borrowSnapshot = accountBorrows[msg.sender][underlying];

        if (borrowSnapshot.principal == 0) {
            borrowSnapshot.interestIndex = market.borrowIndex;
        }

        // Calculate current borrow balance
        uint256 currentBorrowBalance = (borrowSnapshot.principal * market.borrowIndex) /
                        borrowSnapshot.interestIndex;

        // Update borrow snapshot
        borrowSnapshot.principal = currentBorrowBalance + borrowAmount;
        borrowSnapshot.interestIndex = market.borrowIndex;

        // Update total borrows
        market.totalBorrows += borrowAmount;

        // Transfer tokens to user
        IERC20(underlying).transfer(msg.sender, borrowAmount);

        emit Borrow(msg.sender, borrowAmount);
    }

    /**
     * @notice Repay borrowed tokens
     * @param underlying Underlying token address
     * @param repayAmount Amount to repay
     */
    function repayBorrow(address underlying, uint256 repayAmount) external nonReentrant {
        require(markets[underlying].isListed, "Market not listed");

        accrueInterest(underlying);

        Market storage market = markets[underlying];
        BorrowSnapshot storage borrowSnapshot = accountBorrows[msg.sender][underlying];

        // Calculate current borrow balance
        uint256 currentBorrowBalance = (borrowSnapshot.principal * market.borrowIndex) /
                        borrowSnapshot.interestIndex;

        require(currentBorrowBalance > 0, "No borrow balance");

        // Determine actual repay amount
        uint256 actualRepayAmount = Math.min(repayAmount, currentBorrowBalance);

        // Transfer tokens from user
        IERC20(underlying).transferFrom(msg.sender, address(this), actualRepayAmount);

        // Update borrow snapshot
        borrowSnapshot.principal = currentBorrowBalance - actualRepayAmount;
        borrowSnapshot.interestIndex = market.borrowIndex;

        // Update total borrows
        market.totalBorrows -= actualRepayAmount;

        emit RepayBorrow(msg.sender, actualRepayAmount);
    }

    /**
     * @notice Liquidate an undercollateralized borrow
     * @param borrower Address of the borrower
     * @param underlying Underlying token to repay
     * @param repayAmount Amount to repay
     * @param cTokenCollateral cToken collateral to seize
     */
    function liquidateBorrow(
        address borrower,
        address underlying,
        uint256 repayAmount,
        address cTokenCollateral
    ) external nonReentrant {
        require(markets[underlying].isListed, "Market not listed");
        require(markets[cTokenCollateral].isListed, "Collateral market not listed");

        accrueInterest(underlying);
        accrueInterest(cTokenCollateral);

        // Check if liquidation is allowed
        require(liquidateAllowed(borrower), "Liquidation not allowed");

        Market storage market = markets[underlying];
        BorrowSnapshot storage borrowSnapshot = accountBorrows[borrower][underlying];

        // Calculate current borrow balance
        uint256 currentBorrowBalance = (borrowSnapshot.principal * market.borrowIndex) /
                        borrowSnapshot.interestIndex;

        require(currentBorrowBalance > 0, "No borrow balance");

        // Calculate max liquidation amount
        uint256 maxLiquidation = (currentBorrowBalance * CLOSE_FACTOR) / 1e18;
        uint256 actualRepayAmount = Math.min(repayAmount, maxLiquidation);

        // Transfer repay amount from liquidator
        IERC20(underlying).transferFrom(msg.sender, address(this), actualRepayAmount);

        // Calculate seize tokens
        uint256 seizeTokens = calculateSeizeTokens(
            underlying,
            cTokenCollateral,
            actualRepayAmount
        );

        // Update borrower's borrow balance
        borrowSnapshot.principal = currentBorrowBalance - actualRepayAmount;
        borrowSnapshot.interestIndex = market.borrowIndex;

        // Update total borrows
        market.totalBorrows -= actualRepayAmount;

        // Transfer collateral to liquidator
        markets[cTokenCollateral].cToken.transfer(msg.sender, seizeTokens);

        // Update borrower's collateral
        accountCollateral[borrower][cTokenCollateral] -= seizeTokens;

        emit LiquidateBorrow(
            msg.sender,
            borrower,
            actualRepayAmount,
            cTokenCollateral,
            seizeTokens
        );
    }

    /**
     * @notice Accrue interest for a market-t
     * @param underlying Underlying token address
     */
    function accrueInterest(address underlying) public {
        Market storage market = markets[underlying];

        uint256 currentBlock = block.number;
        uint256 accrualBlockPrior = market.lastAccrualBlock;

        if (accrualBlockPrior == currentBlock) {
            return;
        }

        uint256 cash = IERC20(underlying).balanceOf(address(this));
        uint256 borrowsPrior = market.totalBorrows;
        uint256 reservesPrior = market.totalReserves;
        uint256 borrowIndexPrior = market.borrowIndex;

        // Calculate borrow rate
        uint256 borrowRate = market.interestRateModel.getBorrowRate(
            cash,
            borrowsPrior,
            reservesPrior
        );

        // Calculate interest accumulated
        uint256 blockDelta = currentBlock - accrualBlockPrior;
        uint256 interestAccumulated = (borrowRate * blockDelta * borrowsPrior) / 1e18;
        uint256 totalBorrowsNew = borrowsPrior + interestAccumulated;
        uint256 totalReservesNew = reservesPrior +
            (interestAccumulated * market.reserveFactor) / 1e18;

        // Update borrow index
        uint256 borrowIndexNew = borrowIndexPrior +
            (borrowRate * blockDelta * borrowIndexPrior) / 1e18;

        // Update market-t state
        market.borrowIndex = borrowIndexNew;
        market.totalBorrows = totalBorrowsNew;
        market.totalReserves = totalReservesNew;
        market.lastAccrualBlock = currentBlock;
    }

    /**
     * @notice Check if redeem is allowed
     */
    function redeemAllowed(
        address user,
        address underlying,
        uint256 redeemTokens
    ) internal view returns (bool) {
        // Calculate hypothetical liquidity after redeem
        uint256 exchangeRate = markets[underlying].cToken.exchangeRateStored();
        uint256 redeemAmount = (redeemTokens * exchangeRate) / 1e18;

        return getHypotheticalLiquidity(user, underlying, redeemAmount, 0) >= 0;
    }

    /**
     * @notice Check if borrow is allowed
     */
    function borrowAllowed(
        address user,
        address underlying,
        uint256 borrowAmount
    ) internal view returns (bool) {
        if (!markets[underlying].isListed) {
            return false;
        }

        return getHypotheticalLiquidity(user, underlying, 0, borrowAmount) >= 0;
    }

    /**
     * @notice Check if liquidation is allowed
     */
    function liquidateAllowed(address borrower) internal view returns (bool) {
        return getAccountLiquidity(borrower) < 0;
    }

    /**
     * @notice Get account liquidity
     */
    function getAccountLiquidity(address user) public view returns (int256) {
        return getHypotheticalLiquidity(user, address(0), 0, 0);
    }

    /**
     * @notice Get hypothetical account liquidity
     */
    function getHypotheticalLiquidity(
        address user,
        address modifyToken,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) internal view returns (int256) {
        uint256 sumCollateral = 0;
        uint256 sumBorrow = 0;

        for (uint i = 0; i < allMarkets.length; i++) {
            address token = allMarkets[i];
            Market storage market = markets[token];

            // Calculate collateral value
            uint256 cTokenBalance = accountCollateral[user][token];
            if (token == modifyToken) {
                cTokenBalance = cTokenBalance >= redeemTokens ?
                    cTokenBalance - redeemTokens : 0;
            }

            if (cTokenBalance > 0) {
                uint256 exchangeRate = market.cToken.exchangeRateStored();
                uint256 underlyingBalance = (cTokenBalance * exchangeRate) / 1e18;
                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 collateralValue = (underlyingBalance * tokenPrice *
                    market.collateralFactor) / (1e18 * 1e18);
                sumCollateral += collateralValue;
            }

            // Calculate borrow value
            BorrowSnapshot storage borrowSnapshot = accountBorrows[user][token];
            if (borrowSnapshot.principal > 0) {
                uint256 currentBorrowBalance = (borrowSnapshot.principal * market.borrowIndex) /
                                borrowSnapshot.interestIndex;
                if (token == modifyToken) {
                    currentBorrowBalance += borrowAmount;
                }

                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 borrowValue = (currentBorrowBalance * tokenPrice) / 1e18;
                sumBorrow += borrowValue;
            }
        }

        return int256(sumCollateral) - int256(sumBorrow);
    }

    /**
     * @notice Calculate seize tokens for liquidation
     */
    function calculateSeizeTokens(
        address underlying,
        address cTokenCollateral,
        uint256 repayAmount
    ) internal view returns (uint256) {
        uint256 underlyingPrice = priceOracle.getPrice(underlying);
        uint256 collateralPrice = priceOracle.getPrice(cTokenCollateral);
        uint256 exchangeRate = markets[cTokenCollateral].cToken.exchangeRateStored();

        // seizeTokens = repayAmount * liquidationIncentive * underlyingPrice / (collateralPrice * exchangeRate)
        uint256 seizeTokens = (repayAmount * LIQUIDATION_INCENTIVE * underlyingPrice * 1e18) /
            (collateralPrice * exchangeRate);

        return seizeTokens;
    }

    /**
     * @notice Get total borrows for a market-t
     */
    function totalBorrows() external view returns (uint256) {
        // This is called by cToken to calculate exchange rate
        // Return total borrows for the calling market-t
        return 0; // Placeholder - should be implemented based on calling context
    }

    /**
     * @notice Get total reserves for a market-t
     */
    function totalReserves() external view returns (uint256) {
        // This is called by cToken to calculate exchange rate
        // Return total reserves for the calling market-t
        return 0; // Placeholder - should be implemented based on calling context
    }

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
    ) {
        require(markets[underlying].isListed, "Market not listed");

        Market storage market = markets[underlying];
        uint256 cash = IERC20(underlying).balanceOf(address(this));

        return (
            address(market.cToken),
            market.cToken.totalSupply(),
            market.totalBorrows,
            market.totalReserves,
            market.cToken.exchangeRateStored(),
            market.interestRateModel.getBorrowRate(cash, market.totalBorrows, market.totalReserves),
            market.interestRateModel.getSupplyRate(cash, market.totalBorrows, market.totalReserves, market.reserveFactor)
        );
    }

    /**
     * @notice Get user account information
     */
    function getUserAccountInfo(address user) external view returns (
        int256 liquidity,
        uint256 totalCollateralValue,
        uint256 totalBorrowValue
    ) {
        liquidity = getAccountLiquidity(user);

        uint256 sumCollateral = 0;
        uint256 sumBorrow = 0;

        for (uint i = 0; i < allMarkets.length; i++) {
            address token = allMarkets[i];
            Market storage market = markets[token];

            // Calculate collateral value
            uint256 cTokenBalance = accountCollateral[user][token];
            if (cTokenBalance > 0) {
                uint256 exchangeRate = market.cToken.exchangeRateStored();
                uint256 underlyingBalance = (cTokenBalance * exchangeRate) / 1e18;
                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 collateralValue = (underlyingBalance * tokenPrice) / 1e18;
                sumCollateral += collateralValue;
            }

            // Calculate borrow value
            BorrowSnapshot storage borrowSnapshot = accountBorrows[user][token];
            if (borrowSnapshot.principal > 0) {
                uint256 currentBorrowBalance = (borrowSnapshot.principal * market.borrowIndex) /
                                borrowSnapshot.interestIndex;
                uint256 tokenPrice = priceOracle.getPrice(token);
                uint256 borrowValue = (currentBorrowBalance * tokenPrice) / 1e18;
                sumBorrow += borrowValue;
            }
        }

        return (liquidity, sumCollateral, sumBorrow);
    }
}
