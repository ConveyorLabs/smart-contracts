// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./OrderBook.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/token/IWETH.sol";
import "./SwapRouter.sol";
import "./interfaces/ILimitOrderQuoter.sol";
import "./interfaces/ILimitOrderExecutor.sol";

/// @title LimitOrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract LimitOrderRouter is OrderBook {
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
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;
        _;
        reentrancyStatus = false;
    }

    // ========================================= Constants  =============================================

    ///@notice Interval that determines when an order is eligible for refresh. The interval is set to 30 days represented in Unix time.
    uint256 constant REFRESH_INTERVAL = 2592000;

    ///@notice The fee paid every time an order is refreshed by an off-chain executor to keep the order active within the system.
    uint256 constant REFRESH_FEE = 20000000000000000;

    // ========================================= State Variables =============================================

    ///@notice Boolean responsible for indicating if a function has been entered when the nonReentrant modifier is used.
    bool reentrancyStatus = false;

    ///@notice Mapping to hold gas credit balances for accounts.
    mapping(address => uint256) public gasCreditBalance;

    ///@notice The execution cost of fufilling a standard ERC20 swap from tokenIn to tokenOut
    uint256 public constant ORDER_EXECUTION_GAS_COST = 300000;

    ///@notice State variable to track the amount of gas initally alloted during executeOrders.
    uint256 initialTxGas;

    ///@notice Temporary owner storage variable when transferring ownership of the contract.
    address tempOwner;

    ///@notice The owner of the Order Router contract
    ///@dev The contract owner can remove the owner funds from the contract, and transfer ownership of the contract.
    address owner;

    address immutable WETH;

    address immutable LIMIT_ORDER_EXECUTOR;

    // ========================================= Constructor =============================================

    ///@param _gasOracle - Address of the ChainLink fast gas oracle.
    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _limitOrderExecutor - Address of the USD pegged token for the chain.
    constructor(
        address _gasOracle,
        address _weth,
        address _limitOrderExecutor
    ) OrderBook(_gasOracle, _limitOrderExecutor) {
        require(
            _limitOrderExecutor != address(0),
            "Invalid LimitOrderExecutor address"
        );
        require(_weth != address(0), "Invalid weth address");
        WETH = _weth;
        owner = msg.sender;

        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
    }

    // ========================================= Events  =============================================

    ///@notice Event that notifies off-chain executors when gas credits are added or withdrawn from an account's balance.
    event GasCreditEvent(address indexed sender, uint256 indexed balance);

    ///@notice Event that notifies off-chain executors when an order has been refreshed.
    event OrderRefreshed(
        bytes32 indexed orderId,
        uint32 indexed lastRefreshTimestamp,
        uint32 indexed expirationTimestamp
    );

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
                    ORDER_EXECUTION_GAS_COST,
                    msg.sender,
                    gasCreditBalance[msg.sender] - value
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
            Order memory order = getOrderById(orderId);

            ///@notice Check if order exists, otherwise revert.
            if (order.owner == address(0)) {
                revert OrderDoesNotExist(orderId);
            }

            ///@notice Require that current timestamp is not past order expiration, otherwise cancel the order and continue the loop.
            if (block.timestamp > order.expirationTimestamp) {
                _cancelOrder(order);

                unchecked {
                    ++i;
                }

                continue;
            }

            ///@notice Check that the account has enough gas credits to refresh the order, otherwise, cancel the order and continue the loop.
            if (gasCreditBalance[order.owner] < REFRESH_FEE) {
                _cancelOrder(order);

                unchecked {
                    ++i;
                }

                continue;
            }

            ///@notice If the time elapsed since the last refresh is less than 30 days, continue to the next iteration in the loop.
            if (
                block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL
            ) {
                unchecked {
                    ++i;
                }

                continue;
            }

            ///@notice Require that account has enough gas for order execution after the refresh, otherwise, cancel the order and continue the loop.
            if (
                !(
                    _hasMinGasCredits(
                        gasPrice,
                        ORDER_EXECUTION_GAS_COST,
                        order.owner,
                        gasCreditBalance[order.owner] - REFRESH_FEE
                    )
                )
            ) {
                _cancelOrder(order);

                unchecked {
                    ++i;
                }

                continue;
            }

            ///@notice Accumulate the REFRESH_FEE.
            totalRefreshFees += REFRESH_FEE;

            ///@notice Decrement the order.owner's gas credit balance
            gasCreditBalance[order.owner] -= REFRESH_FEE;

            ///@notice update the order's last refresh timestamp
            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
            orderIdToOrder[orderId].lastRefreshTimestamp = uint32(
                block.timestamp % (2**32 - 1)
            );

            ///@notice Emit an event to notify the off-chain executors that the order has been refreshed.
            emit OrderRefreshed(
                orderId,
                order.lastRefreshTimestamp,
                order.expirationTimestamp
            );

            unchecked {
                ++i;
            }
        }

        ///@notice Transfer the refresh fee to off-chain executor who called the function.
        safeTransferETH(msg.sender, totalRefreshFees);
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
        ///@notice Cache the order to run validation checks before cancellation.
        Order memory order = orderIdToOrder[orderId];

        ///@notice Check if order exists, otherwise revert.
        if (order.owner == address(0)) {
            revert OrderDoesNotExist(orderId);
        }

        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Check if the account has the minimum gas credits for
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    ORDER_EXECUTION_GAS_COST,
                    order.owner,
                    gasCreditBalance[order.owner]
                )
            )
        ) {
            ///@notice Remove the order from the limit order system.
            _cancelOrder(order);

            return true;
        }
        return false;
    }

    /// @notice Internal helper function to cancel an order. This function is only called after cancel order validation.
    /// @param order - The order to cancel.
    /// @return success - Boolean to indicate if the order was successfully cancelled.
    function _cancelOrder(Order memory order) internal returns (bool success) {
        ///@notice Get the current gas price from the v3 Aggregator.
        uint256 gasPrice = getGasPrice();

        ///@notice Get the minimum gas credits needed for a single order
        uint256 minimumGasCreditsForSingleOrder = gasPrice *
            ORDER_EXECUTION_GAS_COST;

        ///@notice Remove the order from the limit order system.
        _removeOrderFromSystem(order);

        uint256 orderOwnerGasCreditBalance = gasCreditBalance[order.owner];

        ///@notice If the order owner's gas credit balance is greater than the minimum needed for a single order, send the executor the minimumGasCreditsForSingleOrder.
        if (orderOwnerGasCreditBalance > minimumGasCreditsForSingleOrder) {
            ///@notice Decrement from the order owner's gas credit balance.
            gasCreditBalance[order.owner] -= minimumGasCreditsForSingleOrder;

            ///@notice Send the off-chain executor the reward for cancelling the order.
            safeTransferETH(msg.sender, minimumGasCreditsForSingleOrder);
        } else {
            ///@notice Otherwise, decrement the entire gas credit balance.
            gasCreditBalance[order.owner] -= orderOwnerGasCreditBalance;
            ///@notice Send the off-chain executor the reward for cancelling the order.
            safeTransferETH(msg.sender, orderOwnerGasCreditBalance);
        }

        ///@notice Emit an order cancelled event to notify the off-chain exectors.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);

        return true;
    }

    ///@notice Function to validate the congruency of an array of orders.
    ///@param orders Array of orders to be validated
    function _validateOrderSequencing(Order[] memory orders) internal pure {
        ///@notice Iterate through the length of orders -1.
        for (uint256 i = 0; i < orders.length - 1; i++) {
            ///@notice Cache order at index i, and i+1
            Order memory currentOrder = orders[i];
            Order memory nextOrder = orders[i + 1];

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
    function executeOrders(bytes32[] calldata orderIds) external nonReentrant {
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
        Order[] memory orders = new Order[](orderIds.length);
        address[] memory orderOwners = new address[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getOrderById(orderIds[i]);
            orderOwners[i]= orders[i].owner;
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

        ///@notice If the order is not taxed and the tokenOut on the order is Weth
        if (orders[0].tokenOut == WETH) {
            ILimitOrderExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToWethOrders(orders);
        } else {
            ///@notice Otherwise, if the tokenOut is not weth, continue with a regular token to token execution.
            ILimitOrderExecutor(
                LIMIT_ORDER_EXECUTOR
            ).executeTokenToTokenOrders(orders);
        }

        ///@notice Iterate through all orderIds in the batch and delete the orders from queue post execution.
        for (uint256 i = 0; i < orderIds.length; ) {
            bytes32 orderId = orderIds[i];
            ///@notice Mark the order as resolved from the system.
            _resolveCompletedOrder(orderId);

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
            orderOwners
        );

        ///@notice Transfer the reward to the off-chain executor.
        safeTransferETH(msg.sender, executionGasCompensation);
    }


    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if (msg.sender != tempOwner) {
            revert UnauthorizedCaller();
        }
        owner = msg.sender;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        tempOwner = newOwner;
    }

    ///@notice Function to calculate the execution gas consumed during executeOrders
    ///@return executionGasConsumed - The amount of gas consumed.
    function calculateExecutionGasConsumed(uint256 gasPrice)
        internal
        view
        returns (uint256 executionGasConsumed)
    {
        assembly {
            executionGasConsumed := mul(
                gasPrice,
                sub(sload(initialTxGas.slot), gas())
            )
        }
    }

    ///@notice Function to adjust order owner's gas credit balance and calaculate the compensation to be paid to the executor.
    ///@param orderOwners - The order owners in the batch.
    ///@return gasExecutionCompensation - The amount to be paid to the off-chain executor for execution gas.
    function calculateExecutionGasCompensation(
        uint256 gasPrice,
        address[] memory orderOwners
    ) internal returns (uint256 gasExecutionCompensation) {
        uint256 orderOwnersLength = orderOwners.length;

        ///@notice Decrement gas credit balances for each order owner
        uint256 executionGasConsumed = calculateExecutionGasConsumed(gasPrice);
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
