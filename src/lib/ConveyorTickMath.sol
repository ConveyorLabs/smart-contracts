// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../../lib/libraries/Uniswap/FullMath.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/SafeCast.sol";
import "../../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "../../lib/libraries/Uniswap/TickMath.sol";
import "../../lib/libraries/Uniswap/TickBitmap.sol";
import "../../lib/libraries/Uniswap/SwapMath.sol";
import "../../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/LiquidityMath.sol";
import "../../lib/libraries/Uniswap/Tick.sol";
import "../../lib/libraries/QuadruplePrecision.sol";
import "../../lib/libraries/Uniswap/SafeCast.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../test/utils/Console.sol";
import "./ConveyorMath.sol";

contract ConveyorTickMath {
    ///@notice Initialize all libraries.
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
    uint256 internal constant Q96 = 0x1000000000000000000000000;
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

    ///@notice Function to convers a SqrtPrice Q96.64 fixed point to Price as 128.128 fixed point resolution.
    ///@dev token0 is token0 on the pool, and token1 is token1 on the pool. Not tokenIn,tokenOut on the swap.
    ///@param sqrtPriceX96 The slot0 sqrtPriceX96 on the pool.
    ///@param token0IsReserve0 Bool indicating whether the tokenIn to be quoted is token0 on the pool.
    ///@param token0 Token0 in the pool.
    ///@param token1 Token1 in the pool.
    ///@return priceX128 The spot price of TokenIn as 128.128 fixed point.
    function fromSqrtX96(
        uint160 sqrtPriceX96,
        bool token0IsReserve0,
        address token0,
        address token1
    ) internal view returns (uint256 priceX128) {
        unchecked {
            ///@notice Cache the difference between the input and output token decimals. p=y/x ==> p*10**(x_decimals-y_decimals)>>Q192 will be the proper price in base 10.
            int8 decimalShift = int8(IERC20(token0).decimals()) -
                int8(IERC20(token1).decimals());
            ///@notice Square the sqrtPrice ratio and normalize the value based on decimalShift.
            uint256 priceSquaredX96 = decimalShift < 0
                ? uint256(sqrtPriceX96)**2 / uint256(10)**(uint8(-decimalShift))
                : uint256(sqrtPriceX96)**2 * 10**uint8(decimalShift);

            ///@notice The first value is a Q96 representation of p_token0, the second is 128X fixed point representation of p_token1.
            uint256 priceSquaredShiftQ96 = token0IsReserve0
                ? priceSquaredX96 / Q96
                : (Q96 * 0xffffffffffffffffffffffffffffffff) /
                    (priceSquaredX96 / Q96);

            ///@notice Convert the first value to 128X fixed point by shifting it left 128 bits and normalizing the value by Q96.
            priceX128 = token0IsReserve0
                ? (uint256(priceSquaredShiftQ96) *
                    0xffffffffffffffffffffffffffffffff) / Q96
                : priceSquaredShiftQ96;
            require(priceX128 <= type(uint256).max, "Overflow");
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

        uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtPriceX96,
            liquidity,
            amountIn,
            zeroForOne
        );

        ///@notice While the current state still has an amount to swap continue.
        while (currentState.amountSpecifiedRemaining > 0) {
            ///@notice Initialize step structure.
            StepComputations memory step;
            ///@notice Set sqrtPriceStartX96.
            step.sqrtPriceStartX96 = currentState.sqrtPriceX96;
            ///@notice Set the tickNext, and if the tick is initialized.
            (step.tickNext, step.initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    currentState.tick,
                    tickSpacing,
                    zeroForOne
                );
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }
            ///@notice Set the next sqrtPrice of the step.
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            ///@notice Perform the swap step on the current tick.
            (
                currentState.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                currentState.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                currentState.liquidity,
                currentState.amountSpecifiedRemaining,
                fee
            );
            ///@notice Decrement the remaining amount to be swapped by the amount available within the tick range.
            currentState.amountSpecifiedRemaining -= (step.amountIn +
                step.feeAmount).toInt256();
            ///@notice Increment amountCalculated by the amount recieved in the tick range.
            currentState.amountCalculated -= step.amountOut.toInt256();
            ///@notice If the swap step crossed into the next tick, and that tick is initialized.
            if (currentState.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    ///@notice Get the net liquidity after crossing the tick.
                    int128 liquidityNet = ticks.cross(step.tickNext);
                    ///@notice If swapping token0 for token1 then negate the liquidtyNet.

                    if (zeroForOne) liquidityNet = -liquidityNet;

                    currentState.liquidity = LiquidityMath.addDelta(
                        currentState.liquidity,
                        liquidityNet
                    );
                }
                ///@notice Update the currentStates tick.
                unchecked {
                    currentState.tick = zeroForOne
                        ? step.tickNext - 1
                        : step.tickNext;
                }
                ///@notice If sqrtPriceX96 in the currentState is not equal to the projected next tick, then recompute the currentStates tick.
            } else if (currentState.sqrtPriceX96 != step.sqrtPriceStartX96) {
                currentState.tick = TickMath.getTickAtSqrtRatio(
                    currentState.sqrtPriceX96
                );
            }
        }
        ///@notice Return the simulated amount out as a negative value representing the amount recieved in the swap.
        return currentState.amountCalculated;
    }

    ///@notice Helper function to determine the amount of a specified token introduced into a v3 pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev If the prices are in 64.64 fixed point form simply call from64XSpotToSqrtRatioX96 in the CFMMMath library to convert the prices into a the correct form.
    ///@param sqrtRatioAX96 The initial price of the pool.
    ///@param sqrtRatioBX96 The Quote price to determine the delta introduced to the pool on.
    ///@param liquidity The current liqudity in the pool.
    ///@return amountDelta The amount of tokenX introduced to the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev Note This is simply returning the amount of tokenX to be introduced to the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96. To calculate the amount removed use calculateDeltaRemovedOnSqrtPriceChange.
    function calculateDeltaAddedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {
        ///@notice Determine if the price is decresing or increasing.
        bool priceIncrease = sqrtRatioAX96 > sqrtRatioBX96 ? false : true;

        ///@notice Conditionally evaluate the amountDelta in the pool, depending on whether the price increased or decreased.
        if (!priceIncrease) {
            amountDelta = SqrtPriceMath.getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        } else {
            amountDelta = SqrtPriceMath.getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        }
    }

    function from128XSpotToSqrtRatioX96(
        uint256 spotBase,
        uint256 spotOutlier,
        int8 shift,
        bool token0IsReserve0
    ) internal pure returns (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) {
        bytes16 outlierSpotQuad = QuadruplePrecision.from128x128(
            int256(spotOutlier)
        );
        bytes16 baseSpotQuad = QuadruplePrecision.from128x128(int256(spotBase));
        bytes16 sqrtOutlierQuad = QuadruplePrecision.sqrt(outlierSpotQuad);
        bytes16 sqrtBaseQuad = QuadruplePrecision.sqrt(baseSpotQuad);
        uint128 sqrtBase64X;
        uint128 sqrtOutlier64X;

        if (!token0IsReserve0) {
            sqrtBase64X = ConveyorMath.div64x64(
                uint128(1) << 64,
                uint128(QuadruplePrecision.to64x64(sqrtBaseQuad))
            );
            sqrtOutlier64X = ConveyorMath.div64x64(
                uint128(1) << 64,
                uint128(QuadruplePrecision.to64x64(sqrtOutlierQuad))
            );
        } else {
            sqrtBase64X = uint128(QuadruplePrecision.to64x64(sqrtBaseQuad));
            sqrtOutlier64X = uint128(
                QuadruplePrecision.to64x64(sqrtOutlierQuad)
            );
        }

        unchecked {
            uint256 sqrtBaseShift = (uint256(sqrtBase64X) <<
                (FixedPoint96.RESOLUTION)) / (2**64);
            uint256 sqrtOutlierShift = (uint256(sqrtOutlier64X) <<
                FixedPoint96.RESOLUTION) / (2**64);
            sqrtRatioAX96 = shift < 0
                ? uint160(sqrtBaseShift) * uint160(10**(uint8(-shift)))
                : uint160(sqrtBaseShift) / uint160(10**(uint8(shift)));

            sqrtRatioBX96 = shift < 0
                ? uint160(sqrtOutlierShift) * uint160(10**(uint8(-shift)))
                : uint160(sqrtOutlierShift) / uint160(10**(uint8(shift)));
            require(sqrtRatioAX96 <= type(uint160).max, "Overflow in 128XToQ96 conversion");
            require(sqrtRatioBX96 <= type(uint160).max, "Overflow in 128XToQ96 conversion");
        }
    }

    ///@notice Helper function to determine the amount of a specified token removed from a v3 pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev If the prices are in 64.64 fixed point form simply call from64XSpotToSqrtRatioX96 in the CFMMMath library to convert the prices into a the correct form.
    ///@param sqrtRatioAX96 The initial price of the pool.
    ///@param sqrtRatioBX96 The Quote price to determine the delta introduced to the pool on.
    ///@param liquidity The current liqudity in the pool.
    ///@return amountDelta The amount of tokenX removed from the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev Note This is simply returning the amount of tokenX to be removed from the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96. To calculate the amount introduced use calculateDeltaAddedOnSqrtPriceChange.
    function calculateDeltaRemovedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {
        ///@notice Determine if the price is decresing or increasing.
        bool priceIncrease = sqrtRatioAX96 > sqrtRatioBX96 ? false : true;

        ///@notice Conditionally evaluate the amountDelta in the pool, depending on whether the price increased or decreased.
        if (!priceIncrease) {
            amountDelta = SqrtPriceMath.getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        } else {
            amountDelta = SqrtPriceMath.getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        }
    }
}
