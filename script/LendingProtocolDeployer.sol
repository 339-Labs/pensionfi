// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./LendingProtocol.sol";

/**
 * @title LendingProtocolDeployer
 * @notice 部署和配置借贷协议的合约
 */
contract LendingProtocolDeployer {
    address public priceOracle;
    address public interestRateModel;
    address public lendingPool;
    address public wethMarket;
    address public ethStrategyIntegration;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH

    event ContractsDeployed(
        address priceOracle,
        address interestRateModel,
        address lendingPool,
        address wethMarket,
        address ethStrategyIntegration
    );

    /**
     * @notice 部署所有合约
     * @param _ethStrategy ETHStrategy 合约地址
     * @param _initialWethPrice WETH 初始价格 (USD, scaled by 1e18)
     */
    function deployContracts(
        address _ethStrategy,
        uint256 _initialWethPrice
    ) external {
        require(_ethStrategy != address(0), "Invalid ETHStrategy address");
        require(_initialWethPrice > 0, "Invalid WETH price");

        // 1. 部署价格预言机
        priceOracle = address(new PriceOracle());
        PriceOracle(priceOracle).setPrice(WETH, _initialWethPrice);

        // 2. 部署利率模型
        interestRateModel = address(new InterestRateModel());

        // 3. 部署借贷池
        lendingPool = address(new LendingPool(priceOracle));

        // 4. 在借贷池中列出 WETH 市场
        LendingPool(lendingPool).listMarket(
            WETH,                           // underlying token
            "Compound WETH",                // cToken name
            "cWETH",                        // cToken symbol
            interestRateModel,              // interest rate model
            0.75e18,                        // 75% collateral factor
            0.1e18                          // 10% reserve factor
        );

        // 5. 获取 WETH 市场的 cToken 地址
        (address cToken,,,,,,,) = LendingPool(lendingPool).getMarketInfo(WETH);
        wethMarket = cToken;

        // 6. 部署 ETHStrategy 集成合约
        ethStrategyIntegration = address(new ETHStrategyIntegration(
            lendingPool,
            _ethStrategy,
            WETH
        ));

        emit ContractsDeployed(
            priceOracle,
            interestRateModel,
            lendingPool,
            wethMarket,
            ethStrategyIntegration
        );
    }

    /**
     * @notice 配置额外的市场（如 USDC, USDT 等）
     * @param _token 代币地址
     * @param _name cToken 名称
     * @param _symbol cToken 符号
     * @param _price 代币价格
     * @param _collateralFactor 抵押因子
     * @param _reserveFactor 储备因子
     */
    function addMarket(
        address _token,
        string memory _name,
        string memory _symbol,
        uint256 _price,
        uint256 _collateralFactor,
        uint256 _reserveFactor
    ) external {
        require(lendingPool != address(0), "LendingPool not deployed");
        require(_token != address(0), "Invalid token address");

        // 设置价格
        PriceOracle(priceOracle).setPrice(_token, _price);

        // 列出市场
        LendingPool(lendingPool).listMarket(
            _token,
            _name,
            _symbol,
            interestRateModel,
            _collateralFactor,
            _reserveFactor
        );
    }

    /**
     * @notice 更新代币价格
     * @param _token 代币地址
     * @param _price 新价格
     */
    function updatePrice(address _token, uint256 _price) external {
        require(priceOracle != address(0), "PriceOracle not deployed");
        PriceOracle(priceOracle).setPrice(_token, _price);
    }

    /**
     * @notice 获取部署的合约地址
     */
    function getDeployedContracts() external view returns (
        address _priceOracle,
        address _interestRateModel,
        address _lendingPool,
        address _wethMarket,
        address _ethStrategyIntegration
    ) {
        return (
            priceOracle,
            interestRateModel,
            lendingPool,
            wethMarket,
            ethStrategyIntegration
        );
    }
}

/**
 * @title ETHStrategyExample
 * @notice 示例 ETHStrategy 合约，展示如何与借贷协议集成
 */
