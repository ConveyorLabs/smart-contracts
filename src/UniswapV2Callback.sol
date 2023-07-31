// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../test/utils/Console.sol";

contract UniswapV2Callback {
    /// @notice Uniswap v2 swap callback
    /// @param amount0 - The change in token0 reserves from the swap.
    /// @param amount1 - The change in token1 reserves from the swap.
    /// @param data - The data packed into the swap.
    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address _tokenIn, uint8 _swapFee) = abi.decode(data, (bool, address, uint8));

        uint256 amountOut = _zeroForOne ? amount1 : amount0;
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(msg.sender).getReserves();

        uint256 amountIn =
            getAmountIn(amountOut, _zeroForOne ? reserve0 : reserve1, _zeroForOne ? reserve1 : reserve0, _swapFee);

        IERC20(_tokenIn).transfer(msg.sender, amountIn);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint8 swapFee)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 100000;
        uint256 denominator = (reserveOut - amountOut) * (100000 - swapFee);
        amountIn = (numerator / denominator) + 1;
    }
}