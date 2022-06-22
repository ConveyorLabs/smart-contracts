// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

import "../lib/interfaces/token/IERC20.sol";
import "./GasOracle.sol";
import "./ConveyorErrors.sol";

contract OrderBook is GasOracle, ConveyorErrors {
    //----------------------Constructor------------------------------------//

    constructor(address _gasOracle) GasOracle(_gasOracle) {}

    //----------------------Events------------------------------------//

    event OrderPlaced(bytes32[] indexed orderIds);
    event OrderCancelled(bytes32[] indexed orderIds);
    event OrderUpdated(bytes32[] indexed orderIds);

    //----------------------Structs------------------------------------//

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    struct Order {
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
        bool buy;
        uint256 price;
        uint256 amountOutMin;
        uint256 quantity;
        address owner;
    }

    //----------------------State Structures------------------------------------//

    //order id  to order
    //TODO: deleting doesnt actually get rid of the order, just removes the pointer
    mapping(bytes32 => Order) orderIdToOrder;

    //keccak256(msg.sender, tokenAddress) -> total orders quantity
    mapping(bytes32 => uint256) totalOrdersQuantity;

    //struct to check if order exists, as well as get all orders for a wallet
    mapping(address => mapping(bytes32 => bool)) addressToOrderIds;

    //Mapping to get total order count for a users address
    mapping(address => uint256) totalOrdersPerAddress;

    //----------------------Functions------------------------------------//

    function getOrderById(bytes32 orderId)
        public
        view
        returns (Order memory order)
    {
        order = orderIdToOrder[orderId];
        return order;
    }

    /// @notice Add user's order into the Active order's mapping conditionally if the oder passes all of the safety check criterion
    /// @param orderGroup := array of orders to be added to ActiveOrders mapping in OrderGroup struct
    /// @return orderIds
    function placeOrder(Order[] calldata orderGroup)
        public
        returns (bytes32[] memory)
    {
        uint256 orderIdIndex;
        bytes32[] memory orderIds = new bytes32[](orderGroup.length);
        //token that the orders are being placed on
        address orderToken = orderGroup[0].tokenIn;

        uint256 totalOrdersValue = getTotalOrdersValue(orderToken);
        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        //TODO: check for tokenIn/weth and tokenOut/weth else revert

        for (uint256 i = 0; i < orderGroup.length; ++i) {
            Order memory newOrder = orderGroup[i];

            if (!(orderToken == newOrder.tokenIn)) {
                revert IncongruentTokenInOrderGroup();
            }

            totalOrdersValue += newOrder.quantity;

            //check if the wallet has a sufficient balance
            if (tokenBalance < totalOrdersValue) {
                revert InsufficientWalletBalance();
            }

            //TODO: create new order id construction that is simpler, also use assembly to hash this
            bytes32 orderId = keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.timestamp,
                    orderToken,
                    newOrder.price,
                    i
                )
            );

            //add new order to state
            orderIdToOrder[orderId] = newOrder;
            addressToOrderIds[msg.sender][orderId] = true;
            //update total orders per address
            ++totalOrdersPerAddress[msg.sender];

            //update order ids for event emission
            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;
        }

        //emit orders placed
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

        //TODO: get total order sum and make sure that the user has the balance for the new order

        // if (newOrder.quantity > oldOrder.quantity) {
        //     totalOrdersValue += newOrder.quantity - oldOrder.quantity;
        // } else {
        //     totalOrdersValue += oldOrder.quantity - newOrder.quantity;
        // }

        // //check if the wallet has a sufficient balance
        // if (IERC20(newOrder.token).balanceOf(msg.sender) < totalOrdersValue) {
        //     revert InsufficientWalletBalance();
        // }

        //update the order
        orderIdToOrder[oldOrder.orderId] = newOrder;

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

        // Delete Order Orders[order.orderId] from ActiveOrders mapping
        delete orderIdToOrder[orderId];
        delete addressToOrderIds[msg.sender][orderId];
        //decrement from total orders per address
        --totalOrdersPerAddress[msg.sender];

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

            if (!orderExists) {
                revert OrderDoesNotExist(orderId);
            }

            delete addressToOrderIds[msg.sender][orderId];
            delete orderIdToOrder[orderId];
            canceledOrderIds[i] = orderId;
        }
        //emit an updated order event
        //TODO: do this in assembly
        emit OrderCancelled(canceledOrderIds);
    }

    function getTotalOrdersValue(address token) internal returns (uint256) {}

    /// @notice Internal helper function to approximate the minimum gas credits for a user assuming all Order's are standard erc20 compliant
    /// @param gasPrice uint256 current gas price in gwei
    /// @param executionCost uint256 total internal contract execution cost
    /// @param userAddress bytes32 address of the user to which calculation will be made
    /// @param multiplier uint256 margin multiplier to account for gas volatility
    /// @return unsigned uint256 total ETH required to cover execution
    function calculateMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 multiplier
    ) internal view returns (uint256) {
        uint256 totalOrderCount = totalOrdersPerAddress[userAddress];
        return totalOrderCount * gasPrice * executionCost * multiplier;
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
            calculateMinGasCredits(gasPrice, executionCost, userAddress, 5);
    }
}
