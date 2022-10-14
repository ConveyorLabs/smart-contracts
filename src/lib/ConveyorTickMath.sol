// SPDX-License-Identifier: MIT
pragma solidity >=0.8.16;

import "../../lib/libraries/Uniswap/FullMath.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/SafeCast.sol";
import "../../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "../../lib/libraries/Uniswap/TickMath.sol";
import "../../lib/libraries/Uniswap/TickBitmap.sol";
import "../../lib/libraries/Uniswap/SwapMath.sol";
import "../../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../../lib/libraries//Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/Tick.sol";
import "../../src/test/utils/Console.sol";
import "../../lib/libraries/Uniswap/SafeCast.sol";

contract ConveyorTickMath {
    using SafeCast for uint256;
    using LowGasSafeMath for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    ///@notice Storage mapping to hold the tickBitmap for a v3 pool.
    mapping(int16 => uint256) public tickBitmap;

    ///@notice Storage mapping to map a tick to the relevant liquidity data on that tick in a pool.
    mapping(int24 => Tick.Info) public ticks;

    /// @notice maximum uint128 64.64 fixed point number
    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    ///@notice Struct holding the current simulated swap state.
    struct CurrentState {
        ///@notice Amount remaining to be swapped upon cross tick simulation.
        int256 amountSpecifiedRemaining;
        ///@notice The amount that has already been simulated over the whole swap.
        int256 amountCalculated;
        ///@notice Current price on the tick.
        uint160 sqrtPriceX96;
        ///@notice The current tick.
        int24 tick;
        ///@notice The liquidity on the current tick.
        uint128 liquidity;
    }

    ///@notice Struct holding the simulated swap state across swap steps.
    struct StepComputations {
        ///@notice The price at the beginning of the state.
        uint160 sqrtPriceStartX96;
        ///@notice The adjacent tick from the current tick in the swap simulation.
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

    function fromX96(uint160 x) internal pure returns (uint128) {
        unchecked {
            require(uint128(x >> 32) <= MAX_64x64);
            return uint128(x >> 32);
        }
    }

    ///@notice Function to simulate the change in sqrt price on a uniswap v3 swap.
    ///@param token0 Token 0 in the v3 pool.
    ///@param tokenIn Token 0 in the v3 pool.
    ///@param lpAddressAToWeth The tokenA to weth liquidity pool address.
    ///@param amountIn The amount in to simulate the price change on.
    ///@param tickSpacing The tick spacing on the pool.
    ///@param liquidity The liquidity in the pool.
    ///@param fee The swap fee in the pool.
    function simulateAmountOutOnSqrtPriceX96(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) internal returns (int256 amountOut) {
        ///@notice If token0 in the pool is tokenIn then set zeroForOne to true.
        bool zeroForOne = token0 == tokenIn ? true : false;
        int256 amount0;
        int256 amount1;
        ///@notice Grab the current price and the current tick in the pool.
        (uint160 sqrtPriceX96, int24 initialTick, , , , , ) = IUniswapV3Pool(
            lpAddressAToWeth
        ).slot0();

        ///@notice Initialize the initial simulation state
        CurrentState memory currentState = CurrentState({
            sqrtPriceX96: sqrtPriceX96,
            amountCalculated: 0,
            amountSpecifiedRemaining: int256(amountIn),
            tick: initialTick,
            liquidity: liquidity
        });

        
        ///@notice While the current state still has an amount to swap continue.
        while (currentState.amountSpecifiedRemaining > 0) {
            
            StepComputations memory step;
            step.sqrtPriceStartX96 = currentState.sqrtPriceX96;

            (step.tickNext, step.initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    currentState.tick,
                    tickSpacing,
                    zeroForOne
                );
            console.logInt(step.tickNext);
            

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            (
                currentState.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                currentState.sqrtPriceX96,
                step.sqrtPriceNextX96,
                currentState.liquidity,
                currentState.amountSpecifiedRemaining,
                uint8(fee)
            );
            
            currentState.amountSpecifiedRemaining -= (step.amountIn +
                    step.feeAmount).toInt256();
            
            currentState.amountCalculated -= step.amountOut.toInt256();

            if (currentState.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityNet = ticks.cross(step.tickNext);
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    currentState.liquidity = liquidityNet < 0
                        ? currentState.liquidity - uint128(-liquidityNet)
                        : currentState.liquidity + uint128(liquidityNet);
                }

                unchecked {
                    currentState.tick = zeroForOne
                        ? step.tickNext - 1
                        : step.tickNext;
                }
            } else if (currentState.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                currentState.tick = TickMath.getTickAtSqrtRatio(
                    currentState.sqrtPriceX96
                );
            }
        }

        unchecked {
            (amount0, amount1) = zeroForOne
                ? (int256(amountIn) - currentState.amountSpecifiedRemaining, currentState.amountCalculated)
                : (currentState.amountCalculated, int256(amountIn) - currentState.amountSpecifiedRemaining);
                console.logInt(amount0);
        console.logInt(amount1);
        }
        

        console.logInt(int256(currentState.amountSpecifiedRemaining));
        return int256(currentState.amountSpecifiedRemaining);
    }
}
