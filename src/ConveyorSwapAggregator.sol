// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";

interface IConveyorSwapExecutor {
    function executeMulticall(ConveyorSwapAggregator.Call[] calldata calls)
        external;
}

/// @title LimitOrderSwapRouter
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Dex aggregator that executes standalone swaps, and fulfills limit orders during execution.
contract ConveyorSwapAggregator {
    address immutable CONVEYOR_SWAP_EXECUTOR;

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
    ) public {
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
        internal
    {
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; ) {
            ConveyorSwapAggregator.Call memory call = calls[i];

            address target = call.target;
            bytes memory data = call.callData;
            uint256 dataLength = data.length;

            assembly {
                let success := call(
                    gas(),
                    target,
                    0, // no ether
                    data, // input buffer
                    dataLength, // input length
                    0x00, // output buffer
                    0x00 // output length
                )

                if iszero(success) {
                    revert(0x00, 0xbad)
                }
            }

            unchecked {
                ++i;
            }
        }
    }
}

//--------------------------------------------------------------------
// All Inline Assembly
//--------------------------------------------------------------------

// /// @title LimitOrderSwapRouter
// /// @author 0xKitsune, 0xOsiris, Conveyor Labs
// /// @notice Dex aggregator that executes standalone swaps, and fulfills limit orders during execution.
// contract ConveyorSwapAggregator {
//     address immutable CONVEYOR_SWAP_EXECUTOR;

//     constructor() {
//         CONVEYOR_SWAP_EXECUTOR = address(new ConveyorSwapExecutor());
//     }

//     struct SwapAggregatorCalldata {
//         address tokenInDestination;
//         Call[] multicall;
//     }

//     struct Call {
//         address target;
//         bytes callData;
//     }

//     function swap(
//         address tokenIn,
//         address tokenOut,
//         uint256 amountIn,
//         uint256 amountOutMin,
//         SwapAggregatorCalldata calldata data
//     ) public {
//         //Calldata:
//         //tokenIn -> 0x04
//         //tokenOut -> 0x24
//         //amountIn -> 0x44
//         //amountOutMin -> 0x64
//         //tokenInDestination -> 0x84
//         //multicall length -> 0xA0

//         assembly {
//             // IERC20(tokenIn).transferFrom(msg.sender, tokenInDestination, amountIn);

//             //transferFrom(address,address,uint256)
//             mstore(0x00, 0x23b872dd)
//             //store msg.sender
//             mstore(0x04, caller())
//             //store tokenInDestination
//             mstore(0x24, calldataload(0x80))
//             //store amountIn
//             mstore(0x44, calldataload(0x60))
//             let success := call(
//                 gas(),
//                 calldataload(0x04),
//                 0, // no ether
//                 0x00, // input buffer (starts after the first 32 bytes in the `data` array)
//                 0x64, // input length (loaded from the first 32 bytes in the `data` array)
//                 0x00, // output buffer
//                 0x00 // output length
//             )

//             if iszero(success) {
//                 revert(0x00, 0xbad)
//             }

//             // IERC20(tokenOut).balanceOf(msg.sender);

//             //balanceOf(address)
//             mstore(0x00, 0x70a08231)
//             mstore(0x04, caller())

//             success := call(
//                 gas(),
//                 calldataload(0x24),
//                 0, // no ether
//                 0x00, // input buffer
//                 0x24, // input length
//                 0x00, // output buffer
//                 0x20 // output length
//             )

//             // uint256 tokenOutAmountRequired = tokenOutBalance + amountOutMin;
//             let tokenOutAmountRequired := add(mload(0x00), calldataload(0x64))

//             // executeMulticall(calls);
//         }

//         // uint256 tokenOutAmountRequired = tokenOutBalance + amountOutMin;

//         // executor.executeMulticall(tokenIn, amountIn, multicall);

//         // if (IERC20(tokenOut).balanceOf(msg.sender) < tokenOutAmountRequired) {
//         //     revert InsufficientOutputAmount(
//         //         tokenOutAmountRequired - IERC20(tokenOut).balanceOf(msg.sender),
//         //         amountOutMin
//         //     );
//         // }
//     }
// }

// contract ConveyorSwapExecutor {
//     function executeMulticall(ConveyorSwapAggregator.Call[] calldata calls)
//         internal
//     {
//         assembly {
//             for {
//                 let i := 0
//             } lt(i, calls.length) {
//                 i := add(i, 1)
//             } {
//                 // store the calldata
//                 // mstore(
//                 //     0x00,
//                 //     0xddca3f4300000000000000000000000000000000000000000000000000000000
//                 // )

//                 let success := call(
//                     gas(), // gas remaining
//                     0xdead, // destination address
//                     0, // no ether
//                     0x00, // input buffer (starts after the first 32 bytes in the `data` array)
//                     0x04, // input length (loaded from the first 32 bytes in the `data` array)
//                     0x00, // output buffer
//                     0x00 // output length
//                 )
//             }
//         }
//     }
// }
