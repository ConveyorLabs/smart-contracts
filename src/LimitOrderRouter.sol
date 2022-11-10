// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./OrderBook.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/token/IWETH.sol";
import "./SwapRouter.sol";

import "./interfaces/ILimitOrderQuoter.sol";
import "./interfaces/ILimitOrderExecutor.sol";
import "./interfaces/ILimitOrderRouter.sol";

/// @title LimitOrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract LimitOrderRouter is OrderBook {
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

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlySandboxRouter() {
        if (msg.sender != SANDBOX_ROUTER) {
            revert MsgSenderIsNotSandboxRouter();
        }
        _;
    }

    // ========================================= Constants  =============================================

    ///@notice Interval that determines when an order is eligible for refresh. The interval is set to 30 days represented in Unix time.
    uint256 constant REFRESH_INTERVAL = 2592000;

    ///@notice The fee paid every time an order is refreshed by an off-chain executor to keep the order active within the system.
    ///@notice The refresh fee is 0.02 ETH
    uint256 constant REFRESH_FEE = 20000000000000000;

    // ========================================= Immutables  =============================================
    address public immutable SANDBOX_ROUTER;

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
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _limitOrderExecutionGasCost,
        uint256 _sandboxLimitOrderExecutionGasCost
    )
        OrderBook(
            _gasOracle,
            _limitOrderExecutor,
            _weth,
            _usdc,
            _limitOrderExecutionGasCost,
            _sandboxLimitOrderExecutionGasCost
        )
    {
        ///@notice Require that deployment addresses are not zero
        ///@dev All other addresses are being asserted in the limit order executor, which deploys the limit order router
        require(
            _limitOrderExecutor != address(0),
            "Invalid LimitOrderExecutor address"
        );

        ///@notice Deploy the SandboxRouter and set the SANDBOX_ROUTER address
        SANDBOX_ROUTER = address(
            new SandboxRouter(address(_limitOrderExecutor), address(this))
        );

        ///@notice Set the owner of the contract
        owner = msg.sender;
    }

    // ========================================= FUNCTIONS =============================================

    //------------Gas Credit Functions------------------------

    /// @notice Function to deposit gas credits.
    /// @return success - Boolean that indicates if the deposit completed successfully.
    function depositGasCredits() public payable returns (bool success) {
        if (msg.value == 0) {
            revert InsufficientMsgValue();
        }
        ///@notice Increment the gas credit balance for the user by the msg.value
        uint256 newBalance = gasCreditBalance[msg.sender] + msg.value;

        ///@notice Set the gas credit balance of the sender to the new balance.
        gasCreditBalance[msg.sender] = newBalance;

        ///@notice Emit a gas credit event notifying the off-chain executors that gas credits have been deposited.
        emit GasCreditEvent(msg.sender, newBalance);

        return true;
    }

    /**@notice Function to withdraw gas credits from an account's balance. If the withdraw results in the account's gas credit
    balance required to execute existing orders, those orders must be canceled before the gas credits can be withdrawn.
    */
    /// @param value - The amount to withdraw from the gas credit balance.
    /// @return success - Boolean that indicates if the withdraw completed successfully.
    function withdrawGasCredits(uint256 value)
        public
        nonReentrant
        returns (bool success)
    {
        ///@notice Require that account's credit balance is larger than withdraw amount
        if (gasCreditBalance[msg.sender] < value) {
            revert InsufficientGasCreditBalance();
        }

        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Require that account has enough gas for order execution after the gas credit withdrawal.
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    LIMIT_ORDER_EXECUTION_GAS_COST,
                    msg.sender,
                    gasCreditBalance[msg.sender] - value,
                    GAS_CREDIT_BUFFER
                )
            )
        ) {
            revert InsufficientGasCreditBalanceForOrderExecution();
        }

        ///@notice Decrease the account's gas credit balance
        uint256 newBalance = gasCreditBalance[msg.sender] - value;

        ///@notice Set the senders new gas credit balance.
        gasCreditBalance[msg.sender] = newBalance;

        ///@notice Emit a gas credit event notifying the off-chain executors that gas credits have been deposited.
        emit GasCreditEvent(msg.sender, newBalance);

        ///@notice Transfer the withdraw amount to the account.
        safeTransferETH(msg.sender, value);

        return true;
    }

    ///@notice
    /* This function caches the state of the specified orders before and after arbitrary execution, ensuring that the proper
    prices and fill amounts have been satisfied.
     */

    ///@param sandboxMulticall -
    function executeOrdersViaSandboxMulticall(
        SandboxRouter.SandboxMulticall calldata sandboxMulticall
    ) external onlySandboxRouter nonReentrant {
        ///@notice Initialize arrays to hold pre execution validation state.
        (
            SandboxLimitOrder[] memory sandboxLimitOrders,
            address[] memory orderOwners,
            uint256[] memory initialTokenInBalances,
            uint256[] memory initialTokenOutBalances
        ) = initializePreSandboxExecutionState(
                sandboxMulticall.orderIds,
                sandboxMulticall.fillAmount
            );

        ///@notice Call the limit order executor to transfer all of the order owners tokens to the contract.
        ILimitOrderExecutor(LIMIT_ORDER_EXECUTOR).executeSandboxLimitOrders(
            sandboxLimitOrders,
            sandboxMulticall,
            SANDBOX_ROUTER
        );

        ///@notice Post execution, assert that all of the order owners have received >= their exact amount out
        validateSandboxExecutionAndFillOrders(
            sandboxLimitOrders,
            sandboxMulticall.fillAmount,
            initialTokenInBalances,
            initialTokenOutBalances
        );

        ///@notice Decrement gas credit balances for each order owner
        uint256 executionGasCompensation = calculateExecutionGasCompensation(
            getGasPrice(),
            orderOwners,
            OrderType.SandboxLimitOrder
        );

        ///@notice Transfer the reward to the off-chain executor.
        safeTransferETH(msg.sender, executionGasCompensation);
    }

    function initializePreSandboxExecutionState(
        bytes32[] calldata orderIds,
        uint128[] calldata fillAmounts
    )
        internal
        view
        returns (
            SandboxLimitOrder[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 orderIdsLength = orderIds.length;

        ///@notice Initialize arrays to hold post execution validation state.
        SandboxLimitOrder[] memory sandboxLimitOrders = new SandboxLimitOrder[](
            orderIdsLength
        );
        address[] memory orderOwners = new address[](orderIdsLength);
        uint256[] memory initialTokenInBalances = new uint256[](orderIdsLength);
        uint256[] memory initialTokenOutBalances = new uint256[](
            orderIdsLength
        );

        ///@notice Transfer the tokens from the order owners to the sandbox router contract.
        ///@dev This function is executed in the context of LimitOrderExecutor as a delegatecall.
        for (uint256 i = 0; i < orderIdsLength; ++i) {
            ///@notice Get the current order
            SandboxLimitOrder memory currentOrder = orderIdToSandboxLimitOrder[
                orderIds[i]
            ];

            orderOwners[i] = currentOrder.owner;

            if (currentOrder.orderId == bytes32(0)) {
                revert OrderDoesNotExist(orderIds[i]);
            }

            sandboxLimitOrders[i] = currentOrder;

            ///@notice Cache amountSpecifiedToFill for intermediate calculations
            uint128 amountSpecifiedToFill = fillAmounts[i];
            ///@notice Require the amountSpecifiedToFill is less than or equal to the amountInRemaining of the order.
            if (amountSpecifiedToFill > currentOrder.amountInRemaining) {
                revert FillAmountSpecifiedGreaterThanAmountRemaining(
                    amountSpecifiedToFill,
                    currentOrder.amountInRemaining,
                    currentOrder.orderId
                );
            }

            ///@notice Cache the the pre execution state of the order details
            initialTokenInBalances[i] = IERC20(currentOrder.tokenIn).balanceOf(
                currentOrder.owner
            );

            initialTokenOutBalances[i] = IERC20(currentOrder.tokenOut)
                .balanceOf(currentOrder.owner);
        }

        return (
            sandboxLimitOrders,
            orderOwners,
            initialTokenInBalances,
            initialTokenOutBalances
        );
    }

    function validateSandboxExecutionAndFillOrders(
        SandboxLimitOrder[] memory sandboxLimitOrders,
        uint128[] memory fillAmounts,
        uint256[] memory initialTokenInBalances,
        uint256[] memory initialTokenOutBalances
    ) internal {
        uint256 ordersLength = sandboxLimitOrders.length;
        ///@notice Verify all of the order owners have received their out amounts.
        for (uint256 i = 0; i < ordersLength; ++i) {
            SandboxLimitOrder memory currentOrder = sandboxLimitOrders[i];

            ///@notice Cache values for post execution assertions
            uint128 amountOutRequired = uint128(
                ConveyorMath.mul64U(
                    ConveyorMath.divUU(
                        currentOrder.amountOutRemaining,
                        currentOrder.amountInRemaining
                    ),
                    fillAmounts[i]
                )
            );

            uint256 initialTokenInBalance = initialTokenInBalances[i];
            uint256 initialTokenOutBalance = initialTokenOutBalances[i];

            uint256 currentTokenInBalance = IERC20(currentOrder.tokenIn)
                .balanceOf(currentOrder.owner);

            uint256 currentTokenOutBalance = IERC20(currentOrder.tokenOut)
                .balanceOf(currentOrder.owner);

            ///@notice Assert that the tokenIn balance is decremented by the fill amount exactly
            uint256 fillAmount = fillAmounts[i];
            if (initialTokenInBalance - currentTokenInBalance > fillAmount) {
                revert SandboxFillAmountNotSatisfied(
                    currentOrder.orderId,
                    initialTokenInBalance - currentTokenInBalance,
                    fillAmounts[i]
                );
            }

            ///@notice Assert that the tokenOut balance is greater than or equal to the amountOutRequired
            if (
                currentTokenOutBalance - initialTokenOutBalance <
                amountOutRequired
            ) {
                revert SandboxAmountOutRequiredNotSatisfied(
                    currentOrder.orderId,
                    currentTokenOutBalance - initialTokenOutBalance,
                    amountOutRequired
                );
            }

            ///@notice Update the sandboxLimitOrder after the execution requirements have been met.
            if (currentOrder.amountInRemaining == fillAmount) {
                _resolveCompletedOrder(
                    currentOrder.orderId,
                    OrderType.SandboxLimitOrder
                );
            } else {
                ///@notice Update the state of the order to parial filled quantities.
                _partialFillSandboxLimitOrder(
                    uint128(initialTokenInBalance - currentTokenInBalance),
                    uint128(currentTokenOutBalance - initialTokenOutBalance),
                    currentOrder.orderId
                );
            }
        }
    }

    /// @notice Function to refresh an order for another 30 days.
    /// @param orderIds - Array of order Ids to indicate which orders should be refreshed.
    function refreshOrder(bytes32[] memory orderIds) external nonReentrant {
        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Initialize totalRefreshFees;
        uint256 totalRefreshFees;

        ///@notice For each order in the orderIds array.
        for (uint256 i = 0; i < orderIds.length; ) {
            ///@notice Get the current orderId.
            bytes32 orderId = orderIds[i];

            ///@notice Cache the order in memory.
            (OrderType orderType, bytes memory orderBytes) = getOrderById(
                orderId
            );

            if (orderType == OrderType.None) {
                continue;
            } else {
                if (orderType == OrderType.LimitOrder) {
                    LimitOrder memory order = abi.decode(
                        orderBytes,
                        (LimitOrder)
                    );
                    totalRefreshFees += _refreshLimitOrder(order, gasPrice);
                } else if (orderType == OrderType.SandboxLimitOrder) {
                    SandboxLimitOrder memory order = abi.decode(
                        orderBytes,
                        (SandboxLimitOrder)
                    );
                    totalRefreshFees += _refreshSandboxLimitOrder(
                        order,
                        gasPrice
                    );
                }
            }

            unchecked {
                ++i;
            }
        }

        ///@notice Transfer the refresh fee to off-chain executor who called the function.
        safeTransferETH(msg.sender, totalRefreshFees);
    }

    ///@notice Internal helper function to refresh a Sandbox Limit Order.
    ///@param order - The Sandbox Limit Order to be refreshed.
    ///@param gasPrice - The current gasPrice from the Gas oracle.
    ///@return uint256 - The refresh fee to be compensated to the off-chain executor.
    function _refreshSandboxLimitOrder(
        SandboxLimitOrder memory order,
        uint256 gasPrice
    ) internal returns (uint256) {
        ///@notice Require that current timestamp is not past order expiration, otherwise cancel the order and continue the loop.
        if (block.timestamp > order.expirationTimestamp) {
            return _cancelSandboxLimitOrderViaExecutor(order);
        }

        ///@notice Check that the account has enough gas credits to refresh the order, otherwise, cancel the order and continue the loop.
        if (gasCreditBalance[order.owner] < REFRESH_FEE) {
            return _cancelSandboxLimitOrderViaExecutor(order);
        }

        ///@notice If the time elapsed since the last refresh is less than 30 days, continue to the next iteration in the loop.
        if (block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL) {
            return 0;
        }

        ///@notice Require that account has enough gas for order execution after the refresh, otherwise, cancel the order and continue the loop.
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    LIMIT_ORDER_EXECUTION_GAS_COST,
                    order.owner,
                    gasCreditBalance[order.owner] - REFRESH_FEE,
                    1 ///@dev Multiplier is set to 1 for refresh order
                )
            )
        ) {
            return _cancelSandboxLimitOrderViaExecutor(order);
        }

        ///@notice Decrement the order.owner's gas credit balance
        gasCreditBalance[order.owner] -= REFRESH_FEE;

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

        return REFRESH_FEE;
    }

    ///@notice Internal helper function to refresh a Limit Order.
    ///@param order - The Limit Order to be refreshed.
    ///@param gasPrice - The current gasPrice from the Gas oracle.
    ///@return executorFee - The fee to be compensated to the off-chain executor.
    function _refreshLimitOrder(LimitOrder memory order, uint256 gasPrice)
        internal
        returns (uint256 executorFee)
    {
        ///@notice Require that current timestamp is not past order expiration, otherwise cancel the order and continue the loop.
        if (block.timestamp > order.expirationTimestamp) {
            return _cancelLimitOrderViaExecutor(order);
        }

        ///@notice Check that the account has enough gas credits to refresh the order, otherwise, cancel the order and continue the loop.
        if (gasCreditBalance[order.owner] < REFRESH_FEE) {
            return _cancelLimitOrderViaExecutor(order);
        }

        ///@notice If the time elapsed since the last refresh is less than 30 days, continue to the next iteration in the loop.
        if (block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL) {
            return 0;
        }

        ///@notice Require that account has enough gas for order execution after the refresh, otherwise, cancel the order and continue the loop.
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    LIMIT_ORDER_EXECUTION_GAS_COST,
                    order.owner,
                    gasCreditBalance[order.owner] - REFRESH_FEE,
                    1 ///@dev Multiplier is set to 1 for refresh order
                )
            )
        ) {
            return _cancelLimitOrderViaExecutor(order);
        }

        ///@notice Decrement the order.owner's gas credit balance
        gasCreditBalance[order.owner] -= REFRESH_FEE;

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

    ///@notice Transfer ETH to a specific address and require that the call was successful.
    ///@param to - The address that should be sent Ether.
    ///@param amount - The amount of Ether that should be sent.
    function safeTransferETH(address to, uint256 amount) internal {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert ETHTransferFailed();
        }
    }

    /// @notice Function for off-chain executors to cancel an Order that does not have the minimum gas credit balance for order execution.
    /// @param orderId - Order Id of the order to cancel.
    /// @return success - Boolean to indicate if the order was successfully cancelled and compensation was sent to the off-chain executor.
    function validateAndCancelOrder(bytes32 orderId)
        external
        nonReentrant
        returns (bool success)
    {
        uint256 gasPrice = getGasPrice();

        (OrderType orderType, bytes memory orderBytes) = getOrderById(orderId);

        ///@notice Check if order exists, otherwise revert.
        if (orderType == OrderType.None) {
            revert OrderDoesNotExist(orderId);
        } else if (orderType == OrderType.LimitOrder) {
            LimitOrder memory limitOrder = abi.decode(orderBytes, (LimitOrder));

            ///@notice If the order owner does not have min gas credits, cancel the order
            if (
                !(
                    _hasMinGasCredits(
                        gasPrice,
                        LIMIT_ORDER_EXECUTION_GAS_COST,
                        limitOrder.owner,
                        gasCreditBalance[limitOrder.owner],
                        1 ///@dev Multiplier is set to 1
                    )
                )
            ) {
                ///@notice Remove the order from the limit order system.
                safeTransferETH(
                    msg.sender,
                    _cancelLimitOrderViaExecutor(limitOrder)
                );
                return true;
            }
        } else {
            SandboxLimitOrder memory sandboxLimitOrder = abi.decode(
                orderBytes,
                (SandboxLimitOrder)
            );

            ///@notice If the order owner does not have min gas credits, cancel the order
            if (
                !(
                    _hasMinGasCredits(
                        gasPrice,
                        SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST,
                        sandboxLimitOrder.owner,
                        gasCreditBalance[sandboxLimitOrder.owner],
                        1 ///@dev Multiplier is set to 1
                    )
                )
            ) {
                ///@notice Remove the order from the limit order system.

                safeTransferETH(
                    msg.sender,
                    _cancelSandboxLimitOrderViaExecutor(sandboxLimitOrder)
                );

                return true;
            }
        }

        return false;
    }

    /// @notice Internal helper function to cancel an order. This function is only called after cancel order validation.
    /// @param order - The order to cancel.
    /// @return success - Boolean to indicate if the order was successfully cancelled.
    function _cancelLimitOrderViaExecutor(LimitOrder memory order)
        internal
        returns (uint256)
    {
        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Get the minimum gas credits needed for a single order
        uint256 executorFee = gasPrice * LIMIT_ORDER_EXECUTION_GAS_COST;

        ///@notice Remove the order from the limit order system.
        _removeOrderFromSystem(order.orderId, OrderType.LimitOrder);

        uint256 orderOwnerGasCreditBalance = gasCreditBalance[order.owner];

        ///@notice If the order owner's gas credit balance is greater than the minimum needed for a single order, send the executor the minimumGasCreditsForSingleOrder.
        if (orderOwnerGasCreditBalance > executorFee) {
            ///@notice Decrement from the order owner's gas credit balance.
            gasCreditBalance[order.owner] -= executorFee;
        } else {
            ///@notice Otherwise, decrement the entire gas credit balance.
            gasCreditBalance[order.owner] -= orderOwnerGasCreditBalance;
            executorFee = orderOwnerGasCreditBalance;
        }

        ///@notice Emit an order cancelled event to notify the off-chain exectors.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);

        return executorFee;
    }

    ///@notice Remove an order from the system if the order exists.
    function _cancelSandboxLimitOrderViaExecutor(SandboxLimitOrder memory order)
        internal
        returns (uint256)
    {
        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Get the minimum gas credits needed for a single order
        uint256 executorFee = gasPrice * SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST;

        ///@notice Remove the order from the limit order system.
        _removeOrderFromSystem(order.orderId, OrderType.SandboxLimitOrder);

        uint256 orderOwnerGasCreditBalance = gasCreditBalance[order.owner];

        ///@notice If the order owner's gas credit balance is greater than the minimum needed for a single order, send the executor the minimumGasCreditsForSingleOrder.
        if (orderOwnerGasCreditBalance > executorFee) {
            ///@notice Decrement from the order owner's gas credit balance.
            gasCreditBalance[order.owner] -= executorFee;
        } else {
            ///@notice Otherwise, decrement the entire gas credit balance.
            gasCreditBalance[order.owner] -= orderOwnerGasCreditBalance;
            executorFee = orderOwnerGasCreditBalance;
        }

        ///@notice Emit an order cancelled event to notify the off-chain exectors.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);

        return executorFee;
    }

    ///@notice Function to validate the congruency of an array of orders.
    ///@param orders Array of orders to be validated
    function _validateOrderSequencing(LimitOrder[] memory orders)
        internal
        pure
    {
        ///@notice Iterate through the length of orders -1.
        for (uint256 i = 0; i < orders.length - 1; i++) {
            ///@notice Cache order at index i, and i+1
            LimitOrder memory currentOrder = orders[i];
            LimitOrder memory nextOrder = orders[i + 1];

            ///@notice Check if the current order is less than or equal to the next order
            if (currentOrder.quantity > nextOrder.quantity) {
                revert InvalidBatchOrder();
            }

            ///@notice Check if the token in is the same for the next order
            if (currentOrder.tokenIn != nextOrder.tokenIn) {
                revert IncongruentInputTokenInBatch();
            }

            ///@notice Check if the stoploss status is the same for the next order
            if (currentOrder.stoploss != nextOrder.stoploss) {
                revert IncongruentStoplossStatus();
            }

            ///@notice Check if the token out is the same for the next order
            if (currentOrder.tokenOut != nextOrder.tokenOut) {
                revert IncongruentOutputTokenInBatch();
            }

            ///@notice Check if the buy status is the same for the next order
            if (currentOrder.buy != nextOrder.buy) {
                revert IncongruentBuySellStatusInBatch();
            }

            ///@notice Check if the tax status is the same for the next order
            if (currentOrder.taxed != nextOrder.taxed) {
                revert IncongruentTaxedTokenInBatch();
            }

            ///@notice Check if the fee in is the same for the next order
            if (currentOrder.feeIn != nextOrder.feeIn) {
                revert IncongruentFeeInInBatch();
            }

            ///@notice Check if the fee out is the same for the next order
            if (currentOrder.feeOut != nextOrder.feeOut) {
                revert IncongruentFeeOutInBatch();
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
        ///@notice Require gas price to avoid verifier's delimma.
        /*
        A verifier's delimma occurs when there is not a sufficient incentive for a player within a given system to carry out an action.
        Within the context of the Conveyor Finance Limit Order Protocol, if an MEV searcher were to listen to the mempool for execution 
        transactions and frontrun the off-chain execution, there would be no incentive for the off-chain executor to run the computations 
        to identify when a limit order is eligible when they could simply listen and front run other transactions. To solve for this, the protocol
        requires that the gas price of the execution transaction is exactly the price of the Chainlink gas oracle price + 25%.

        The Chainlink oracle's gas price can deviate from the real competitive gas price by 25% before an update. If the gas oracle is 25% lower than
        the competitive gas price, the execution transaction gas price is still priced at a competitive rate. If the gas oracle is 25% higher than
        the competitive gas price, the execution gas price will be faster than the current competitive rate. At all times, the execution transaction's gas price will be competitve.

        Since the gas price is an exact value, searchers can not monitor the mempool and front run the transaction with a higher gas price. This effecively eliminates the verifier's delimma
        from the protocol, incentivizing the off-chain executor to be the first to compute the execution opportunity and submit a transaction. Any while miners/block builders can order a block as they desire
        there is not an incentive to order one transaction in front of the other, allowing the first to submit the transaction to be included in most cases.
        */

        uint256 gasPrice = getGasPrice();
        if (tx.gasprice > gasPrice) {
            revert VerifierDilemmaGasPrice();
        }

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
            ///@notice Revert if the order does not exist in the contract.
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
            (totalBeaconReward, totalConveyorReward) = ILimitOrderExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToWethOrders(orders);
        } else {
            ///@notice Otherwise, if the tokenOut is not weth, continue with a regular token to token execution.
            (totalBeaconReward, totalConveyorReward) = ILimitOrderExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToTokenOrders(orders);
        }

        ///@notice Get the array of order owners.
        address[] memory orderOwners = getOrderOwners(orders);

        ///@notice Iterate through all orderIds in the batch and delete the orders from queue post execution.
        for (uint256 i = 0; i < orderIds.length; ) {
            bytes32 orderId = orderIds[i];
            ///@notice Mark the order as resolved from the system.
            _resolveCompletedOrder(orderId, OrderType.LimitOrder);

            ///@notice Mark order as fulfilled in addressToFufilledOrderIds mapping
            addressToFufilledOrderIds[orderOwners[i]][orderIds[i]] = true;

            unchecked {
                ++i;
            }
        }

        ///@notice Emit an order fufilled event to notify the off-chain executors.
        emit OrderFufilled(orderIds);

        ///@notice Calculate the execution gas compensation.
        uint256 executionGasCompensation = calculateExecutionGasCompensation(
            gasPrice,
            orderOwners,
            OrderType.LimitOrder
        );

        ///@notice Transfer the reward to the off-chain executor.
        safeTransferETH(msg.sender, executionGasCompensation);
    }

    ///@notice Function to return an array of order owners.
    ///@param orders - Array of orders.
    ///@return orderOwners - An array of order owners in the orders array.
    function getOrderOwners(LimitOrder[] memory orders)
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
            revert UnauthorizedCaller();
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
    function calculateExecutionGasConsumed(
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

        if (orderType == OrderType.LimitOrder) {
            ///@notice If the execution gas is greater than the max compensation, set the compensation to the max
            uint256 maxExecutionCompensation = LIMIT_ORDER_EXECUTION_GAS_COST *
                numberOfOrders *
                gasPrice;
            if (executionGasConsumed > maxExecutionCompensation) {
                executionGasConsumed = maxExecutionCompensation;
            }
        } else {
            ///@notice If the execution gas is greater than the max compensation, set the compensation to the max
            uint256 maxExecutionCompensation = SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST *
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
    function calculateExecutionGasCompensation(
        uint256 gasPrice,
        address[] memory orderOwners,
        OrderType orderType
    ) internal returns (uint256 gasExecutionCompensation) {
        uint256 orderOwnersLength = orderOwners.length;

        ///@notice Decrement gas credit balances for each order owner
        uint256 executionGasConsumed = calculateExecutionGasConsumed(
            gasPrice,
            orderOwners.length,
            orderType
        );

        uint256 gasDecrementValue = executionGasConsumed / orderOwnersLength;

        ///@notice Unchecked for gas efficiency
        unchecked {
            for (uint256 i = 0; i < orderOwnersLength; ) {
                ///@notice Adjust the order owner's gas credit balance
                uint256 ownerGasCreditBalance = gasCreditBalance[
                    orderOwners[i]
                ];

                if (ownerGasCreditBalance >= gasDecrementValue) {
                    gasCreditBalance[orderOwners[i]] -= gasDecrementValue;
                    gasExecutionCompensation += gasDecrementValue;
                } else {
                    gasCreditBalance[orderOwners[i]] -= ownerGasCreditBalance;
                    gasExecutionCompensation += ownerGasCreditBalance;
                }

                ++i;
            }
        }
    }
}
