// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";

interface IConveyorSwapExecutor {
    function executeMulticall(ConveyorSwapAggregator.Call[] memory calls)
        external;
}

/// @title LimitOrderSwapRouter
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Dex aggregator that executes standalone swaps, and fulfills limit orders during execution.
contract ConveyorSwapAggregator {
    address public immutable CONVEYOR_SWAP_EXECUTOR;

    constructor() {
        CONVEYOR_SWAP_EXECUTOR = address(new ConveyorSwapExecutor());
    }

    struct SwapAggregatorMulticall {
        address tokenInDestination;
        Call[] calls;
    }

    struct Call {
        address target;
        bytes callData;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external {
        IERC20(tokenIn).transferFrom(
            msg.sender,
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );

        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(msg.sender);
        uint256 tokenOutAmountRequired = tokenOutBalance + amountOutMin;

        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall.calls
        );

        if (IERC20(tokenOut).balanceOf(msg.sender) < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - IERC20(tokenOut).balanceOf(msg.sender),
                amountOutMin
            );
        }
    }
}

contract ConveyorSwapExecutor {
    function executeMulticall(ConveyorSwapAggregator.Call[] calldata calls)
        public
    {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; ) {
            ConveyorSwapAggregator.Call memory call = calls[i];

            (bool success, ) = call.target.call(call.callData);

            require(success, "call failed");

            unchecked {
                ++i;
            }
        }
    }

    ///@notice Uniswap V3 callback function called during a swap on a v3 liqudity pool.
    ///@param amount0Delta - The change in token0 reserves from the swap.
    ///@param amount1Delta - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address tokenIn, address _sender) = abi.decode(
            data,
            (bool, address, address)
        );

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(tokenIn).transfer(msg.sender, amountIn);
        }
    }
}