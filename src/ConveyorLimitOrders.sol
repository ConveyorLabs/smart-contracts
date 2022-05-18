// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./test/utils/Console.sol";
import "../lib/libraries/uniswap/OracleLibrary.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/PriceLibrary.sol";
import "../lib/libraries/ConveyorMath64x64.sol";

contract ConveyorLimitOrders {
    //----------------------Modifiers------------------------------------//

    modifier onlyEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    //----------------------Events------------------------------------//

    event OrderEvent(
        EventType indexed eventType,
        address indexed sender,
        bytes32[] indexed orderIds
    );

    //----------------------Errors------------------------------------//

    error OrderDoesNotExist(bytes32 orderId);
    error InsufficientWalletBalance();

    //TODO: rename this, bad name oof
    error IncongruentTokenInOrderGroup();

    //----------------------Enums------------------------------------//

    /// @notice enumeration of event type to be emmited from eoa function calls for, for queryable beacon event listening
    enum EventType {
        PLACE,
        UPDATE,
        CANCEL,
        CANCEL_ALL,
        FILLED,
        FAILED
    }

    /// @notice enumeration of type of Order to be executed within the 'Order' Struct
    enum OrderType {
        BUY,
        SELL,
        STOP,
        TAKE_PROFIT
    }

    //----------------------Factory/Router Address's------------------------------------//
    /// @dev 0-Uniswap V2 Factory, 1-Uniswap V3 Factory
    //TODO: add logic to initialize this in the contstructor
    address[] dexFactories = [
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
        0x1F98431c8aD98523631AE4a59f267346ea31F984
    ];

    //----------------------Structs------------------------------------//

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    struct Order {
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
    }

    /// @notice Struct to store important Dex specifications
    struct Dex {
        address factoryAddress;
        bytes32 initBytecode;
        bool isUniV2;
    }

    //----------------------State Structures------------------------------------//

    //order id  to order
    mapping(bytes32 => Order) orderIdToOrder;

    //struct to check if order exists, as well as get all orders for a wallet
    mapping(address => mapping(bytes32 => bool)) addressToOrderIds;

    /// @notice Array of dex structures to be used throughout the contract for pair spot price calculations
    Dex[] public dexes;

    //----------------------Constructor------------------------------------//

    constructor() {}

    //----------------------Functions------------------------------------//

    function getOrderById(
        address eoaAddress,
        address token,
        bytes32 orderId
    ) public view returns (Order memory order) {
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
        address orderToken = orderGroup[0].token;

        //TODO: sum all orders to check against total order value
        uint256 totalOrdersValue;

        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        for (uint256 i = 0; i < orderGroup.length; ++i) {
            Order memory newOrder = orderGroup[i];

            if (!(orderToken == newOrder.token)) {
                revert IncongruentTokenInOrderGroup();
            }

            totalOrdersValue += newOrder.quantity;

            //check if the wallet has a sufficient balance
            if (tokenBalance < totalOrdersValue) {
                revert InsufficientWalletBalance();
            }

            //TODO: create new order id construction that is simpler
            bytes32 orderId = keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.timestamp,
                    orderToken,
                    newOrder.price,
                    i
                )
            );

            //TODO: add order to all necessary state

            //TODO: add the order to active orders

            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;
        }

        //emit orders placed
        emit OrderEvent(EventType.PLACE, msg.sender, orderIds);

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

        //emit order updated
        //TODO: still need to decide on contents of events

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = newOrder.orderId;
        emit OrderEvent(EventType.UPDATE, msg.sender, orderIds);
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

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderEvent(EventType.CANCEL, msg.sender, orderIds);
    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelOrders(bytes32[] memory orderIds) public {
        bytes32[] memory canceledOrderIds = new bytes32[](orderIds.length);

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

        emit OrderEvent(EventType.PLACE, msg.sender, canceledOrderIds);
    }

    function swapAndPlaceOrders() public {}

    ///@notice gets all open orders for a specific wallet from ActiveOrders mapping

    ///TODO: implement logic to do this
    // function getOpenOrders() external view returns (TokenToOrderGroup memory) {
    //     return ActiveOrders[msg.sender];
    // }

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] memory orders) external onlyEOA {
        //iterate through orders and try to fill order
        for (uint256 i = 0; i < orders.length; ++i) {
            Order memory order = orders[i];
            //check the execution price of the order

            //check the price of the lp

            //note: can either loop through and execute or aggregate and execute

            //loop through orders and see which ones hit the execution price

            //if execution price hit
            //add the order to executableOrders, update total

            //aggregate the value of all of the orders
        }
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token0
    /// @param token1 bytes32 address of token1
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMeanPairSpotPrice(address token0, address token1)
        external
        view
        returns (uint256)
    {
        return
            PriceLibrary.calculateMeanSpotPrice(token0, token1, dexes, 1, 3000);
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMinPairSpotPrice(address token0, address token1)
        external
        view
        returns (uint256)
    {
        return
            PriceLibrary.calculateMinSpotPrice(token0, token1, dexes, 1, 3000);
    }

    /// @notice Helper function to calculate the logistic mapping output on a USDC input quantity for fee % calculation
    /// @dev calculation assumes 64x64 fixed point in128 representation for all values
    /// @param amountIn uint128 USDC amount in 64x64 fixed point to calculate the fee % of
    /// @return Out64x64 int128 Fee percent
    function calculateFee(int128 amountIn)
        public
        pure
        returns (int128 Out64x64)
    {
        require(
            !(amountIn << 64 > 0xfffffffffffffffffffffffffff),
            "Overflow Error"
        );
        int128 iamountIn = amountIn << 64;
        int128 numerator = 16602069666338597000; //.9 sccale := 1e19 ==> 64x64 fixed representation
        int128 denominator = (23058430092136940000 +
            ConveyorMath64x64.exp(
                ConveyorMath64x64.div(iamountIn, 75000 << 64)
            ));
        int128 rationalFraction = ConveyorMath64x64.div(numerator, denominator);
        Out64x64 = rationalFraction + 1844674407370955300;
    }

    /// @notice Helper function to calculate beacon and conveyor reward on transaction execution
    /// @param percentFee uint8 percentage of order size to be taken from user order size
    /// @param wethValue uint256 total order value in wei at execution price
    /// @return conveyorReward conveyor reward in terms of wei
    /// @return beaconReward beacon reward in wei
    function calculateReward(int128 percentFee, int128 wethValue)
        public
        pure
        returns (int128 conveyorReward, int128 beaconReward)
    {
        /// Todo calculate the beaconReward/conveyorReward based on applying percentFee to wethValue
    }

    /// @notice Helper function to check if min credits needed for order placement are satisfied
    /// @param orderGroup := array of order's to be placed
    /// @param gasPrice uint256 in gwei
    /// @return bool := boolean value indicating whether gas credit's provide coverage over all orders in the orderGroup
    function hasMinGasCredits(Order[] calldata orderGroup, uint256 gasPrice)
        internal
        pure
        returns (bool)
    {
        /// Todo iterate through each order in orderGroup, check if gas credits is satisfied for each order
    }

    /// @notice Helper function to calculate min gas credit quantity for singular order
    /// @param order Order struct to be checked for minimum gas credits
    /// @param gasPrice uint256 in gwei
    /// @return minCredits uint256 minimum gas credits required represented in wei
    function calculateMinGasCredits(Order calldata order, uint256 gasPrice)
        internal
        pure
        returns (uint256)
    {
        /// Todo determine the execution cost based on gasPrice, and return minimum gasCredits required in wei for order placement
    }

    /// @notice Helper function to calculate the max beacon reward for a group of order's
    /// @param snapShotSpot uint256 snapShotSpot of the lowest execution spot price of the whole batch
    /// @param reserve0 uint256 reserve0 of lp at execution time
    /// @param reserve1 uint256 reserve1 of lp at execution time
    /// @param fee uint256 lp fee
    /// @return maxBeaconReward uint256 maximum safe beacon reward to protect against flash loan price manipulation in the lp
    function calculateMaxBeaconReward(
        uint256 snapShotSpot,
        uint256 reserve0,
        uint256 reserve1,
        uint8 fee
    ) internal pure returns (uint256) {
        /// Todo calulate alphaX and multiply by fee to determine max beacon reward quantity
    }

    //------------------------Admin Functions----------------------------

    /// @notice Add Dex struct to dexes array from arr _factory, and arr _hexDem
    /// @param _factory address[] dex factory address's to add
    /// @param _hexDem Factory address create2 deployment bytecode array
    /// @param isUniV2 Array of bool's indicating uniV2 status
    function addDex(
        address[] memory _factory,
        bytes32[] memory _hexDem,
        bool[] memory isUniV2
    ) public {
        require(
            (_factory.length == _hexDem.length &&
                _hexDem.length == isUniV2.length),
            "Invalid input, Arr length mismatch"
        );
        for (uint256 i = 0; i < _factory.length; i++) {
            Dex memory d = Dex(_factory[i], _hexDem[i], isUniV2[i]);
            dexes.push(d);
        }
    }
}