contract ETHStrategyExample {
    ETHStrategyIntegration public immutable lendingIntegration;

    mapping(address => uint256) public userDeposits;
    uint256 public totalETHDeposited;
    uint256 public totalETHInLending;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event LendingDeposit(uint256 amount);
    event LendingWithdrawal(uint256 amount);
    event InterestClaimed(uint256 amount);

    constructor(address _lendingIntegration) {
        lendingIntegration = ETHStrategyIntegration(_lendingIntegration);
    }

    /**
     * @notice 用户存入 ETH
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");

        userDeposits[msg.sender] += msg.value;
        totalETHDeposited += msg.value;

        emit Deposit(msg.sender, msg.value);

        // 自动将一部分资金存入借贷协议
        uint256 lendingAmount = msg.value * 70 / 100; // 70% 存入借贷
        if (lendingAmount > 0) {
            _depositToLending(lendingAmount);
        }
    }

    /**
     * @notice 用户提取 ETH
     * @param amount 提取数量
     */
    function withdraw(uint256 amount) external {
        require(userDeposits[msg.sender] >= amount, "Insufficient balance");
        require(address(this).balance >= amount, "Insufficient contract balance");

        userDeposits[msg.sender] -= amount;
        totalETHDeposited -= amount;

        // 如果合约余额不足，从借贷协议提取
        if (address(this).balance < amount) {
            _withdrawFromLending(amount - address(this).balance);
        }

        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice 将资金存入借贷协议
     * @param amount 存入数量
     */
    function _depositToLending(uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient balance");

        // 转账给集成合约
        payable(address(lendingIntegration)).transfer(amount);

        // 调用存入函数
        lendingIntegration.depositToLending(amount);

        totalETHInLending += amount;
        emit LendingDeposit(amount);
    }

    /**
     * @notice 从借贷协议提取资金
     * @param amount 提取数量
     */
    function _withdrawFromLending(uint256 amount) internal {
        // 计算需要赎回的 cToken 数量
        (,uint256 currentValue,) = lendingIntegration.getUserPosition(address(this));

        if (currentValue == 0) return;

        // 简化计算，实际应该更精确
        uint256 cTokenAmount = (amount * totalETHInLending) / currentValue;

        lendingIntegration.withdrawFromLending(cTokenAmount);

        totalETHInLending -= amount;
        emit LendingWithdrawal(amount);
    }

    /**
     * @notice 管理员函数：收集利息
     */
    function claimInterest() external {
        uint256 interest = lendingIntegration.getEarnedInterest(address(this));

        if (interest > 0) {
            lendingIntegration.claimInterest();
            emit InterestClaimed(interest);
        }
    }

    /**
     * @notice 获取策略总价值
     */
    function getTotalValue() external view returns (uint256) {
        uint256 contractBalance = address(this).balance;
        uint256 lendingValue = lendingIntegration.getTotalValueLocked();

        return contractBalance + lendingValue;
    }

    /**
     * @notice 获取用户在借贷协议中的收益
     */
    function getUserLendingReward(address user) external view returns (uint256) {
        if (totalETHDeposited == 0) return 0;

        uint256 userProportion = (userDeposits[user] * 1e18) / totalETHDeposited;
        uint256 totalInterest = lendingIntegration.getEarnedInterest(address(this));

        return (totalInterest * userProportion) / 1e18;
    }

    /**
     * @notice 获取策略统计信息
     */
    function getStrategyStats() external view returns (
        uint256 totalDeposited,
        uint256 totalInLending,
        uint256 totalEarned,
        uint256 contractBalance,
        uint256 totalValue
    ) {
        totalDeposited = totalETHDeposited;
        totalInLending = totalETHInLending;
        totalEarned = lendingIntegration.getEarnedInterest(address(this));
        contractBalance = address(this).balance;
        totalValue = contractBalance + lendingIntegration.getTotalValueLocked();
    }

    receive() external payable {}
}
