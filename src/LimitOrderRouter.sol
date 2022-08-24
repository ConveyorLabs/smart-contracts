// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "./OrderBook.sol";
import "./OrderRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";

/// @title OrderRouter
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


    ///@notice Conveyor funds balance in the contract.
    uint256 conveyorBalance;

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

    ///@notice The wrapped native token address for the chain.
    address immutable WETH;

    ///@notice The USD pegged token address for the chain.
    address immutable USDC;

    ///@notice The execution cost of fufilling a standard ERC20 swap from tokenIn to tokenOut
    uint256 immutable ORDER_EXECUTION_GAS_COST;

    ///@notice State variable to track the amount of gas initally alloted during executeOrders.
    uint256 initialTxGas;

    ///@notice Temporary owner storage variable when transferring ownership of the contract. 
    address tempOwner;


    //TODO: Change this to contractOwner to not get mixed up with orderOwner
    ///@notice The owner of the Order Router contract
    ///@dev The contract owner can remove the owner funds from the contract, and transfer ownership of the contract. 
    address owner;



    // ========================================= Constructor =============================================

    ///@param _gasOracle - Address of the ChainLink fast gas oracle.
    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _executionCost - The execution cost of fufilling a standard ERC20 swap from tokenIn to tokenOut
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        uint256 _executionCost
    )
        OrderBook(_gasOracle)
    {
        WETH = _weth;
        USDC = _usdc;
        ORDER_EXECUTION_GAS_COST = _executionCost;
        owner = msg.sender;
    }

    // ========================================= Events  =============================================

    ///@notice Event that notifies off-chain executors when gas credits are added or withdrawn from an account's balance.
    event GasCreditEvent(
        bool indexed deposit,
        address indexed sender,
        uint256 amount
    );

    ///@notice Event that notifies off-chain executors when an order has been refreshed.
    event OrderRefreshed(
        bytes32 indexed orderId,
        uint32 lastRefreshTimestamp,
        uint32 expirationTimestamp
    );

    // ========================================= FUNCTIONS =============================================

    //------------Gas Credit Functions------------------------

    /// @notice Function to deposit gas credits.
    /// @return success - Boolean that indicates if the deposit completed successfully.
    function depositGasCredits() public payable returns (bool success) {
        ///@notice Increment the gas credit balance for the user by the msg.value
        gasCreditBalance[msg.sender] += msg.value;

        ///@notice Emit a gas credit event notifying the off-chain executors that gas credits have been deposited.
        emit GasCreditEvent(true, msg.sender, msg.value);

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
        gasCreditBalance[msg.sender] = gasCreditBalance[msg.sender] - value;

        ///@notice Transfer the withdraw amount to the account.
        safeTransferETH(msg.sender, value);

        return true;
    }

    /// @notice Function to refresh an order for another 30 days.
    /// @param orderIds - Array of order Ids to indicate which orders should be refreshed.
    function refreshOrder(bytes32[] memory orderIds) external nonReentrant {
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

            ///@notice Get the current gas price from the v3 Aggregator.
            uint256 gasPrice = getGasPrice();

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

            ///@notice Transfer the refresh fee to off-chain executor who called the function.
            safeTransferETH(msg.sender, REFRESH_FEE);

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

        ///@notice Get the minimum gas credits needed for a single order
        uint256 minimumGasCreditsForSingleOrder = gasPrice *
            ORDER_EXECUTION_GAS_COST;

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

            ///@notice Decrement from the order owner's gas credit balance.
            gasCreditBalance[order.owner] -= minimumGasCreditsForSingleOrder;

            ///@notice Send the off-chain executor the reward for cancelling the order.
            safeTransferETH(msg.sender, minimumGasCreditsForSingleOrder);

            ///@notice Emit an order cancelled event to notify the off-chain exectors.
            bytes32[] memory orderIds = new bytes32[](1);
            orderIds[0] = order.orderId;
            emit OrderCancelled(orderIds);

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

            ///@notice Check if the token in is the same for the last order
            if (currentOrder.tokenIn != nextOrder.tokenIn) {
                revert IncongruentInputTokenInBatch();
            }

            ///@notice Check if the token out is the same for the last order
            if (currentOrder.tokenOut != nextOrder.tokenOut) {
                revert IncongruentOutputTokenInBatch();
            }

            ///@notice Check if the token tax status is the same for the last order
            if (currentOrder.buy != nextOrder.buy) {
                revert IncongruentBuySellStatusInBatch();
            }

            ///@notice Check if the token tax status is the same for the last order
            if (currentOrder.taxed != nextOrder.taxed) {
                revert IncongruentTaxedTokenInBatch();
            }
        }
    }

    // ==================== Order Execution Functions =========================

    ///@notice This function is called by off-chain executors, passing in an array of orderIds to execute a specific batch of orders.
    /// @param orderIds - Array of orderIds to indicate which orders should be executed.
    function executeOrders(bytes32[] calldata orderIds) external onlyEOA {
        // Update the initial gas balance.
        assembly {
            sstore(initialTxGas.slot, gas())
        }

        ///@notice Get all of the orders by orderId and add them to a temporary orders array
        Order[] memory orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getOrderById(orderIds[i]);

            unchecked {
                ++i;
            }
        }

        ///@notice If the length of orders array is greater than a single order, than validate the order sequencing.
        if (orders.length > 1) {
            ///@notice Validate that the orders in the batch are passed in with increasing quantity.
            _validateOrderSequencing(orders);
        }

        ///@notice Check if the order contains any taxed tokens.
        if (orders[0].taxed == true) {
            ///@notice If the tokenOut on the order is Weth
            if (orders[0].tokenOut == WETH) {
                ///@notice If the length of the orders array > 1, execute multiple TokenToWeth taxed orders. 
                if(orders.length>1){

                    //TODO: _executeTokenToWethTaxedOrders(orders);
                ///@notice If the length ==1, execute a single TokenToWeth taxed order. 
                }else{
                      //TODO: _executeTokenToWethOrderSingle(orders);
                }
            } else {
                ///@notice If the length of the orders array > 1, execute multiple TokenToToken taxed orders. 
                if(orders.length>1){
                    ///@notice Otherwise, if the tokenOut is not Weth and the order is a taxed order.
                      //TODO: _executeTokenToTokenTaxedOrders(orders);
                ///@notice If the length ==1, execute a single TokenToToken taxed order. 
                }else{
                      //TODO: _executeTokenToTokenOrderSingle(orders);
                }   
                
            }
        } else {
            ///@notice If the order is not taxed and the tokenOut on the order is Weth
            if (orders[0].tokenOut == WETH) {
                ///@notice If the length of the orders array > 1, execute multiple TokenToWeth taxed orders. 
                if (orders.length > 1) {
                      //TODO: _executeTokenToWethOrders(orders);
                ///@notice If the length ==1, execute a single TokenToWeth taxed order. 
                } else {
                      //TODO: _executeTokenToWethOrderSingle(orders);
                }
            } else {
                ///@notice If the length of the orders array > 1, execute multiple TokenToToken orders. 
                if (orders.length > 1) {
                    ///@notice Otherwise, if the tokenOut is not weth, continue with a regular token to token execution.
                      //TODO: _executeTokenToTokenOrders(orders);
                ///@notice If the length ==1, execute a single TokenToToken order. 
                } else {
                      //TODO: _executeTokenToTokenOrderSingle(orders);
                }
            }
        }

        //TODO: Handle gas credit values
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner nonReentrant {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
    }

    

    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if(msg.sender != tempOwner){
            revert UnauthorizedCaller();
        }
        owner = msg.sender;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if(owner== address(0)){
            revert InvalidAddress();
        }
        tempOwner = newOwner;

    }

    ///@notice Function to calculate the execution gas consumed during executeOrders
    ///@return executionGasConsumed - The amount of gas consumed.
    function calculateExecutionGasConsumed()
        internal
        view
        returns (uint256 executionGasConsumed)
    {
        assembly {
            executionGasConsumed := sub(sload(initialTxGas.slot), gas())
        }
    }

    ///@notice Function to adjust order owner's gas credit balance and calaculate the compensation to be paid to the executor.
    ///@param orderOwners - The order owners in the batch.
    ///@return gasExecutionCompensation - The amount to be paid to the off-chain executor for execution gas.
    function calculateExecutionGasCompensation(address[] memory orderOwners)
        internal
        returns (uint256 gasExecutionCompensation)
    {
        uint256 orderOwnersLength = orderOwners.length;

        ///@notice Decrement gas credit balances for each order owner
        uint256 executionGasConsumed = calculateExecutionGasConsumed();
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


    ///@notice Transfer ETH to a specific address and require that the call was successful.
    ///@param to - The address that should be sent Ether.
    ///@param amount - The amount of Ether that should be sent.
    function safeTransferETH(address to, uint256 amount) public {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert ETHTransferFailed();
        }
    }
}