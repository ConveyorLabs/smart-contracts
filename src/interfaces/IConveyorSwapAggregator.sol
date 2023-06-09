// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import "../ConveyorSwapAggregator.sol";

interface IConveyorSwapAggregator {
    function swapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall
    ) external payable;

    function swapExactTokenForTokenWithReferral(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        ConveyorSwapAggregator.ReferralInfo calldata referralInfo
    ) external payable;

    function swapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall
    ) external payable;

    function swapExactEthForTokenWithReferral(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        ConveyorSwapAggregator.ReferralInfo calldata referralInfo
    ) external payable;

    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall
    ) external payable;

    function swapExactTokenForEthWithReferral(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        ConveyorSwapAggregator.ReferralInfo calldata referralInfo
    ) external payable;

    function CONVEYOR_SWAP_EXECUTOR() external view returns (address);
}
