// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../lib/libraries/token/SafeERC20.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {GenericMulticall} from "./GenericMulticall.sol";

interface IConveyorMulticall {
    function executeMulticall(
        ConveyorRouterV1.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        uint256 amountIn,
        address receiver
    ) external;

    function executeGenericMulticall(
        ConveyorRouterV1.SwapAggregatorGenericMulticall calldata genericMulticall
    ) external;
}

/// @title ConveyorRouterV1
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Multicall contract for token Swaps.
contract ConveyorRouterV1 {
    using SafeERC20 for IERC20;
    address public immutable CONVEYOR_MULTICALL;
    address public immutable WETH;

    address owner;
    address tempOwner;

    /**@notice Event that is emitted when a token to token swap has filled successfully.
     **/
    event Swap(
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address indexed receiver
    );

    /**@notice Event that is emitted when a token to ETH swap has filled successfully.
     **/
    event SwapExactTokenForEth(
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        address indexed receiver
    );

    /**@notice Event that is emitted when a ETH to token swap has filled successfully.
     **/
    event SwapExactEthForToken(
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address indexed receiver
    );

    /** @notice Event that is emitted when a referral token swap has filled successfully
     **/
    event Referral(
        address indexed referrer,
        address indexed receiver,
        uint256 referralFee
    );

    /** @notice Event that is emitted when ETH is withdrawn from the contract
     **/
    event Withdraw(address indexed receiver, uint256 amount);

    ///@notice Modifier function to only allow the owner of the contract to call specific functions
    ///@dev Functions with onlyOwner: withdraw
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }

    ///@dev Deploys the ConveyorSwapExecutor contract.
    ///@param _weth Address of Wrapped Native Asset.
    constructor(address _weth) {
        require(_weth != address(0), "WETH address is zero");
        CONVEYOR_MULTICALL = address(new ConveyorMulticall(address(this)));
        WETH = _weth;
        owner = tx.origin;
    }

    /// @notice SwapAggregatorMulticall struct for token Swaps.
    /// @param zeroForOneBitmap for zeroForOne bool along the swap calls.
    /// @param callTypeBitmap determines the call type being executed.
    /// @param toAddressBitmap for toAddress address along the swap calls.
    /// @param feeBitmap for uniV2 custom fee's along the swap calls.
    /// @param tokenInDestination Address to send tokenIn to.
    /// @param calls Array of calls to be executed.
    struct SwapAggregatorMulticall {
        uint24 zeroForOneBitmap;
        uint40 callTypeBitmap;
        uint64 toAddressBitmap;
        uint128 feeBitmap;
        address tokenInDestination;
        Call[] calls;
    }

    /// @notice Gas optimized Multicall struct
    struct SwapAggregatorGenericMulticall {
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

    /// @notice ReferralInfo struct for token Swaps.
    /// @param referrer Address of referrer.
    /// @param referralFee Referral fee.
    struct ReferralInfo {
        address referrer;
        uint256 referralFee;
    }

    /// @notice Swap tokens for tokens.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) public payable {
        ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
        IERC20(tokenIn).transferFrom(
            msg.sender,
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );

        ///@notice Get tokenOut balance of msg.sender.
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);
        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = balanceBefore + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeMulticall(
            swapAggregatorMulticall,
            amountIn,
            msg.sender
        );

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Check if tokenOut balance of msg.sender is sufficient.
        if (balanceAfter < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - balanceAfter,
                amountOutMin
            );
        }

        ///@notice Emit Swap event.
        emit Swap(
            tokenIn,
            amountIn,
            tokenOut,
            balanceAfter - balanceBefore,
            msg.sender
        );
    }

    /// @notice Swap tokens for tokens.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param genericMulticall Multicall to be executed.
    function swapExactTokenForTokenOptimized(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorGenericMulticall calldata genericMulticall
    ) public payable {
        ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
        IERC20(tokenIn).transferFrom(
            msg.sender,
            genericMulticall.tokenInDestination,
            amountIn
        );

        ///@notice Get tokenOut balance of msg.sender.
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);
        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = balanceBefore + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeGenericMulticall(
            genericMulticall
        );

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Check if tokenOut balance of msg.sender is sufficient.
        if (balanceAfter < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - balanceAfter,
                amountOutMin
            );
        }

        ///@notice Emit Swap event.
        emit Swap(
            tokenIn,
            amountIn,
            tokenOut,
            balanceAfter - balanceBefore,
            msg.sender
        );
    }

    /// @notice Swap tokens for tokens with referral.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    /// @param referralInfo Referral information.
    function swapExactTokenForTokenWithReferral(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo
    ) public payable {
        uint256 referralFee = referralInfo.referralFee;
        address referrer = referralInfo.referrer;

        ///@notice Transfer referral fee to referrer.
        if (referrer != address(0) && referralFee <= msg.value) {
            /// @dev The remaining amount is stored in the contract for withdrawal.
            _safeTransferETH(referralInfo.referrer, referralFee);
        } else {
            revert InvalidReferral();
        }

        ///@notice Swap tokens for tokens.
        swapExactTokenForToken(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            swapAggregatorMulticall
        );

        ///@notice Emit Referral event.
        emit Referral(referrer, msg.sender, referralFee);
    }

    /// @notice Swap ETH for tokens.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) public payable {
        if (protocolFee > msg.value) {
            revert InsufficientMsgValue();
        }

        ///@notice Cache the amountIn to save gas.
        uint256 amountIn = msg.value - protocolFee;

        ///@notice Deposit the msg.value-protocolFee into WETH.
        _depositEth(amountIn, WETH);

        ///@notice Transfer WETH from WETH to tokenInDestination address.
        IERC20(WETH).transfer(
            swapAggregatorMulticall.tokenInDestination,
            amountIn
        );

        ///@notice Get tokenOut balance of msg.sender.
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = balanceBefore + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeMulticall(
            swapAggregatorMulticall,
            amountIn,
            msg.sender
        );

        ///@notice Get tokenOut balance of msg.sender after multicall execution.
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Revert if tokenOut balance of msg.sender is insufficient.
        if (balanceAfter < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(
                tokenOutAmountRequired - balanceAfter,
                amountOutMin
            );
        }

        ///@notice Emit SwapExactEthForToken event.
        emit SwapExactEthForToken(
            msg.value,
            tokenOut,
            balanceAfter - balanceBefore,
            msg.sender
        );
    }

    /// @notice Swap ETH for tokens with Referral.
    /// @param tokenOut Address of token to receive.
    /// @param amountOutMin Minimum amount of tokenOut to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    /// @param referralInfo Referral information.
    function swapExactEthForTokenWithReferral(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo
    ) public payable {
        if (protocolFee > msg.value) {
            revert InsufficientMsgValue();
        }

        uint256 referralFee = referralInfo.referralFee;
        address referrer = referralInfo.referrer;

        ///@notice Transfer referral fee to referrer.
        if (referralInfo.referrer != address(0) && referralFee <= protocolFee) {
            _safeTransferETH(referrer, referralFee);
        } else {
            revert InvalidReferral();
        }

        swapExactEthForToken(
            tokenOut,
            amountOutMin,
            protocolFee,
            swapAggregatorMulticall
        );
        ///@notice Emit Referral event.
        emit Referral(referrer, msg.sender, referralFee);
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
    ) public payable {
        ///@dev Ignore if the tokenInDestination is address(0).
        if (swapAggregatorMulticall.tokenInDestination != address(0)) {
            ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
            IERC20(tokenIn).transferFrom(
                msg.sender,
                swapAggregatorMulticall.tokenInDestination,
                amountIn
            );
        }
        ///@notice Get ETH balance of msg.sender.
        uint256 balanceBefore = msg.sender.balance;

        ///@notice Calculate amountOutRequired.
        uint256 amountOutRequired = balanceBefore + amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeMulticall(
            swapAggregatorMulticall,
            amountIn,
            msg.sender
        );

        ///@notice Get WETH balance of this contract.
        uint256 balanceWeth = IERC20(WETH).balanceOf(address(this));

        ///@notice Withdraw WETH from this contract.
        _withdrawEth(balanceWeth, WETH);

        ///@notice Transfer ETH to msg.sender.
        _safeTransferETH(msg.sender, balanceWeth);

        ///@notice Revert if Eth balance of the caller is insufficient.
        if (msg.sender.balance < amountOutRequired) {
            revert InsufficientOutputAmount(
                amountOutRequired - msg.sender.balance,
                amountOutMin
            );
        }

        ///@notice Emit SwapExactTokenForEth event.
        emit SwapExactTokenForEth(
            tokenIn,
            amountIn,
            msg.sender.balance - balanceBefore,
            msg.sender
        );
    }

    /// @notice Swap tokens for ETH.
    /// @param tokenIn Address of token to swap.
    /// @param amountIn Amount of tokenIn to swap.
    /// @param amountOutMin Minimum amount of ETH to receive.
    /// @param swapAggregatorMulticall Multicall to be executed.
    /// @param referralInfo Referral information.
    function swapExactTokenForEthWithReferral(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo
    ) public payable {
        uint256 referralFee = referralInfo.referralFee;
        address referrer = referralInfo.referrer;
        ///@notice Transfer referral fee to referrer.
        if (referralInfo.referrer != address(0) && referralFee <= msg.value) {
            _safeTransferETH(referrer, referralFee);
        } else {
            revert InvalidReferral();
        }

        swapExactTokenForEth(
            tokenIn,
            amountIn,
            amountOutMin,
            swapAggregatorMulticall
        );

        ///@notice Emit Referral event.
        emit Referral(referrer, msg.sender, referralFee);
    }

    /// @notice Quotes the amount of gas used for a token to token swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactTokenForToken(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo,
        bool isReferral
    ) external payable returns (uint256 gasConsumed) {
        if (isReferral) {
            assembly {
                mstore(0x60, gas())
            }
            swapExactTokenForTokenWithReferral(
                tokenIn,
                amountIn,
                tokenOut,
                amountOutMin,
                swapAggregatorMulticall,
                referralInfo
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        } else {
            assembly {
                mstore(0x60, gas())
            }
            swapExactTokenForToken(
                tokenIn,
                amountIn,
                tokenOut,
                amountOutMin,
                swapAggregatorMulticall
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        }
    }

    /// @notice Quotes the amount of gas used for a ETH to token swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactEthForToken(
        address tokenOut,
        uint128 amountOutMin,
        uint128 protocolFee,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo,
        bool isReferral
    ) external payable returns (uint256 gasConsumed) {
        if (isReferral) {
            assembly {
                mstore(0x60, gas())
            }
            swapExactEthForTokenWithReferral(
                tokenOut,
                amountOutMin,
                protocolFee,
                swapAggregatorMulticall,
                referralInfo
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        } else {
            assembly {
                mstore(0x60, gas())
            }
            swapExactEthForToken(
                tokenOut,
                amountOutMin,
                protocolFee,
                swapAggregatorMulticall
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        }
    }

    /// @notice Quotes the amount of gas used for a token to ETH swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapAggregatorMulticall calldata swapAggregatorMulticall,
        ReferralInfo calldata referralInfo,
        bool isReferral
    ) external payable returns (uint256 gasConsumed) {
        if (isReferral) {
            assembly {
                mstore(0x60, gas())
            }
            swapExactTokenForEthWithReferral(
                tokenIn,
                amountIn,
                amountOutMin,
                swapAggregatorMulticall,
                referralInfo
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        } else {
            assembly {
                mstore(0x60, gas())
            }
            swapExactTokenForEth(
                tokenIn,
                amountIn,
                amountOutMin,
                swapAggregatorMulticall
            );
            assembly {
                gasConsumed := sub(mload(0x60), gas())
            }
        }
    }

    ///@notice Helper function to transfer ETH.
    function _safeTransferETH(address to, uint256 amount) internal {
        bool success;
        /// @solidity memory-safe-assembly
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
        /// @solidity memory-safe-assembly
        assembly {
            mstore(
                0x0,
                shl(224, 0x2e1a7d4d) /* keccak256("withdraw(uint256)") */
            )
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
        /// @solidity memory-safe-assembly
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
                revert("Native token deposit failed", amount)
            }
        }
    }

    /// @notice Withdraw ETH from this contract.
    function withdraw() external onlyOwner {
        _safeTransferETH(msg.sender, address(this).balance);
        emit Withdraw(msg.sender, address(this).balance);
    }

    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if (msg.sender != tempOwner) {
            revert UnauthorizedCaller();
        }

        ///@notice Cleanup tempOwner storage.
        tempOwner = address(0);
        owner = msg.sender;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }

        tempOwner = newOwner;
    }

    /// @notice Fallback receiver function.
    receive() external payable {}
}

