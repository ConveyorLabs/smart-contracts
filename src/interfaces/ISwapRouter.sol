// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../SwapRouter.sol";

interface ISwapRouter {
    function calculateMultiCallFeeAmount(
        address tokenIn,
        address tokenOut,
        bool buy,
        address weth,
        uint128 amountIn,
        uint128 amountOut,
        address usdc
    ) external view returns (uint128 minOrderFee);

    function _calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) external view returns (SpotReserve memory spRes, address poolAddress);

    function _calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) external view returns (uint128);
}