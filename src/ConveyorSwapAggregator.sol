// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";

interface IConveyorSwapExecutor {
    function executeMulticall(
        ConveyorSwapAggregator.Call[] memory calls
    ) external;
}

/// @title ConveyorSwapAggregator
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Multicall contract for token Swaps.
contract ConveyorSwapAggregator {
    address public immutable CONVEYOR_SWAP_EXECUTOR;
    address public immutable WETH;

    constructor(address _weth, address _conveyorSwapExecutor) {
        WETH = _weth;
        CONVEYOR_SWAP_EXECUTOR = _conveyorSwapExecutor;
    }

    /// @notice Multicall struct for token Swaps.
    /// @param tokenInDestination Address to send tokenIn to.
    /// @param calls Array of calls to be executed.
    struct SwapAggregatorMulticall {
        uint64 zeroForOneBitMap;
        uint64 isUniV2BitMap;
        uint128 toAddressBitMap;
        address tokenInDestination;
        Call[] calls;
    }
    /// @notice Call struct for token Swaps.
    /// @param target Address to call.
    /// @param callData Data to call.
    struct Call {
        address target;
        bytes callData;
        bool isUniV2;
    }

    /// @notice Swap tokens for tokens.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external {
        ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
        IERC20(tokenIn).transferFrom(
            msg.sender,
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );

        ///@notice Get tokenOut balance of msg.sender.
        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(msg.sender);
        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = tokenOutBalance + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall.calls
        );
        ///@notice Check if tokenOut balance of msg.sender is sufficient.
        if (IERC20(tokenOut).balanceOf(msg.sender) < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - IERC20(tokenOut).balanceOf(msg.sender),
                amountOutMin
            );
        }
    }

    /// @notice Swap ETH for tokens.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactEthForToken(
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external payable {
        ///@notice Deposit the msg.value into WETH.
        _depositEth(msg.value, WETH);

        ///@notice Transfer WETH from WETH to tokenInDestination address.
        IERC20(WETH).transfer(
            swapAggregatorMulticall.tokenInDestination,
            msg.value
        );

        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = IERC20(tokenOut).balanceOf(
            msg.sender
        ) + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall.calls
        );

        ///@notice Get tokenOut balance of msg.sender after multicall execution.
        uint256 balanceOut = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Revert if tokenOut balance of msg.sender is insufficient.
        if (balanceOut < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - balanceOut,
                amountOutMin
            );
        }
    }

    /// @notice Swap tokens for ETH.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param amountOutMin Minimum amount of ETH to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external {
        ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
        IERC20(tokenIn).transferFrom(
            msg.sender,
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );
        ///@notice Calculate amountOutRequired.
        uint256 amountOutRequired = msg.sender.balance + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall.calls
        );

        ///@notice Get WETH balance of this contract.
        uint256 balanceWeth = IERC20(WETH).balanceOf(address(this));

        ///@notice Withdraw WETH from this contract.
        _withdrawEth(balanceWeth, WETH);

        ///@notice Transfer ETH to msg.sender.
        _safeTransferETH(msg.sender, address(this).balance);

        ///@notice Revert if Eth balance of the caller is insufficient.
        if (msg.sender.balance < amountOutRequired) {
            revert InsufficientOutputAmount(
                amountOutRequired - msg.sender.balance,
                amountOutMin
            );
        }
    }

    ///@notice Helper function to transfer ETH.
    function _safeTransferETH(address to, uint256 amount) internal {
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert ETHTransferFailed();
        }
    }

    /// @notice Helper function to Withdraw ETH from WETH.
    function _withdrawEth(uint256 amount, address weth) internal {
        assembly {
            mstore(
                0x0,
                shl(224, 0x2e1a7d4d)
            ) /* keccak256("withdraw(uint256)") */
            mstore(4, amount)
            if iszero(
                call(
                    gas() /* gas */,
                    weth /* to */,
                    0 /* value */,
                    0 /* in */,
                    68 /* in size */,
                    0 /* out */,
                    0 /* out size */
                )
            ) {
                revert("Native Token Withdraw failed", amount)
            }
        }
    }

    /// @notice Helper function to Deposit ETH into WETH.
    function _depositEth(uint256 amount, address weth) internal {
        assembly {
            mstore(0x0, shl(224, 0xd0e30db0)) /* keccak256("deposit()") */
            if iszero(
                call(
                    gas() /* gas */,
                    weth /* to */,
                    amount /* value */,
                    0 /* in */,
                    0 /* in size */,
                    0 /* out */,
                    0 /* out size */
                )
            ) {
                revert("Native token deposit failed", 0)
            }
        }
    }

    receive() external payable {}
}

