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
    function uniswapV2Call(
        address,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address _tokenIn, address _sender) = abi.decode(
            data,
            (bool, address, address)
        );

        uint256 amountOut = _zeroForOne ? amount1 : amount0;
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(msg.sender)
            .getReserves();

        uint256 amountIn = getAmountIn(
            amountOut,
            _zeroForOne ? reserve0 : reserve1,
            _zeroForOne ? reserve1 : reserve0
        );

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(_tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(_tokenIn).transfer(msg.sender, amountIn);
        }
    }

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
}
