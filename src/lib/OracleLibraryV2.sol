// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

library OracleLibraryV2 {
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint24 swapFee)
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
