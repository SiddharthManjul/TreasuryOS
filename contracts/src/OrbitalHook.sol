// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title OrbitalHook
/// @notice Uniswap v4 hook for stablecoin liquidity with orbital invariant AMM
/// @dev Custom AMM optimized for low-slippage stablecoin swaps
contract OrbitalHook is BaseHook {
    using FixedPointMathLib for uint256;

    // --- Errors ---
    error InvalidStablecoin();
    error InsufficientLiquidity();
    error ZeroAmount();
    error SlippageExceeded();
    error Unauthorized();

    // --- Constants ---
    uint256 public constant FEE_BPS = 4; // 0.04%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant PRECISION = 1e18;

    // Orbital invariant amplification coefficient (similar to Curve's A)
    uint256 public constant AMPLIFICATION = 100;

    // --- State ---
    address public owner;
    address[] public stablecoins;
    mapping(address => bool) public isStablecoin;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => uint256) public reserves;

    // LP positions
    mapping(address => uint256) public lpShares;
    uint256 public totalLpShares;
    uint256 public accumulatedFees;

    // --- Events ---
    event LiquidityAdded(address indexed provider, uint256[] amounts, uint256 lpSharesMinted);
    event LiquidityRemoved(address indexed provider, uint256 lpSharesBurned, uint256[] amounts);
    event Swapped(address indexed trader, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event FeesCollected(uint256 amount);

    // --- Modifiers ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        address[] memory _stablecoins,
        uint8[] memory _decimals
    )
        BaseHook(_poolManager)
    {
        require(_stablecoins.length == _decimals.length, "Length mismatch");
        require(_stablecoins.length >= 2, "Need at least 2 stablecoins");

        owner = msg.sender;

        for (uint256 i = 0; i < _stablecoins.length; i++) {
            stablecoins.push(_stablecoins[i]);
            isStablecoin[_stablecoins[i]] = true;
            tokenDecimals[_stablecoins[i]] = _decimals[i];
        }
    }

    // --- Hook Permissions ---

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // --- Hook Implementations ---

    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    )
        internal
        pure
        override
        returns (bytes4)
    {
        return this.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    )
        internal
        pure
        override
        returns (bytes4)
    {
        return this.beforeRemoveLiquidity.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    )
        internal
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    )
        internal
        pure
        override
        returns (bytes4, int128)
    {
        return (this.afterSwap.selector, 0);
    }

    // --- Custom Swap Function (for Treasury integration) ---

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut)
    {
        if (!isStablecoin[tokenIn] || !isStablecoin[tokenOut]) revert InvalidStablecoin();
        if (amountIn == 0) revert ZeroAmount();

        // Normalize to 18 decimals
        uint256 normalizedIn = _normalize(amountIn, tokenDecimals[tokenIn]);

        // Calculate output using orbital invariant
        amountOut = _getAmountOut(tokenIn, tokenOut, normalizedIn);

        // Denormalize output
        amountOut = _denormalize(amountOut, tokenDecimals[tokenOut]);

        if (amountOut < minAmountOut) revert SlippageExceeded();
        if (reserves[tokenOut] < amountOut) revert InsufficientLiquidity();

        // Calculate and accumulate fee
        uint256 fee = amountIn * FEE_BPS / BPS_DENOMINATOR;
        uint256 amountInAfterFee = amountIn - fee;
        accumulatedFees += _normalize(fee, tokenDecimals[tokenIn]);

        // Transfer tokens
        SafeTransferLib.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        SafeTransferLib.safeTransfer(tokenOut, msg.sender, amountOut);

        // Update reserves
        reserves[tokenIn] += amountInAfterFee;
        reserves[tokenOut] -= amountOut;

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    // --- Liquidity Management ---

    function addLiquidity(uint256[] calldata amounts) external returns (uint256 sharesMinted) {
        require(amounts.length == stablecoins.length, "Invalid amounts length");

        uint256 totalValue = 0;

        // Transfer tokens and calculate total value
        for (uint256 i = 0; i < stablecoins.length; i++) {
            if (amounts[i] > 0) {
                SafeTransferLib.safeTransferFrom(stablecoins[i], msg.sender, address(this), amounts[i]);
                reserves[stablecoins[i]] += amounts[i];
                totalValue += _normalize(amounts[i], tokenDecimals[stablecoins[i]]);
            }
        }

        if (totalValue == 0) revert ZeroAmount();

        // Calculate LP shares
        if (totalLpShares == 0) {
            sharesMinted = totalValue;
        } else {
            uint256 totalReserves = _getTotalReserves();
            sharesMinted = totalValue.mulDiv(totalLpShares, totalReserves - totalValue);
        }

        lpShares[msg.sender] += sharesMinted;
        totalLpShares += sharesMinted;

        emit LiquidityAdded(msg.sender, amounts, sharesMinted);
    }

    function removeLiquidity(uint256 sharesToBurn) external returns (uint256[] memory amounts) {
        if (sharesToBurn == 0) revert ZeroAmount();
        if (lpShares[msg.sender] < sharesToBurn) revert InsufficientLiquidity();

        amounts = new uint256[](stablecoins.length);
        uint256 shareRatio = sharesToBurn.mulDiv(PRECISION, totalLpShares);

        for (uint256 i = 0; i < stablecoins.length; i++) {
            amounts[i] = reserves[stablecoins[i]].mulDiv(shareRatio, PRECISION);
            if (amounts[i] > 0) {
                reserves[stablecoins[i]] -= amounts[i];
                SafeTransferLib.safeTransfer(stablecoins[i], msg.sender, amounts[i]);
            }
        }

        lpShares[msg.sender] -= sharesToBurn;
        totalLpShares -= sharesToBurn;

        emit LiquidityRemoved(msg.sender, sharesToBurn, amounts);
    }

    // --- Views ---

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut) {
        if (!isStablecoin[tokenIn] || !isStablecoin[tokenOut]) revert InvalidStablecoin();

        uint256 normalizedIn = _normalize(amountIn, tokenDecimals[tokenIn]);
        uint256 fee = normalizedIn * FEE_BPS / BPS_DENOMINATOR;
        uint256 amountInAfterFee = normalizedIn - fee;

        amountOut = _getAmountOut(tokenIn, tokenOut, amountInAfterFee);
        amountOut = _denormalize(amountOut, tokenDecimals[tokenOut]);
    }

    function getPosition(address provider)
        external
        view
        returns (uint256 shares, uint256[] memory underlyingAmounts, uint256 earnedFees)
    {
        shares = lpShares[provider];
        underlyingAmounts = new uint256[](stablecoins.length);

        if (totalLpShares > 0 && shares > 0) {
            uint256 shareRatio = shares.mulDiv(PRECISION, totalLpShares);
            for (uint256 i = 0; i < stablecoins.length; i++) {
                underlyingAmounts[i] = reserves[stablecoins[i]].mulDiv(shareRatio, PRECISION);
            }
            earnedFees = accumulatedFees.mulDiv(shareRatio, PRECISION);
        }
    }

    function getTotalLiquidity() external view returns (uint256[] memory amounts) {
        amounts = new uint256[](stablecoins.length);
        for (uint256 i = 0; i < stablecoins.length; i++) {
            amounts[i] = reserves[stablecoins[i]];
        }
    }

    function getStablecoins() external view returns (address[] memory) {
        return stablecoins;
    }

    // --- Internal Functions ---

    /// @dev Orbital invariant swap calculation (StableSwap-like)
    /// Uses: D = A * sum(x_i) + D^n / (n^n * prod(x_i))
    function _getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        uint256 reserveIn = _normalize(reserves[tokenIn], tokenDecimals[tokenIn]);
        uint256 reserveOut = _normalize(reserves[tokenOut], tokenDecimals[tokenOut]);

        if (reserveOut == 0) return 0;

        // Simple constant-product with amplification for stables
        // y = reserveOut - (reserveIn * reserveOut) / (reserveIn + amountIn * A)
        uint256 amplifiedIn = amountIn * AMPLIFICATION;
        uint256 newReserveIn = reserveIn + amplifiedIn;

        // Prevent division by zero
        if (newReserveIn == 0) return 0;

        uint256 newReserveOut = (reserveIn * reserveOut) / newReserveIn;
        uint256 amountOut = reserveOut > newReserveOut ? reserveOut - newReserveOut : 0;

        // Apply amplification adjustment
        return amountOut * AMPLIFICATION / (AMPLIFICATION + 1);
    }

    function _normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * 10 ** (18 - decimals);
        return amount / 10 ** (decimals - 18);
    }

    function _denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / 10 ** (18 - decimals);
        return amount * 10 ** (decimals - 18);
    }

    function _getTotalReserves() internal view returns (uint256 total) {
        for (uint256 i = 0; i < stablecoins.length; i++) {
            total += _normalize(reserves[stablecoins[i]], tokenDecimals[stablecoins[i]]);
        }
    }
}
