// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./LimitOrderBook.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/token/IWETH.sol";
import "./LimitOrderSwapRouter.sol";
import "./interfaces/ILimitOrderQuoter.sol";
import "./interfaces/IConveyorExecutor.sol";
import "./interfaces/ILimitOrderRouter.sol";

/// @title LimitOrderRouter
/// @author 0xOsiris, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the LimitOrderBook contract.
contract LimitOrderRouter is LimitOrderBook {
    using SafeERC20 for IERC20;
    // ========================================= Modifiers =============================================

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlyEOA() {
        if (msg.sender != tx.origin) {
            revert MsgSenderIsNotTxOrigin();
        }
        _;
    }

    ///@notice Modifier function to only allow the owner of the contract to call specific functions
    ///@dev Functions with onlyOwner: withdrawConveyorFees, transferOwnership.
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }

    ///@notice Modifier to restrict reentrancy into a function.
    modifier nonReentrant() {
        if (reentrancyStatus) {
            revert Reentrancy();
        }
        reentrancyStatus = true;
        _;
        reentrancyStatus = false;
    }

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlyLimitOrderExecutor() {
        if (msg.sender != LIMIT_ORDER_EXECUTOR) {
            revert MsgSenderIsNotLimitOrderExecutor();
        }
        _;
    }

    // ========================================= Constants  =============================================

    ///@notice Interval that determines when an order is eligible for refresh. The interval is set to 30 days represented in Unix time.
    uint256 private constant REFRESH_INTERVAL = 2592000;

    ///@notice The fee paid every time an order is refreshed by an off-chain executor to keep the order active within the system.
    ///@notice The refresh fee is 0.02 ETH
    uint256 private constant REFRESH_FEE = 20000000000000000;

    // ========================================= State Variables =============================================

    ///@notice Boolean responsible for indicating if a function has been entered when the nonReentrant modifier is used.
    bool reentrancyStatus = false;

    ///@notice State variable to track the amount of gas initally alloted during executeLimitOrders.
    uint256 initialTxGas;

    ///@notice Temporary owner storage variable when transferring ownership of the contract.
    address tempOwner;

    ///@notice The owner of the Order Router contract
    ///@dev The contract owner can remove the owner funds from the contract, and transfer ownership of the contract.
    address owner;

    // ========================================= Constructor =============================================

    ///@param _gasOracle - Address of the ChainLink fast gas oracle.
    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _limitOrderExecutor - Address of the limit order executor contract
    ///@param _limitOrderExecutionGasCost - The amount of gas required to execute a limit order.
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _limitOrderExecutionGasCost
    )
        LimitOrderBook(
            _gasOracle,
            _limitOrderExecutor,
            _weth,
            _usdc,
            _limitOrderExecutionGasCost
        )
    {
        ///@notice Require that deployment addresses are not zero
        ///@dev All other addresses are being asserted in the limit order executor, which deploys the limit order router
        require(
            _limitOrderExecutor != address(0),
            "Invalid ConveyorExecutor address"
        );

        ///@notice Set the owner of the contract
        owner = msg.sender;
    }

    /// @notice Function to refresh an order for another 30 days.
    /// @param orderIds - Array of order Ids to indicate which orders should be refreshed.
    function refreshOrder(bytes32[] calldata orderIds) external nonReentrant {
        ///@notice Initialize totalRefreshFees;
        uint256 totalRefreshFees;

        ///@notice For each order in the orderIds array.
        for (uint256 i = 0; i < orderIds.length; ) {
            ///@notice Get the current orderId.
            bytes32 orderId = orderIds[i];

            LimitOrder memory order = getLimitOrderById(orderId);

            totalRefreshFees += _refreshLimitOrder(order);

            unchecked {
                ++i;
            }
        }

        ///@notice Transfer the refresh fee to off-chain executor who called the function.
        IConveyorExecutor(LIMIT_ORDER_EXECUTOR).transferGasCreditFees(
            msg.sender,
            totalRefreshFees
        );
    }

    ///@notice Internal helper function to refresh a Limit Order.
    ///@param order - The Limit Order to be refreshed.
    ///@return executorFee - The fee to be compensated to the off-chain executor.
    function _refreshLimitOrder(LimitOrder memory order)
        internal
        returns (uint256 executorFee)
    {
        uint256 currentBalance = IConveyorExecutor(LIMIT_ORDER_EXECUTOR)
            .gasCreditBalance(order.owner);

        ///@notice Require that current timestamp is not past order expiration, otherwise cancel the order and continue the loop.
        if (block.timestamp > order.expirationTimestamp) {
            return _cancelLimitOrderViaExecutor(order);
        }

        ///@notice Check that the account has enough gas credits to refresh the order, otherwise, cancel the order and continue the loop.
        if (currentBalance < REFRESH_FEE) {
            return _cancelLimitOrderViaExecutor(order);
        }

        if (IERC20(order.tokenIn).balanceOf(order.owner) < order.quantity) {
            return _cancelLimitOrderViaExecutor(order);
        }

        ///@notice If the time elapsed since the last refresh is less than 30 days, continue to the next iteration in the loop.
        if (block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL) {
            revert OrderNotEligibleForRefresh(order.orderId);
        }

        ///@notice Decrement the order.owner's gas credit balance
        IConveyorExecutor(LIMIT_ORDER_EXECUTOR).updateGasCreditBalance(
            order.owner,
            currentBalance - REFRESH_FEE
        );

        ///@notice update the order's last refresh timestamp
        ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
        orderIdToLimitOrder[order.orderId].lastRefreshTimestamp = uint32(
            block.timestamp % (2**32 - 1)
        );

        ///@notice Emit an event to notify the off-chain executors that the order has been refreshed.
        emit OrderRefreshed(
            order.orderId,
            order.lastRefreshTimestamp,
            order.expirationTimestamp
        );

        ///@notice Accumulate the REFRESH_FEE.
        return REFRESH_FEE;
    }

    /// @notice Function for off-chain executors to cancel an Order that does not have the minimum gas credit balance for order execution.
    /// @param orderId - Order Id of the order to cancel.
    /// @return success - Boolean to indicate if the order was successfully canceled and compensation was sent to the off-chain executor.
    function validateAndCancelOrder(bytes32 orderId)
        external
        nonReentrant
        returns (bool success)
    {
        LimitOrder memory order = getLimitOrderById(orderId);

        if (IERC20(order.tokenIn).balanceOf(order.owner) < order.quantity) {
            ///@notice Remove the order from the limit order system.
            IConveyorExecutor(LIMIT_ORDER_EXECUTOR).transferGasCreditFees(
                msg.sender,
                _cancelLimitOrderViaExecutor(order)
            );

            return true;
        }

        return false;
    }

    /// @notice Internal helper function to cancel an order. This function is only called after cancel order validation.
    /// @param order - The order to cancel.
    /// @return success - Boolean to indicate if the order was successfully canceled.
    function _cancelLimitOrderViaExecutor(LimitOrder memory order)
        internal
        returns (uint256)
    {
        ///@notice Get the current gas price.
        uint256 gasPrice = IConveyorGasOracle(CONVEYOR_GAS_ORACLE)
            .getGasPrice();

        ///@notice Get the minimum gas credits needed for a single order
        uint256 executorFee = gasPrice * LIMIT_ORDER_EXECUTION_GAS_COST;

        ///@notice Remove the order from the limit order system.
        _removeOrderFromSystem(order.orderId);

        addressToOrderIds[msg.sender][order.orderId] = OrderType
            .CanceledLimitOrder;

        uint256 orderOwnerGasCreditBalance = IConveyorExecutor(
            LIMIT_ORDER_EXECUTOR
        ).gasCreditBalance(order.owner);

        ///@notice If the order owner's gas credit balance is greater than the minimum needed for a single order, send the executor the minimumGasCreditsForSingleOrder.
        if (orderOwnerGasCreditBalance > executorFee) {
            ///@notice Decrement from the order owner's gas credit balance.
            IConveyorExecutor(LIMIT_ORDER_EXECUTOR).updateGasCreditBalance(
                order.owner,
                orderOwnerGasCreditBalance - executorFee
            );
        } else {
            ///@notice Otherwise, decrement the entire gas credit balance.
            IConveyorExecutor(LIMIT_ORDER_EXECUTOR).updateGasCreditBalance(
                order.owner,
                0
            );
            executorFee = orderOwnerGasCreditBalance;
        }

        ///@notice Emit an order canceled event to notify the off-chain exectors.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCanceled(orderIds);

        return executorFee;
    }

    ///@notice Function to validate the congruency of an array of orders.
    ///@param orders Array of orders to be validated
    function _validateOrderSequencing(LimitOrder[] memory orders)
        internal
        pure
    {
        ///@notice Iterate through the length of orders -1.
        for (uint256 i = 0; i < orders.length - 1; ) {
            ///@notice Cache order at index i, and i+1
            LimitOrder memory currentOrder = orders[i];
            LimitOrder memory nextOrder = orders[i + 1];

            ///@notice Check if the current order is less than or equal to the next order
            if (currentOrder.quantity > nextOrder.quantity) {
                revert InvalidOrderGroupSequence();
            }

            ///@notice Check if the token in is the same for the next order
            if (currentOrder.tokenIn != nextOrder.tokenIn) {
                revert IncongruentInputTokenInOrderGroup(
                    nextOrder.tokenIn,
                    currentOrder.tokenIn
                );
            }

            ///@notice Check if the stoploss status is the same for the next order
            if (currentOrder.stoploss != nextOrder.stoploss) {
                revert IncongruentStoplossStatusInOrderGroup();
            }

            ///@notice Check if the token out is the same for the next order
            if (currentOrder.tokenOut != nextOrder.tokenOut) {
                revert IncongruentOutputTokenInOrderGroup(
                    nextOrder.tokenOut,
                    currentOrder.tokenOut
                );
            }

            ///@notice Check if the buy status is the same for the next order
            if (currentOrder.buy != nextOrder.buy) {
                revert IncongruentBuySellStatusInOrderGroup();
            }

            ///@notice Check if the tax status is the same for the next order
            if (currentOrder.taxed != nextOrder.taxed) {
                revert IncongruentTaxedTokenInOrderGroup();
            }

            ///@notice Check if the fee in is the same for the next order
            if (currentOrder.feeIn != nextOrder.feeIn) {
                revert IncongruentFeeInInOrderGroup();
            }

            ///@notice Check if the fee out is the same for the next order
            if (currentOrder.feeOut != nextOrder.feeOut) {
                revert IncongruentFeeOutInOrderGroup();
            }

            unchecked {
                ++i;
            }
        }
    }

    // ==================== Order Execution Functions =========================

    ///@notice This function is called by off-chain executors, passing in an array of orderIds to execute a specific batch of orders.
    /// @param orderIds - Array of orderIds to indicate which orders should be executed.
    function executeLimitOrders(bytes32[] calldata orderIds)
        external
        nonReentrant
    {
        uint256 gasPrice = IConveyorGasOracle(CONVEYOR_GAS_ORACLE)
            .getGasPrice();

        //Update the initial gas balance.
        assembly {
            sstore(initialTxGas.slot, gas())
        }

        ///@notice Revert if the length of the orderIds array is 0.
        if (orderIds.length == 0) {
            revert InvalidCalldata();
        }

        ///@notice Get all of the orders by orderId and add them to a temporary orders array
        LimitOrder[] memory orders = new LimitOrder[](orderIds.length);

        for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getLimitOrderById(orderIds[i]);
            if (orders[i].orderId == bytes32(0)) {
                revert OrderDoesNotExist(orderIds[i]);
            }
            unchecked {
                ++i;
            }
        }
        ///@notice Cache stoploss status for the orders.
        bool isStoplossExecution = orders[0].stoploss;
        ///@notice If msg.sender != tx.origin and the stoploss status for the batch is true, revert the transaction.
        ///@dev Stoploss batches strictly require EOA execution.
        if (isStoplossExecution) {
            if (msg.sender != tx.origin) {
                revert NonEOAStoplossExecution();
            }
        }

        ///@notice If the length of orders array is greater than a single order, than validate the order sequencing.
        if (orders.length > 1) {
            ///@notice Validate that the orders in the batch are passed in with increasing quantity.
            _validateOrderSequencing(orders);
        }

        uint256 totalBeaconReward;
        uint256 totalConveyorReward;

        ///@notice If the order is not taxed and the tokenOut on the order is Weth
        if (orders[0].tokenOut == WETH) {
            (totalBeaconReward, totalConveyorReward) = IConveyorExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToWethOrders(orders);
        } else {
            ///@notice Otherwise, if the tokenOut is not weth, continue with a regular token to token execution.
            (totalBeaconReward, totalConveyorReward) = IConveyorExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToTokenOrders(orders);
        }

        ///@notice Get the array of order owners.
        address[] memory orderOwners = _getLimitOrderOwners(orders);

        ///@notice Iterate through all orderIds in the batch and delete the orders from queue post execution.
        for (uint256 i = 0; i < orderIds.length; ) {
            bytes32 orderId = orderIds[i];
            ///@notice Mark the order as resolved from the system.
            _resolveCompletedOrder(orderId);

            unchecked {
                ++i;
            }
        }

        ///@notice Emit an order fufilled event to notify the off-chain executors.
        emit OrderFufilled(orderIds);

        ///@notice Calculate the execution gas compensation.
        uint256 executionGasCompensation = _calculateExecutionGasCompensation(
            gasPrice,
            orderOwners,
            OrderType.PendingLimitOrder
        );
        ///@notice Transfer the reward to the off-chain executor.
        IConveyorExecutor(LIMIT_ORDER_EXECUTOR).transferGasCreditFees(
            msg.sender,
            executionGasCompensation
        );
    }

    ///@notice Function to return an array of limit order owners.
    ///@param orders - Array of LimitOrders.
    ///@return orderOwners - An array of order owners in the orders array.
    function _getLimitOrderOwners(LimitOrder[] memory orders)
        internal
        pure
        returns (address[] memory orderOwners)
    {
        orderOwners = new address[](orders.length);
        for (uint256 i = 0; i < orders.length; ) {
            orderOwners[i] = orders[i].owner;
            unchecked {
                ++i;
            }
        }
    }

    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if (msg.sender != tempOwner) {
            revert MsgSenderIsNotTempOwner();
        }
        owner = msg.sender;
        tempOwner = address(0);
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        tempOwner = newOwner;
    }

    ///@notice Function to calculate the execution gas consumed during executeLimitOrders
    ///@return executionGasConsumed - The amount of gas consumed.
    function _calculateExecutionGasConsumed(
        uint256 gasPrice,
        uint256 numberOfOrders,
        OrderType orderType
    ) internal view returns (uint256 executionGasConsumed) {
        assembly {
            executionGasConsumed := mul(
                gasPrice,
                sub(sload(initialTxGas.slot), gas())
            )
        }

        if (orderType == OrderType.PendingLimitOrder) {
            ///@notice If the execution gas is greater than the max compensation, set the compensation to the max
            uint256 maxExecutionCompensation = LIMIT_ORDER_EXECUTION_GAS_COST *
                numberOfOrders *
                gasPrice;
            if (executionGasConsumed > maxExecutionCompensation) {
                executionGasConsumed = maxExecutionCompensation;
            }
        }
    }

    ///@notice Function to adjust order owner's gas credit balance and calaculate the compensation to be paid to the executor.
    ///@param orderOwners - The order owners in the batch.
    ///@return gasExecutionCompensation - The amount to be paid to the off-chain executor for execution gas.
    function _calculateExecutionGasCompensation(
        uint256 gasPrice,
        address[] memory orderOwners,
        OrderType orderType
    ) internal returns (uint256 gasExecutionCompensation) {
        uint256 orderOwnersLength = orderOwners.length;

        ///@notice Decrement gas credit balances for each order owner
        uint256 executionGasConsumed = _calculateExecutionGasConsumed(
            gasPrice,
            orderOwners.length,
            orderType
        );

        uint256 gasDecrementValue = executionGasConsumed / orderOwnersLength;

        ///@notice Unchecked for gas efficiency
        unchecked {
            for (uint256 i = 0; i < orderOwnersLength; ) {
                ///@notice Adjust the order owner's gas credit balance
                uint256 ownerGasCreditBalance = IConveyorExecutor(
                    LIMIT_ORDER_EXECUTOR
                ).gasCreditBalance(orderOwners[i]);

                if (ownerGasCreditBalance >= gasDecrementValue) {
                    IConveyorExecutor(LIMIT_ORDER_EXECUTOR)
                        .updateGasCreditBalance(
                            orderOwners[i],
                            ownerGasCreditBalance - gasDecrementValue
                        );

                    gasExecutionCompensation += gasDecrementValue;
                } else {
                    IConveyorExecutor(LIMIT_ORDER_EXECUTOR)
                        .updateGasCreditBalance(orderOwners[i], 0);

                    gasExecutionCompensation += ownerGasCreditBalance;
                }

                ++i;
            }
        }
    }
}
