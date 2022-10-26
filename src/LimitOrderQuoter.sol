// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./SwapRouter.sol";
import "./lib/ConveyorTickMath.sol";

contract LimitOrderQuoter is ConveyorTickMath {
    address immutable WETH;

    constructor(address _weth, address _quoterAddress) {
        require(_weth != address(0), "Invalid weth address");
        WETH = _weth;
    }

    ///@notice Helper function to determine if a pool address is Uni V2 compatible.
    ///@param lp - Pair address.
    ///@return bool Idicator whether the pool is not Uni V3 compatible.
    function _lpIsNotUniV3(address lp) internal returns (bool) {
        bool success;
        assembly {
            //store the function sig for  "fee()"
            mstore(
                0x00,
                0xddca3f4300000000000000000000000000000000000000000000000000000000
            )

            success := call(
                gas(), // gas remaining
                lp, // destination address
                0, // no ether
                0x00, // input buffer (starts after the first 32 bytes in the `data` array)
                0x04, // input length (loaded from the first 32 bytes in the `data` array)
                0x00, // output buffer
                0x00 // output length
            )
        }
        ///@notice return the opposite of success, meaning if the call succeeded, the address is univ3, and we should
        ///@notice indicate that lpIsNotUniV3 is false
        return !success;
    }

    ///@notice Function to retrieve the buy/sell status of a single order.
    ///@param order Order to determine buy/sell status on.
    ///@return bool Boolean indicating the buy/sell status of the order.
    function _buyOrSell(OrderBook.Order memory order)
        internal
        pure
        returns (bool)
    {
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice Function to determine if an order meets the execution price.
    ///@param orderPrice The Spot price for execution of the order.
    ///@param executionPrice The current execution price of the best prices lp.
    ///@param buyOrder The buy/sell status of the order.
    function _orderMeetsExecutionPrice(
        uint256 orderPrice,
        uint256 executionPrice,
        bool buyOrder
    ) internal pure returns (bool) {
        if (buyOrder) {
            return executionPrice <= orderPrice;
        } else {
            return executionPrice >= orderPrice;
        }
    }

    ///@notice Checks if order can complete without hitting slippage
    ///@param spot_price The spot price of the liquidity pool.
    ///@param order_quantity The input quantity of the order.
    ///@param amountOutMin The slippage set by the order owner.
    function _orderCanExecute(
        uint256 spot_price,
        uint256 order_quantity,
        uint256 amountOutMin
    ) internal pure returns (bool) {
        return ConveyorMath.mul128I(spot_price, order_quantity) >= amountOutMin;
    }

    ///@notice Function to get the amountOut from a UniV2 lp.
    ///@param amountIn - AmountIn for the swap.
    ///@param reserveIn - tokenIn reserve for the swap.
    ///@param reserveOut - tokenOut reserve for the swap.
    ///@return amountOut - AmountOut from the given parameters.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert InsufficientInputAmount();
        }

        if (reserveIn == 0) {
            revert InsufficientLiquidity();
        }

        if (reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    ///@notice Helper to calculate the multiplicative spot price over both router hops
    ///@param spotPriceAToWeth spotPrice of Token A relative to Weth
    ///@param spotPriceWethToB spotPrice of Weth relative to Token B
    ///@return spotPriceFinal multiplicative finalSpot
    function _calculateTokenToWethToTokenSpotPrice(
        uint256 spotPriceAToWeth,
        uint256 spotPriceWethToB
    ) internal pure returns (uint128 spotPriceFinal) {
        spotPriceFinal = ConveyorMath.mul64x64(
            uint128(spotPriceAToWeth >> 64),
            uint128(spotPriceWethToB >> 64)
        );
    }

    ///@notice Helper function to calculate amountOutMin value agnostically across dexes on the first hop from tokenA to WETH.
    ///@param lpAddressAToWeth - The liquidity pool for tokenA to Weth.
    ///@param amountInOrder - The amount in on the swap.
    ///@param taxIn - The tax on the input token for the swap.
    ///@param feeIn - The fee on the swap.
    ///@param tokenIn - The address of tokenIn on the swap.
    ///@return amountOutMinAToWeth - The amountOutMin in the swap.
    function calculateAmountOutMinAToWethV2(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        uint16 taxIn,
        uint24 feeIn,
        address tokenIn
    ) external returns (uint256 amountOutMinAToWeth) {
        ///@notice Otherwise if the lp is a UniV2 LP.

        ///@notice Get the reserves from the pool.
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(
            lpAddressAToWeth
        ).getReserves();

        ///@notice Initialize the reserve0 and reserve1 depending on if Weth is token0 or token1.
        if (WETH == IUniswapV2Pair(lpAddressAToWeth).token0()) {
            uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;

            uint256 amountIn = amountInOrder - amountInBuffer;
            amountOutMinAToWeth = getAmountOut(
                amountIn,
                uint256(reserve1),
                uint256(reserve0)
            );
        } else {
            uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;

            uint256 amountIn = amountInOrder - amountInBuffer;
            amountOutMinAToWeth = getAmountOut(
                amountIn,
                uint256(reserve0),
                uint256(reserve1)
            );
        }
    }
}
