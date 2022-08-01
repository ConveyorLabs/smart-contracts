// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/interfaces/token/IERC20.sol";
import "./GasOracle.sol";
import "./ConveyorErrors.sol";

contract OrderBook is GasOracle {
    //----------------------Constructor------------------------------------//

    constructor(address _gasOracle) GasOracle(_gasOracle) {}

    //----------------------Events------------------------------------//
    /**@notice Event that is emitted when a new order is placed. For each order that is placed, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderPlaced(bytes32[] indexed orderIds);

    /**@notice Event that is emitted when an order is cancelled. For each order that is cancelled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderCancelled(bytes32[] indexed orderIds);

    /**@notice Event that is emitted when a new order is update. For each order that is updated, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderUpdated(bytes32[] indexed orderIds);

    /**@notice Event that is emitted when an order is filled. For each order that is filled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderFilled(bytes32[] indexed orderIds);

    //----------------------Structs------------------------------------//

    ///@notice Struct containing Order details for any limit order
    ///@param buy - Indicates if the order is a buy or sell
    ///@param taxed - Indicates if the tokenIn or tokenOut is taxed. This will be set to true if one or both tokens are taxed.
    ///@param lastRefreshTimestamp - Unix timestamp representing the last time the order was refreshed.
    ///@param expirationTimestamp - Unix timestamp representing when the order should expire.
    ///@param feeIn - The Univ3 liquidity pool fee for the tokenIn/Weth pairing.
    ///@param feeOut - The Univ3 liquidity pool fee for the tokenOut/Weth pairing.
    ///@param price - The execution price representing the spot price of tokenIn/tokenOut that the order should be filled at. This is represented as a 64x64 fixed point number.
    ///@param amountOutMin - The minimum amount out that the order owner is willing to accept. This value is represented in tokenOut.
    ///@param quantity - The amount of tokenIn that the order use as the amountIn value for the swap (represented in amount * 10**tokenInDecimals).
    ///@param owner - The owner of the order. This is set to the msg.sender at order placement.
    ///@param tokenIn - The tokenIn for the order.
    ///@param tokenOut - The tokenOut for the order.
    ///@param orderId - Unique identifier for the order.
    struct Order {
        bool buy;
        bool taxed;
        uint32 lastRefreshTimestamp;
        uint32 expirationTimestamp;
        uint24 feeIn;
        uint24 feeOut;
        uint16 taxIn;
        uint128 price;
        uint128 amountOutMin;
        uint128 quantity;
        address owner;
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
    }

    //----------------------State Structures------------------------------------//

    ///@notice Mapping from an orderId to its order.
    mapping(bytes32 => Order) public orderIdToOrder;

    ///@notice Mapping to find the total orders quantity for a specific token, for an individual account
    ///@notice The key is represented as: keccak256(abi.encode(owner, token));
    mapping(bytes32 => uint256) public totalOrdersQuantity;

    ///@notice Mapping to check if an order exists, as well as get all the orders for an individual account.
    ///@dev ownerAddress -> orderId -> bool
    mapping(address => mapping(bytes32 => bool)) public addressToOrderIds;

    ///@notice Mapping to store the number of total orders for an individual account
    mapping(address => uint256) public totalOrdersPerAddress;

    ///@notice The orderNonce is a unique value is used to create orderIds and increments every time a new order is placed.
    uint256 orderNonce;

    //----------------------Functions------------------------------------//

    ///@notice This function gets an order by the orderId. If the order does not exist, the order returned will be empty.
    function getOrderById(bytes32 orderId)
        public
        view
        returns (Order memory order)
    {
        order = orderIdToOrder[orderId];
        return order;
    }

    ///@notice Places a new order (or group of orders) into the system.
    ///@param orderGroup - List of newly created orders to be placed.
    /// @return orderIds - Returns a list of orderIds corresponding to the newly placed orders.
    function placeOrder(Order[] calldata orderGroup)
        public
        returns (bytes32[] memory)
    {
        ///@notice Value responsible for keeping track of array indices when placing a group of new orders
        uint256 orderIdIndex;

        ///@notice Initialize a new list of bytes32 to store the newly created orderIds.
        bytes32[] memory orderIds = new bytes32[](orderGroup.length);

        ///@notice Initialize the orderToken for the newly placed orders.
        /**@dev When placing a new group of orders, the tokenIn and tokenOut must be the same on each order. New orders are placed
        this way to securely validate if the msg.sender has the tokens required when placing a new order as well as enough gas credits
        to cover order execution cost.
        */
        address orderToken = orderGroup[0].tokenIn;

        ///@notice Get the value of all orders on the orderToken that are currently placed for the msg.sender.
        uint256 updatedTotalOrdersValue = _getTotalOrdersValue(orderToken);

        ///@notice Get the current balance of the orderToken that the msg.sender has in their account.
        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        ///@notice For each order within the list of orders passed into the function.
        for (uint256 i = 0; i < orderGroup.length; ) {
            ///@notice Get the order details from the orderGroup.
            Order memory newOrder = orderGroup[i];

            ///@notice Increment the total value of orders by the quantity of the new order
            updatedTotalOrdersValue += newOrder.quantity;

            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
            if (!(orderToken == newOrder.tokenIn)) {
                revert IncongruentTokenInOrderGroup();
            }

            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
            if (tokenBalance < updatedTotalOrdersValue) {
                revert InsufficientWalletBalance();
            }

            ///@notice Create a new orderId from the orderNonce and current block timestamp
            bytes32 orderId = keccak256(
                abi.encode(orderNonce, block.timestamp)
            );

            ///@notice increment the orderNonce
            /**@dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the 
            orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
            */
            unchecked {
                ++orderNonce;
            }

            ///@notice Set the new order's owner to the msg.sender
            newOrder.owner = msg.sender;

            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
            newOrder.orderId = orderId;

            ///@notice Add the newly created order to the orderIdToOrder mapping
            orderIdToOrder[orderId] = newOrder;

            ///@notice Add the orderId to the addressToOrderIds mapping
            addressToOrderIds[msg.sender][orderId] = true;

            ///@notice Increment the total orders per address for the msg.sender
            ++totalOrdersPerAddress[msg.sender];

            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;

            unchecked {
                ++i;
            }
        }

        ///@notice Update the total orders value on the orderToken for the msg.sender.
        updateTotalOrdersQuantity(
            orderToken,
            msg.sender,
            updatedTotalOrdersValue
        );

        ///@notice Get the total amount approved for the ConveyorLimitOrder contract to spend on the orderToken.
        uint256 totalApprovedQuantity = IERC20(orderToken).allowance(
            msg.sender,
            address(this)
        );

        ///@notice If the total approved quantity is less than the updatedTotalOrdersValue, revert.
        if (totalApprovedQuantity < updatedTotalOrdersValue) {
            revert InsufficientAllowanceForOrderPlacement();
        }

        ///@notice Emit an OrderPlaced event to notify the off-chain executors that a new order has been placed.
        emit OrderPlaced(orderIds);

        return orderIds;
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    function updateOrder(Order calldata newOrder) public {
        //check if the old order exists

        bool orderExists = addressToOrderIds[msg.sender][newOrder.orderId];

        if (!orderExists) {
            revert OrderDoesNotExist(newOrder.orderId);
        }

        Order memory oldOrder = orderIdToOrder[newOrder.orderId];

        ///TODO: make this more efficient and check if new order > old order, then increment the difference else decrement the difference

        //Decrement oldOrder Quantity from totalOrdersQuantity
        //Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            oldOrder.tokenIn,
            msg.sender,
            oldOrder.quantity
        );
        //TODO: get total order sum and make sure that the user has the balance for the new order

        //update the order
        orderIdToOrder[oldOrder.orderId] = newOrder;

        //Update totalOrdersQuantity to new order quantity
        incrementTotalOrdersQuantity(
            newOrder.tokenIn,
            msg.sender,
            newOrder.quantity
        );

        //emit an updated order event
        //TODO: do this in assembly
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = newOrder.orderId;
        emit OrderUpdated(orderIds);
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    function _updateOrder(Order memory newOrder, address owner) internal {
        //check if the old order exists

        bool orderExists = addressToOrderIds[owner][newOrder.orderId];

        if (!orderExists) {
            revert OrderDoesNotExist(newOrder.orderId);
        }

        Order memory oldOrder = orderIdToOrder[newOrder.orderId];

        ///TODO: make this more efficient and check if new order > old order, then increment the difference else decrement the difference

        //Decrement oldOrder Quantity from totalOrdersQuantity
        //Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            oldOrder.tokenIn,
            owner,
            oldOrder.quantity
        );
        //TODO: get total order sum and make sure that the user has the balance for the new order

        //update the order
        orderIdToOrder[oldOrder.orderId] = newOrder;

        //Update totalOrdersQuantity to new order quantity
        incrementTotalOrdersQuantity(
            newOrder.tokenIn,
            owner,
            newOrder.quantity
        );

        //emit an updated order event
        //TODO: do this in assembly
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = newOrder.orderId;
        emit OrderUpdated(orderIds);
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    /// @param orderId the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(bytes32 orderId) public {
        /// Check if order exists in active orders. Revert if order does not exist
        bool orderExists = addressToOrderIds[msg.sender][orderId];

        if (!orderExists) {
            revert OrderDoesNotExist(orderId);
        }

        Order memory order = orderIdToOrder[orderId];

        //Decrement totalOrdersQuantity on order.tokenIn for order owner
        //decrementTotalOrdersQuantity(order.tokenIn, order.owner, order.quantity);
        // Delete Order Orders[order.orderId] from ActiveOrders mapping
        delete orderIdToOrder[orderId];
        delete addressToOrderIds[msg.sender][orderId];
        //decrement from total orders per address
        --totalOrdersPerAddress[msg.sender];

        // Decrement total orders quantity
        // Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.quantity
        );

        //emit a canceled order event
        //TODO: do this in assembly
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);
    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelOrders(bytes32[] memory orderIds) public {
        bytes32[] memory canceledOrderIds = new bytes32[](orderIds.length);

        //TODO: just call cancel order on loop?
        //check that there is one or more orders
        for (uint256 i = 0; i < orderIds.length; ++i) {
            bytes32 orderId = orderIds[i];
            bool orderExists = addressToOrderIds[msg.sender][orderId];

            Order memory order = orderIdToOrder[orderId];

            if (!orderExists) {
                revert OrderDoesNotExist(orderId);
            }

            // Decrement total orders quantity
            // Decrement totalOrdersQuantity on order.tokenIn for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );

            delete addressToOrderIds[msg.sender][orderId];
            delete orderIdToOrder[orderId];
            canceledOrderIds[i] = orderId;
        }
        //emit an updated order event
        //TODO: do this in assembly
        emit OrderCancelled(canceledOrderIds);
    }

    /// @notice Helper function to get the total order's value on a specific token for the sender
    /// @param token token address to get total order's value on
    /// @return unsigned total order's value on token
    function _getTotalOrdersValue(address token)
        internal
        view
        returns (uint256)
    {
        //Hash token and sender for key and accumulate totalOrdersQuantity
        bytes32 totalOrdersValueKey = keccak256(abi.encode(msg.sender, token));

        return totalOrdersQuantity[totalOrdersValueKey];
    }

    function decrementTotalOrdersQuantity(
        address token,
        address owner,
        uint256 quantity
    ) internal {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(owner, token));
        totalOrdersQuantity[totalOrdersValueKey] -= quantity;
    }

    function incrementTotalOrdersQuantity(
        address token,
        address owner,
        uint256 quantity
    ) internal {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(owner, token));

        totalOrdersQuantity[totalOrdersValueKey] += quantity;
    }

    function updateTotalOrdersQuantity(
        address token,
        address owner,
        uint256 newQuantity
    ) internal {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(owner, token));
        totalOrdersQuantity[totalOrdersValueKey] = newQuantity;
    }

    /// @notice Internal helper function to approximate the minimum gas credits for a user assuming all Order's are standard erc20 compliant
    /// @param gasPrice uint256 current gas price in gwei
    /// @param executionCost uint256 total internal contract execution cost
    /// @param userAddress bytes32 address of the user to which calculation will be made
    /// @param multiplier uint256 margin multiplier to account for gas volatility
    /// @return unsigned uint256 total ETH required to cover execution
    function _calculateMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 multiplier
    ) internal view returns (uint256) {
        uint256 totalOrderCount = totalOrdersPerAddress[userAddress];

        unchecked {
            uint256 minimumGasCredits = totalOrderCount *
                gasPrice *
                executionCost *
                multiplier;
            if (
                minimumGasCredits <
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            ) {
                return minimumGasCredits;
            }
        }
        return 0;
    }

    /// @notice Internal helper function to check if user has the minimum gas credit requirement for all current orders
    /// @param gasPrice uint256 current gas price in gwei
    /// @param executionCost static execution cost for contract execution call
    /// @param userAddress bytes32 address of the user to be checked
    /// @param gasCreditBalance uint256 current gas credit balance of the user
    /// @return bool indicator whether user does have minimum gas credit requirements
    function _hasMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 gasCreditBalance
    ) internal view returns (bool) {
        return
            gasCreditBalance >=
            _calculateMinGasCredits(gasPrice, executionCost, userAddress, 5);
    }
}
