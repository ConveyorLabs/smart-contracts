// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";

interface IConveyorSwapExecutor {
    function executeMulticall(ConveyorSwapAggregator.Call[] memory calls)
        external;
}

/// @title ConveyorSwapAggregator
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Multicall contract for token Swaps.
contract ConveyorSwapAggregator {
    address public immutable CONVEYOR_SWAP_EXECUTOR;
    address public immutable WETH;

    constructor(address _weth) {
        WETH = _weth;
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

    function swapExactEthForToken(
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external payable {
        (bool success, ) = address(WETH).call{value: msg.value}(
            abi.encodeWithSignature("deposit()")
        );

        require(success, "WETH deposit failed");

        IERC20(WETH).transfer(
            swapAggregatorMulticall.tokenInDestination,
            msg.value
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

    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external {
        IERC20(tokenIn).transferFrom(
            msg.sender,
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );

        uint256 ethBalance = address(this).balance;
        uint256 ethAmountRequired = ethBalance + amountOutMin;

        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall.calls
        );

        if (address(this).balance < ethAmountRequired) {
            revert InsufficientOutputAmount(
                ethAmountRequired - address(this).balance,
                amountOutMin
            );
        }

        (bool success, ) = address(WETH).call{value: address(this).balance}(
            abi.encodeWithSignature("withdraw(uint256)", address(this).balance)
        );

        require(success, "WETH withdraw failed");

        payable(msg.sender).transfer(address(this).balance);
        
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
        bytes calldata data
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
