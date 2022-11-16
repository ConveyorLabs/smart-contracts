// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "./interfaces/IOrderBook.sol";
import "./lib/ConveyorMath.sol";

/// @title SandboxValidator
/// @author 0xOsiris, 0xKitsune, Conveyor Labs
contract SandboxValidator {
    address immutable LIMIT_ORDER_ROUTER;

    constructor(address _limitOrderRouter) {
        LIMIT_ORDER_ROUTER = _limitOrderRouter;
    }

    struct PreSandboxExecutionState {
        OrderBook.SandboxLimitOrder[] sandboxLimitOrders;
        address[] orderOwners;
        uint256[] initialTokenInBalances;
        uint256[] initialTokenOutBalances;
    }

    function initializePreSandboxExecutionState(
        bytes32[][] calldata orderIdBundles,
        uint128[] calldata fillAmounts
    )
        external
        view
        returns (PreSandboxExecutionState memory preSandboxExecutionState)
    {
        ///@notice Initialize data to hold pre execution validation state.
        preSandboxExecutionState
            .sandboxLimitOrders = new OrderBook.SandboxLimitOrder[](
            fillAmounts.length
        );
        preSandboxExecutionState.orderOwners = new address[](
            fillAmounts.length
        );
        preSandboxExecutionState.initialTokenInBalances = new uint256[](
            fillAmounts.length
        );
        preSandboxExecutionState.initialTokenOutBalances = new uint256[](
            fillAmounts.length
        );

        uint256 arrayIndex = 0;
        {
            for (uint256 i = 0; i < orderIdBundles.length; ++i) {
                bytes32[] memory orderIdBundle = orderIdBundles[i];

                for (uint256 j = 0; j < orderIdBundle.length; ++j) {
                    bytes32 orderId = orderIdBundle[j];

                    ///@notice Transfer the tokens from the order owners to the sandbox router contract.
                    ///@dev This function is executed in the context of LimitOrderExecutor as a delegatecall.

                    ///@notice Get the current order
                    OrderBook.SandboxLimitOrder
                        memory currentOrder = IOrderBook(LIMIT_ORDER_ROUTER)
                            .getSandBoxOrderById(orderId);

                    if (currentOrder.orderId == bytes32(0)) {
                        revert OrderDoesNotExist(orderId);
                    }

                    preSandboxExecutionState.orderOwners[
                        arrayIndex
                    ] = currentOrder.owner;

                    preSandboxExecutionState.sandboxLimitOrders[
                        arrayIndex
                    ] = currentOrder;

                    ///@notice Cache amountSpecifiedToFill for intermediate calculations
                    uint128 amountSpecifiedToFill = fillAmounts[arrayIndex];
                    ///@notice Require the amountSpecifiedToFill is less than or equal to the amountInRemaining of the order.
                    if (
                        amountSpecifiedToFill > currentOrder.amountInRemaining
                    ) {
                        revert FillAmountSpecifiedGreaterThanAmountRemaining(
                            amountSpecifiedToFill,
                            currentOrder.amountInRemaining,
                            currentOrder.orderId
                        );
                    }

                    ///@notice Cache the the pre execution state of the order details
                    preSandboxExecutionState.initialTokenInBalances[
                        arrayIndex
                    ] = IERC20(currentOrder.tokenIn).balanceOf(
                        currentOrder.owner
                    );

                    preSandboxExecutionState.initialTokenOutBalances[
                        arrayIndex
                    ] = IERC20(currentOrder.tokenOut).balanceOf(
                        currentOrder.owner
                    );

                    unchecked {
                        ++arrayIndex;
                    }
                }
            }
        }
    }

    function validateSandboxExecutionAndFillOrders(
        bytes32[][] memory orderIdBundles,
        uint128[] memory fillAmounts,
        PreSandboxExecutionState memory preSandboxExecutionState
    ) external {
        uint256 orderIdIndex = 0;

        for (uint256 i = 0; i < orderIdBundles.length; ++i) {
            bytes32[] memory orderIdBundle = orderIdBundles[i];

            if (orderIdBundle.length > 1) {
                _validateMultiOrderBundle(
                    orderIdIndex,
                    orderIdBundle.length,
                    fillAmounts,
                    preSandboxExecutionState
                );

                orderIdIndex += orderIdBundle.length - 1;
            } else {
                _validateSingleOrderBundle(
                    preSandboxExecutionState.sandboxLimitOrders[orderIdIndex],
                    fillAmounts[orderIdIndex],
                    preSandboxExecutionState.initialTokenInBalances[
                        orderIdIndex
                    ],
                    preSandboxExecutionState.initialTokenOutBalances[
                        orderIdIndex
                    ]
                );

                ++orderIdIndex;
            }
        }
    }

    function _validateSingleOrderBundle(
        OrderBook.SandboxLimitOrder memory currentOrder,
        uint128 fillAmount,
        uint256 initialTokenInBalance,
        uint256 initialTokenOutBalance
    ) internal {
        ///@notice Cache values for post execution assertions
        uint128 amountOutRequired = uint128(
            ConveyorMath.mul64U(
                ConveyorMath.divUU(
                    currentOrder.amountOutRemaining,
                    currentOrder.amountInRemaining
                ),
                fillAmount
            )
        );

        if (amountOutRequired == 0) {
            revert AmountOutRequiredIsZero(currentOrder.orderId);
        }

        uint256 currentTokenInBalance = IERC20(currentOrder.tokenIn).balanceOf(
            currentOrder.owner
        );

        uint256 currentTokenOutBalance = IERC20(currentOrder.tokenOut)
            .balanceOf(currentOrder.owner);

        ///@notice Assert that the tokenIn balance is decremented by the fill amount exactly
        if (initialTokenInBalance - currentTokenInBalance > fillAmount) {
            revert SandboxFillAmountNotSatisfied(
                currentOrder.orderId,
                initialTokenInBalance - currentTokenInBalance,
                fillAmount
            );
        }

        ///@notice Assert that the tokenOut balance is greater than or equal to the amountOutRequired
        if (
            currentTokenOutBalance - initialTokenOutBalance != amountOutRequired
        ) {
            revert SandboxAmountOutRequiredNotSatisfied(
                currentOrder.orderId,
                currentTokenOutBalance - initialTokenOutBalance,
                amountOutRequired
            );
        }

        ///@notice Update the sandboxLimitOrder after the execution requirements have been met.
        if (currentOrder.amountInRemaining == fillAmount) {
            IOrderBook(LIMIT_ORDER_ROUTER).resolveCompletedOrder(
                currentOrder.orderId,
                OrderBook.OrderType.PendingSandboxLimitOrder
            );
        } else {
            ///@notice Update the state of the order to parial filled quantities.
            IOrderBook(LIMIT_ORDER_ROUTER).partialFillSandboxLimitOrder(
                uint128(initialTokenInBalance - currentTokenInBalance),
                uint128(currentTokenOutBalance - initialTokenOutBalance),
                currentOrder.orderId
            );
        }
    }

    function _validateMultiOrderBundle(
        uint256 orderIdIndex,
        uint256 bundleLength,
        uint128[] memory fillAmounts,
        PreSandboxExecutionState memory preSandboxExecutionState
    ) internal {
        ///@notice Cache the first order in the bundle
        OrderBook.SandboxLimitOrder memory prevOrder = preSandboxExecutionState
            .sandboxLimitOrders[orderIdIndex];

        ///@notice Update the cumulative fill amount to include the fill amount for the first order in the bundle
        uint256 cumulativeFillAmount = fillAmounts[orderIdIndex];
        ///@notice Update the cumulativeAmountOutRequired to include the amount out required for the first order in the bundle
        uint128 cumulativeAmountOutRequired = uint128(
            ConveyorMath.mul64U(
                ConveyorMath.divUU(
                    prevOrder.amountOutRemaining,
                    prevOrder.amountInRemaining
                ),
                fillAmounts[orderIdIndex]
            )
        );

        if (cumulativeAmountOutRequired == 0) {
            revert AmountOutRequiredIsZero(prevOrder.orderId);
        }

        ///@notice Set the orderOwner to the first order in the bundle
        address orderOwner = prevOrder.owner;
        ///@notice Update the offset for the sandboxLimitOrders array to correspond with the order in the bundle

        {
            // ///@notice For each order in the bundle
            // for (uint256 i = 1; i < bundleLength; ++i) {
            //     ///@notice Cache the order
            //     OrderBook.SandboxLimitOrder
            //         memory currentOrder = preSandboxExecutionState
            //             .sandboxLimitOrders[orderIdIndex + 1];
            //     ///@notice Cache the amountOutRequired for the current order
            //     uint128 amountOutRequired = uint128(
            //         ConveyorMath.mul64U(
            //             ConveyorMath.divUU(
            //                 currentOrder.amountOutRemaining,
            //                 currentOrder.amountInRemaining
            //             ),
            //             fillAmounts[orderIdIndex + 1]
            //         )
            //     );
            //     if (amountOutRequired == 0) {
            //         revert AmountOutRequiredIsZero(currentOrder.orderId);
            //     }
            //     ///@notice If the current order and previous order tokenIn do not match, assert that the cumulative fill amount can be met
            //     if (currentOrder.tokenIn != prevOrder.tokenIn) {
            //         ///@notice Assert that the tokenIn balance is decremented by the fill amount exactly
            //         if (
            //             preSandboxExecutionState.initialTokenInBalances[
            //                 orderIdIndex
            //             ] -
            //                 IERC20(prevOrder.tokenIn).balanceOf(orderOwner) >
            //             cumulativeFillAmount
            //         ) {
            //             revert SandboxFillAmountNotSatisfied(
            //                 prevOrder.orderId,
            //                 preSandboxExecutionState.initialTokenInBalances[
            //                     orderIdIndex
            //                 ] - IERC20(prevOrder.tokenIn).balanceOf(orderOwner),
            //                 cumulativeFillAmount
            //             );
            //         }
            //         cumulativeFillAmount = fillAmounts[orderIdIndex + 1];
            //     } else {
            //         cumulativeFillAmount += fillAmounts[orderIdIndex + 1];
            //     }
            //     if (currentOrder.tokenOut != prevOrder.tokenOut) {
            //         ///@notice Assert that the tokenOut balance is greater than or equal to the amountOutRequired
            //         if (
            //             IERC20(prevOrder.tokenOut).balanceOf(orderOwner) -
            //                 preSandboxExecutionState.initialTokenOutBalances[
            //                     orderIdIndex
            //                 ] !=
            //             cumulativeAmountOutRequired
            //         ) {
            //             revert SandboxAmountOutRequiredNotSatisfied(
            //                 prevOrder.orderId,
            //                 IERC20(prevOrder.tokenOut).balanceOf(orderOwner) -
            //                     preSandboxExecutionState
            //                         .initialTokenOutBalances[orderIdIndex],
            //                 cumulativeAmountOutRequired
            //             );
            //         }
            //         cumulativeAmountOutRequired = amountOutRequired;
            //     } else {
            //         cumulativeAmountOutRequired += amountOutRequired;
            //     }
            //     ///@notice Update the sandboxLimitOrder after the execution requirements have been met.
            //     if (prevOrder.amountInRemaining == fillAmounts[orderIdIndex]) {
            //         IOrderBook(LIMIT_ORDER_ROUTER).resolveCompletedOrder(
            //             prevOrder.orderId,
            //             OrderBook.OrderType.PendingSandboxLimitOrder
            //         );
            //     } else {
            //         ///@notice Update the state of the order to parial filled quantities.
            //         IOrderBook(LIMIT_ORDER_ROUTER).partialFillSandboxLimitOrder(
            //                 uint128(fillAmounts[orderIdIndex]),
            //                 uint128(
            //                     ConveyorMath.mul64U(
            //                         ConveyorMath.divUU(
            //                             prevOrder.amountOutRemaining,
            //                             prevOrder.amountInRemaining
            //                         ),
            //                         fillAmounts[orderIdIndex]
            //                     )
            //                 ),
            //                 prevOrder.orderId
            //             );
            //     }
            //     prevOrder = currentOrder;
            //     ++orderIdIndex;
            // }
            // ///@notice Update the sandboxLimitOrder after the execution requirements have been met.
            // if (prevOrder.amountInRemaining == fillAmounts[orderIdIndex - 1]) {
            //     IOrderBook(LIMIT_ORDER_ROUTER).resolveCompletedOrder(
            //         prevOrder.orderId,
            //         OrderBook.OrderType.PendingSandboxLimitOrder
            //     );
            // } else {
            //     ///@notice Update the state of the order to parial filled quantities.
            //     IOrderBook(LIMIT_ORDER_ROUTER).partialFillSandboxLimitOrder(
            //         uint128(fillAmounts[orderIdIndex - 1]),
            //         uint128(
            //             ConveyorMath.mul64U(
            //                 ConveyorMath.divUU(
            //                     prevOrder.amountOutRemaining,
            //                     prevOrder.amountInRemaining
            //                 ),
            //                 fillAmounts[orderIdIndex]
            //             )
            //         ),
            //         prevOrder.orderId
            //     );
            // }
        }
    }
}