contract ConveyorSwapExecutor {
    ///@notice Executes a multicall.
    function executeMulticall(
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        uint256 amountIn
    ) public {
        uint256 callsLength = swapAggregatorMulticall.calls.length;
        bytes memory callData;
        for (uint256 i = 0; i < callsLength; ) {
            ConveyorSwapAggregator.Call memory call = swapAggregatorMulticall
                .calls[i];

            if (deriveU64Bitmap(swapAggregatorMulticall.isUniV2BitMap, i)) {
                bool zeroForOne = deriveU64Bitmap(
                    swapAggregatorMulticall.zeroForOneBitMap,
                    i
                );
                address receiver;
                {
                    uint256 toAddressBitPattern = deriveToAddress(
                        swapAggregatorMulticall.toAddressBitMap,
                        i
                    );

                    if (toAddressBitPattern == 0x3) {
                        receiver = msg.sender;
                    } else if (toAddressBitPattern == 0x2) {
                        receiver = address(this);
                    } else {
                        receiver = swapAggregatorMulticall.calls[i + 1].target;
                    }
                }
                (callData, amountIn) = constructV2SwapCalldata(
                    amountIn,
                    zeroForOne,
                    receiver,
                    call.target
                );

                (bool success, ) = call.target.call(callData);

                require(success, "call failed");
                
            } else {
                (bool success, bytes memory data) = call.target.call(
                    call.callData
                );
                require(success, "call failed");
                (amountIn,) = abi.decode(data, (uint256, uint256));
            }

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

    function constructV2SwapCalldata(
        uint256 amountIn,
        bool zeroForOne,
        address to,
        address pool
    ) internal view returns (bytes memory callData, uint256 amountOut) {
        ///@notice Get the reserves for the pool.
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pool)
            .getReserves();

        ///@notice Get the amountOut from the reserves.
        amountOut = getAmountOut(
            amountIn,
            zeroForOne ? reserve0 : reserve1,
            zeroForOne ? reserve1 : reserve0
        );

        ///@notice Get the callData for the swap.
        callData = abi.encodeWithSignature(
            "swap(uint amount0Out, uint amount1Out, address to, bytes calldata data)",
            zeroForOne ? 0 : amountOut,
            zeroForOne ? amountOut : 0,
            to,
            new bytes(0)
        );
    }

    //Note: In human readable format, this is read from right to left, with the right most binary digit being the first representation
    //of tokenIsToken0 for the first pool in the route
    function deriveU64Bitmap(
        uint64 zeroForOneBitmap,
        uint256 i
    ) public pure returns (bool) {
        if ((2 ** i) & zeroForOneBitmap == 0) {
            return false;
        } else {
            return true;
        }
    }

    //01 = msg.sender, 10 = executor, 11 = next pool
    function deriveToAddress(
        uint128 toAddressBitMap,
        uint256 i
    ) public pure returns (uint256) {
        if ((3 << i) & toAddressBitMap == 3 << i) {
            return 0x3;
        } else if ((2 << i) & toAddressBitMap == 2 << i) {
            return 0x2;
        } else if ((1 << i) & toAddressBitMap == 1 << i) {
            return 0x1;
        } else {
            //TODO: revert
        }
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
            revert InsufficientInputAmount(0, 1);
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
}
