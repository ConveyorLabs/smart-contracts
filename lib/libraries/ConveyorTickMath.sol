// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import "./Uniswap/FullMath.sol";
import "./Uniswap/LowGasSafeMath.sol";
import "./Uniswap/SafeCast.sol";
import "./Uniswap/SqrtPriceMath.sol";
import "./Uniswap/TickMath.sol";
import "./Uniswap/TickBitmap.sol";
import "./Uniswap/SwapMath.sol";
import "../interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "./Uniswap/LowGasSafeMath.sol";
import "./Uniswap/Tick.sol";
import "../../src/test/utils/Console.sol";
contract ConveyorTickMath {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    mapping(int16 => uint256) public tickBitmap;
    mapping(int24 => Tick.Info) public ticks;

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct CurrentState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        uint256 feeAmount;
    }

    /// @notice maximum uint128 64.64 fixed point number
    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    function fromX96(uint160 x) internal pure returns (uint128) {
        unchecked {
            require(uint128(x >> 32) <= MAX_64x64);
            return uint128(x >> 32);
        }
    }

    function simulateAmountOutWethOnSqrtPriceX96(
        address token0,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) internal returns (int256 amountOut) {
        Tick.Info memory tickInfo;

        bool zeroForOne = token0 !=
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
            ? true
            : false;

        (
            uint160 sqrtPriceX96,
            int24 initialTick,
            ,
            ,
            ,
            ,

        ) = IUniswapV3Pool(lpAddressAToWeth).slot0();

        ///@notice Initialize the initial simulation state
        CurrentState memory currentState = CurrentState({
            sqrtPriceX96: sqrtPriceX96,
            amountCalculated: 0,
            amountSpecifiedRemaining: int256(amountIn),
            tick: initialTick,
            liquidity: liquidity
        });

        uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(sqrtPriceX96, liquidity, amountIn, zeroForOne);

        ///@notice While the current state still has an amount to swap continue.
        while (currentState.amountSpecifiedRemaining != 0) {
            
            StepComputations memory step;

            step.sqrtPriceStartX96 = currentState.sqrtPriceX96;

            (step.tickNext, step.initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    currentState.tick,
                    tickSpacing,
                    zeroForOne
                );
            console.logInt(step.tickNext);
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            
            (
                currentState.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                currentState.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                currentState.liquidity,
                currentState.amountSpecifiedRemaining,
                uint8(fee)
            );

            currentState.amountSpecifiedRemaining -= int256(
                step.amountIn + step.feeAmount
            );
            currentState.amountCalculated = currentState.amountCalculated.sub(
                int256(step.amountOut)
            );

            if (currentState.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityNet = ticks.cross(step.tickNext);

                    
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    currentState.liquidity = LiquidityMath.addDelta(currentState.liquidity, liquidityNet);
                }
                currentState.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            }else if (currentState.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                currentState.tick = TickMath.getTickAtSqrtRatio(currentState.sqrtPriceX96);

            }
        }
        return int256(currentState.amountCalculated);
    }
}
