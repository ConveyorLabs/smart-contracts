// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";

interface IConveyorSwapExecutor {
    function executeMulticall(
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        uint256 amountIn,
        address receiver
    ) external;
}

/// @title ConveyorSwapAggregator
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Multicall contract for token Swaps.
contract ConveyorSwapAggregator {
    address public immutable CONVEYOR_SWAP_EXECUTOR;
    address public immutable WETH;

    ///@dev Deploys the ConveyorSwapExecutor contract.
    constructor(address _weth) {
        require(_weth != address(0), "WETH address is zero");
        CONVEYOR_SWAP_EXECUTOR = address(
            new ConveyorSwapExecutor(address(this))
        );
        WETH = _weth;
    }

    /// @notice SwapAggregatorMulticall struct for token Swaps.
    /// @param zeroForOneBitMap BitMap for zeroForOne bool along the swap calls.
    /// @param isUniV2BitMap BitMap for isUniV2 bool along the swap calls.
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
        ///@dev Ignore if the tokenInDestination is address(0).
        if (swapAggregatorMulticall.tokenInDestination != address(0)) {
            ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
            IERC20(tokenIn).transferFrom(
                msg.sender,
                swapAggregatorMulticall.tokenInDestination,
                amountIn
            );
        }

        ///@notice Get tokenOut balance of msg.sender.
        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(msg.sender);
        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = tokenOutBalance + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall,
            amountIn,
            msg.sender
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
            swapAggregatorMulticall,
            msg.value,
            msg.sender
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
        ///@dev Ignore if the tokenInDestination is address(0).
        if (swapAggregatorMulticall.tokenInDestination != address(0)) {
            ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
            IERC20(tokenIn).transferFrom(
                msg.sender,
                swapAggregatorMulticall.tokenInDestination,
                amountIn
            );
        }

        ///@notice Calculate amountOutRequired.
        uint256 amountOutRequired = msg.sender.balance + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorSwapExecutor(CONVEYOR_SWAP_EXECUTOR).executeMulticall(
            swapAggregatorMulticall,
            amountIn,
            msg.sender
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
    address immutable CONVEYOR_SWAP_AGGREGATOR;

    constructor(address conveyorSwapAggregator) {
        CONVEYOR_SWAP_AGGREGATOR = conveyorSwapAggregator;
    }

    ///@notice Executes a multicall.
    function executeMulticall(

        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        uint256 amountIn,
        address payable recipient
    ) public {
        ///@notice Get the length of the calls array.
        uint256 callsLength = swapAggregatorMulticall.calls.length;

        ///@notice Create a bytes array to store the calldata for v2 swaps.
        bytes memory callData;
        ///@notice Iterate through the calls array.

        for (uint256 i = 0; i < callsLength; ) {
            ///@notice Get the call from the calls array.
            ConveyorSwapAggregator.Call memory call = swapAggregatorMulticall
                .calls[i];
            ///@notice Get the zeroForOne value from the zeroForOneBitMap.
            bool zeroForOne = deriveBoolFromBitmap(
                swapAggregatorMulticall.zeroForOneBitMap,
                i
            );
            ///@notice Check if the call is a v2 swap.
            if (
                deriveBoolFromBitmap(swapAggregatorMulticall.isUniV2BitMap, i)
            ) {
                ///@notice Instantiate the receiver address for the v2 swap.
                address receiver;
                {
                    ///@notice Get the toAddressBitPattern from the toAddressBitMap.
                    uint256 toAddressBitPattern = deriveToAddressFromBitmap(
                        swapAggregatorMulticall.toAddressBitMap,
                        i
                    );
                    ///@notice Set the receiver address based on the toAddressBitPattern.
                    if (toAddressBitPattern == 0x3) {
                        if (i == callsLength - 1) {
                            revert InvalidToAddressBits();
                        }
                        receiver = swapAggregatorMulticall.calls[i + 1].target;
                    } else if (toAddressBitPattern == 0x2) {
                        receiver = address(this);
                    } else if (toAddressBitPattern == 0x1) {
                        receiver = recipient;
                    } else {
                        receiver = CONVEYOR_SWAP_AGGREGATOR;
                    }
                }

                ///@notice Construct the calldata for the v2 swap.
                (callData, amountIn) = constructV2SwapCalldata(
                    amountIn,
                    zeroForOne,
                    receiver,
                    call.target
                );

                ///@notice Execute the v2 swap.
                (bool success, ) = call.target.call(callData);

                if (!success) {
                    revert V2SwapFailed();
                }
            } else {
                ///@notice Execute the v3 swap.
                (bool success, bytes memory data) = call.target.call(
                    call.callData
                );
                if (!success) {
                    revert V3SwapFailed();
                }
                ///@notice Decode the amountIn from the v3 swap.
                (int256 amount0, int256 amount1) = abi.decode(
                    data,
                    (int256, int256)
                );

                amountIn = zeroForOne ? uint256(-amount1) : uint256(-amount0);
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
            "swap(uint256,uint256,address,bytes)",
            zeroForOne ? 0 : amountOut,
            zeroForOne ? amountOut : 0,
            to,
            new bytes(0)
        );
    }

    //Note: In human readable format, this is read from right to left, with the right most binary digit being the first representation
    //of tokenIsToken0 for the first pool in the route
    function deriveBoolFromBitmap(
        uint64 bitmap,
        uint256 position
    ) public pure returns (bool) {
        if ((2 ** position) & bitmap == 0) {
            return false;
        } else {
            return true;
        }
    }

    //01 = msg.sender, 10 = executor, 11 = next pool, 00 = swapAggregator
    function deriveToAddressFromBitmap(
        uint128 toAddressBitMap,
        uint256 i
    ) internal pure returns (uint256) {
        if ((3 << (2 * i)) & toAddressBitMap == 3 << (2 * i)) {
            return 0x3;
        } else if ((2 << (2 * i)) & toAddressBitMap == 2 << (2 * i)) {
            return 0x2;
        } else if ((1 << (2 * i)) & toAddressBitMap == 1 << (2 * i)) {
            return 0x1;
        } else {
            return 0x0;
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
