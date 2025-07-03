// SPDX-License-Identifier: UNLICENSED
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./LendingManager.sol";

/**
 * @title LendingToken (cToken equivalent)
 * @notice ERC20 token representing shares in the lending pool
 */
contract LendingToken is ERC20, Ownable {
    using Math for uint256;

    IERC20 public immutable underlying;
    LendingManager public immutable pool;

    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18; // 1:1 initially

    constructor(
        address _underlying,
        address _pool,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        underlying = IERC20(_underlying);
        pool = LendingManager(_pool);
    }

    /**
     * @notice Calculate current exchange rate from cTokens to underlying
     * @return Exchange rate scaled by 1e18
     */
    function exchangeRateStored() public view returns (uint256) {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            return INITIAL_EXCHANGE_RATE;
        }

        uint256 cash = underlying.balanceOf(address(pool));
        uint256 totalBorrows = pool.totalBorrows();
        uint256 totalReserves = pool.totalReserves();

        // Exchange rate = (cash + totalBorrows - totalReserves) / totalSupply
        return ((cash + totalBorrows - totalReserves) * 1e18) / totalSupply_;
    }

    /**
     * @notice Mint cTokens to user
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn cTokens from user
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