/// @title ConveyorMulticall
/// @author 0xOsiris, 0xKitsune, Conveyor Labs
/// @notice Optimized multicall execution contract.
contract ConveyorMulticall is
    GenericMulticall,
    UniswapV3Callback,
    UniswapV2Callback
{
    address immutable CONVEYOR_SWAP_AGGREGATOR;

    ///@param conveyorRouterV1 Address of the ConveyorRouterV1 contract.
    constructor(address conveyorRouterV1) {
        CONVEYOR_SWAP_AGGREGATOR = conveyorRouterV1;
    }

    ///@notice Executes a multicall.
    ///@param swapAggregatorMulticall Multicall to be executed.
    ///@param amountIn Amount of tokenIn to swap.
    ///@param recipient Recipient of the output tokens.
    function executeMulticall(
        ConveyorRouterV1.SwapAggregatorMulticall
            calldata swapAggregatorMulticall,
        uint256 amountIn,
        address payable recipient
    ) public {
        ///@notice Get the length of the calls array.
        uint256 callsLength = swapAggregatorMulticall.calls.length;

        ///@notice Create a bytes array to store the calldata for v2 swaps.
        bytes memory callData;

        ///@notice Cache the feeBitmap in memory.
        uint128 feeBitmap = swapAggregatorMulticall.feeBitmap;
        ///@notice Iterate through the calls array.
        for (uint256 i = 0; i < callsLength; ) {
            ///@notice Get the call from the calls array.
            ConveyorRouterV1.Call memory call = swapAggregatorMulticall.calls[
                i
            ];

            ///@notice Get the zeroForOne value from the zeroForOneBitmap.
            bool zeroForOne = deriveBoolFromBitmap(
                swapAggregatorMulticall.zeroForOneBitmap,
                i
            );
            uint256 callType = deriveCallFromBitmap(
                swapAggregatorMulticall.callTypeBitmap,
                i
            );
            ///@notice Check if the call is a v2 swap.
            if (callType == 0x0) {
                ///@notice Instantiate the receiver address for the v2 swap.
                address receiver;
                {
                    ///@notice Get the toAddressBitPattern from the toAddressBitmap.
                    uint256 toAddressBitPattern = deriveToAddressFromBitmap(
                        swapAggregatorMulticall.toAddressBitmap,
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
                (callData, amountIn, feeBitmap) = constructV2SwapCalldata(
                    amountIn,
                    zeroForOne,
                    receiver,
                    call.target,
                    feeBitmap
                );

                ///@notice Execute the v2 swap.
                (bool success, ) = call.target.call(callData);

                if (!success) {
                    revert V2SwapFailed();
                }
            } else if (callType == 0x1) {
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
            } else {
                ///@notice Execute the v3 swap.
                (bool success, ) = call.target.call(call.callData);
                if (!success) {
                    revert CallFailed();
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    ///@notice Constructs the calldata for a v2 swap.
    ///@param amountIn - The amount of tokenIn to swap.
    ///@param zeroForOne - The direction of the swap.
    ///@param to - The address to send the swapped tokens to.
    ///@param pool - The address of the v2 liquidity pool.
    ///@param feeBitmap - The bitmap of fees to use for the swap.
    ///@return callData - The calldata for the v2 swap.
    ///@return amountOut - The amount of tokenOut received from the swap.
    ///@return updatedFeeBitmap - The updated feeBitmap.
    function constructV2SwapCalldata(
        uint256 amountIn,
        bool zeroForOne,
        address to,
        address pool,
        uint128 feeBitmap
    )
        internal
        view
        returns (
            bytes memory callData,
            uint256 amountOut,
            uint128 updatedFeeBitmap
        )
    {
        ///@notice Get the reserves for the pool.
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pool)
            .getReserves();
        uint24 fee;

        (fee, updatedFeeBitmap) = deriveFeeFromBitmap(feeBitmap);

        ///@notice Get the amountOut from the reserves.
        amountOut = getAmountOut(
            amountIn,
            zeroForOne ? reserve0 : reserve1,
            zeroForOne ? reserve1 : reserve0,
            fee
        );
        ///@notice Encode the swap calldata.
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
    ///@notice Derives a boolean at a specific bit position from a bitmap.
    ///@param bitmap - The bitmap to derive the boolean from.
    ///@param position - The bit position.
    function deriveBoolFromBitmap(
        uint64 bitmap,
        uint256 position
    ) internal pure returns (bool) {
        if ((2 ** position) & bitmap == 0) {
            return false;
        } else {
            return true;
        }
    }

    /// @notice Derives the call type from a bitmap.
    /** @dev
        0x0 - Uniswap v2 swap
        0x1 - Uniswap v3 swap
        0x2 - Generic call
    */
    function deriveCallFromBitmap(
        uint40 bitmap,
        uint256 position
    ) internal pure returns (uint256 callType) {
        /// @solidity memory-safe-assembly
        assembly {
            let significantBits := shl(mul(position, 0x2), 0x3)

            switch shr(mul(position, 0x2), and(bitmap, significantBits))
            case 0x0 {
                callType := 0x0
            }
            case 0x1 {
                callType := 0x1
            }
            case 0x2 {
                callType := 0x2
            }
        }
    }

    //Note: In human readable format, this is read from right to left, with the right most binary digit being the first bit of the next fee to derive.
    ///@dev Each non standard fee is represented within exactly 10 bits (0-1024), if the fee is 300 then a single 0 bit is used.
    ///@notice Derives the fee from the feeBitmap.
    ///@param feeBitmap - The bitmap of fees to use for the swap.
    ///@return fee - The fee to use for the swap.
    ///@return updatedFeeBitmap - The updated feeBitmap.
    function deriveFeeFromBitmap(
        uint128 feeBitmap
    ) internal pure returns (uint24 fee, uint128 updatedFeeBitmap) {
        /**@dev Retrieve the first 10 bits from the feeBitmap to get the fee, shift right to set the next
            fee in the first bit position.**/
        fee = uint24(feeBitmap & 0x3FF);
        updatedFeeBitmap = feeBitmap >> 10;
    }

    ///@dev Bit Patterns: 01 => msg.sender, 10 => ConveyorSwapExecutor, 11 = next pool, 00 = ConveyorRouterV1
    ///@notice Derives the toAddress from the toAddressBitmap.
    ///@param toAddressBitmap - The bitmap of toAddresses to use for the swap.
    ///@param i - The index of the toAddress to derive.
    ///@return unsigned - 2 bit pattern representing the receiver of the current swap.
    function deriveToAddressFromBitmap(
        uint128 toAddressBitmap,
        uint256 i
    ) internal pure returns (uint256) {
        if ((3 << (2 * i)) & toAddressBitmap == 3 << (2 * i)) {
            return 0x3;
        } else if ((2 << (2 * i)) & toAddressBitmap == 2 << (2 * i)) {
            return 0x2;
        } else if ((1 << (2 * i)) & toAddressBitmap == 1 << (2 * i)) {
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
        uint256 reserveOut,
        uint24 fee
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
        /**Note: fee is specified in the callData as per the UniswapV2 variants specification.
            If this fee is not specified correctly the swap will likely fail, or yield unoptimal 
            trade values.**/
        uint256 amountInWithFee = amountIn * (100000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 100000 + (amountInWithFee);
        amountOut = numerator / denominator;
    }
}
