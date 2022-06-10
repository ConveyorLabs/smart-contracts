// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./test/utils/Console.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "./test/utils/Console.sol";
import "./OrderBook.sol";
import "./OrderRouter.sol";

///@notice for all order placement, order updates and order cancelation logic, see OrderBook
///@notice for all order fulfuillment logic, see OrderRouter

contract ConveyorLimitOrders is OrderBook, OrderRouter {
    //----------------------Modifiers------------------------------------//

    modifier onlyEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    //----------------------Mappings------------------------------------//

    //mapping to hold users gas credit balances
    mapping(address => uint256) creditBalance;

    //----------------------State Variables------------------------------------//

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //----------------------Constructor------------------------------------//

    constructor(address _gasOracle) OrderBook(_gasOracle) {}

    //----------------------Events------------------------------------//
    event GasCreditEvent(
        bool indexed deposit,
        address indexed sender,
        uint256 amount
    );

    //----------------------Structs------------------------------------//

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    //
    // struct Order {
    //     address tokenIn;
    //     address tokenOut;
    //     bytes32 orderId;
    //     OrderType orderType;
    //     uint256 price;
    //     uint256 quantity;
    // }

    // /// @notice enumeration of type of Order to be executed within the 'Order' Struct
    // enum OrderType {
    //     BUY,  -
    //     SELL, +
    //     STOP, -
    //     TAKE_PROFIT +
    // }
    //
    //

    struct TokenToTokenExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint128 wethToBReserve0;
        uint128 wethToBReserve1;
        uint256 price;
        address lpAddressAToWeth;
        address lpAddressWethToB;
    }

    struct TokenToWethExecutionPrice {
        uint128 aToWethReserve0;
        uint128 aToWethReserve1;
        uint256 price;
        address lpAddressAToWeth;
    }

    struct TokenToWethBatchOrder {
        uint256 amountIn;
        uint256 amountOutMin;
        address lpAddress;
        address[] batchOwners;
        uint256[] ownerShares;
    }

    struct TokenToTokenBatchOrder {
        uint256 amountIn;
        uint256 amountOutMin;
        address lpAddressAToWeth;
        address lpAddressWethToB;
        address[] batchOwners;
        uint256[] ownerShares;
    }

    //----------------------Functions------------------------------------//

    ///@notice This function takes in an array of orders,
    /// @param orders array of orders to be executed within the mapping
    function executeOrders(Order[] calldata orders) external onlyEOA {
        ///@notice validate that the order array is in ascending order by quantity
        _validateOrderSequencing(orders);

        ///@notice Sequence the orders by priority fee
        // Order[] memory sequencedOrders = _sequenceOrdersByPriorityFee(orders);

        ///@notice check if the token out is weth to determine what type of order execution to use
        if (orders[0].tokenOut == WETH) {
            _executeTokenToWethOrders(orders);
        } else {
            _executeTokenToTokenOrders(orders);
        }
    }

    ///@notice execute an array of orders from token to weth
    function _executeTokenToWethOrders(Order[] calldata orders) internal {
        ///@notice get all execution price possibilities
        TokenToWethExecutionPrice[]
            memory executionPrices = _initializeTokenToWethExecutionPrices(
                orders
            );

        ///@notice optimize the execution into batch orders, ensuring the best price for the least amount of gas possible
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        bool success = _executeTokenToWethBatchOrders(tokenToWethBatchOrders);
    }

    ///@notice execute an array of orders from token to token
    function _executeTokenToTokenOrders(Order[] calldata orders) internal {
        ///@notice get all execution price possibilities
        TokenToTokenExecutionPrice[]
            memory executionPrices = _initializeTokenToTokenExecutionPrices(
                orders
            );

        ///@notice optimize the execution into batch orders, ensuring the best price for the least amount of gas possible
        TokenToTokenBatchOrder[]
            memory tokenToTokenBatchOrders = _batchTokenToTokenOrders(
                orders,
                executionPrices
            );

        bool success = _executeTokenToTokenBatchOrders(tokenToTokenBatchOrders);
    }

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToWethExecutionPrices(Order[] calldata orders)
        internal
        returns (TokenToWethExecutionPrice[] memory executionPrices)
    {
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, 300, 1);

        {
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                executionPrices[i] = TokenToWethExecutionPrice(
                    spotReserveAToWeth[i].res0,
                    spotReserveAToWeth[i].res1,
                    0, //TODO: calculate initial price
                    lpAddressesAToWeth[i]
                );
            }
        }
    }

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToTokenExecutionPrices(Order[] calldata orders)
        internal
        returns (TokenToTokenExecutionPrice[] memory executionPrices)
    {
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, 300, 1);

        (
            SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = _getAllPrices(WETH, orders[0].tokenOut, 300, 1);

        {
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                for (uint256 j = 0; j < spotReserveWethToB.length; ++j) {
                    executionPrices[i] = TokenToTokenExecutionPrice(
                        spotReserveAToWeth[i].res0,
                        spotReserveAToWeth[i].res1,
                        spotReserveWethToB[j].res0,
                        spotReserveWethToB[j].res1,
                        0, //TODO: calculate initial price
                        lpAddressesAToWeth[i],
                        lpAddressWethToB[j]
                    );
                }
            }
        }
    }

    function _validateOrderSequencing(Order[] calldata orders) internal {
        for (uint256 j = 0; j < orders.length - 1; j++) {
            //TODO: change this to custom errors
            require(
                orders[j].quantity <= orders[j + 1].quantity,
                "Invalid Batch Ordering"
            );
        }
    }

    //TODO:
    function _sequenceOrdersByPriorityFee(Order[] calldata orders)
        internal
        returns (Order[] memory)
    {
        return orders;
    }

    function _buyOrSell(Order calldata order) internal returns (bool) {
        //Determine high bool from batched OrderType
        if (
            order.orderType == OrderType.BUY ||
            order.orderType == OrderType.TAKE_PROFIT
        ) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice private order execution function, assumes all orders passed to it will execute
    /// @param orders orders to be executed through swap
    /// @param dexIndex index of dex in dexes arr
    /// @param pairAddress lp pair address to execute the order batch on
    /// @param FEE lp spot trading fee
    /// @return bool indicating whether all orders were successfully executed in the batch
    function _executeOrder(
        Order[] memory orders,
        uint256 dexIndex,
        address pairAddress,
        uint24 FEE
    ) private returns (bool) {
        // if (dexes[dexIndex].isUniV2) {
        //     for (uint256 i = 0; i < orders.length; ++i) {
        //         uint128 amountOutWeth = uint128(
        //             _swapV2(
        //                 orders[i].tokenIn,
        //                 WETH,
        //                 pairAddress,
        //                 orders[i].quantity,
        //                 orders[i].amountOutMin
        //             )
        //         );
        //         uint128 _userFee = _calculateFee(amountOutWeth);
        //         (
        //             uint128 conveyorReward,
        //             uint128 beaconReward
        //         ) = _calculateReward(_userFee, amountOutWeth);
        //     }
        // } else {
        //     for (uint256 i = 0; i < orders.length; ++i) {
        //         uint128 amountOutWeth = uint128(
        //             _swapV3(
        //                 orders[i].tokenIn,
        //                 WETH,
        //                 FEE,
        //                 pairAddress,
        //                 orders[i].amountOutMin,
        //                 orders[i].quantity
        //             )
        //         );
        //         uint128 _userFee = _calculateFee(amountOutWeth);
        //         (
        //             uint128 conveyorReward,
        //             uint128 beaconReward
        //         ) = _calculateReward(_userFee, amountOutWeth);
        //     }
        // }
    }

    function _executeTokenToWethBatchOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders
    ) private returns (bool) {}

    function _executeTokenToTokenBatchOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders
    ) private returns (bool) {}

    function _calculateTokenToTokenPrice(
        Order[] memory orders,
        uint128 aToWethReserve0,
        uint128 aToWethReserve1,
        uint128 wethToBReserve0,
        uint128 wethToBReserve1
    ) internal returns (uint256 spotPrice) {}

    function _calculateTokenToWethPrice(
        Order[] memory orders,
        uint128 aToWethReserve0,
        uint128 aToWethReserve1
    ) internal returns (uint256 spotPrice) {}

    function _batchTokenToWethOrders(
        Order[] memory orders,
        TokenToWethExecutionPrice[] memory executionPrices
    ) internal returns (TokenToWethBatchOrder[] memory) {}

    function _batchTokenToTokenOrders(
        Order[] memory orders,
        TokenToTokenExecutionPrice[] memory executionPrices
    ) internal returns (TokenToTokenBatchOrder[] memory) {
        // (uint256 targetSpotFirst, uint256 targetSpotSecond) = (!high)
        //     ? (
        //         0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        //         0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        //     )
        //     : (0, 0);
        // for (uint256 i = 0; i < orders.length; i++) {
        //     uint256 indexFirst;
        //     uint256 indexSecond;
        //     for (uint256 k = 0; k < tempSpotsFirst.length; k++) {
        //         if (!(tempSpotsFirst[k] == 0)) {
        //             if (!high) {
        //                 if (tempSpotsFirst[k] < targetSpotFirst) {
        //                     indexFirst = k;
        //                     targetSpotFirst = tempSpotsFirst[k];
        //                 }
        //             } else {
        //                 if (tempSpotsFirst[k] > targetSpotFirst) {
        //                     indexFirst = k;
        //                     targetSpotFirst = tempSpotsFirst[k];
        //                 }
        //             }
        //         }
        //         if (!(tempSpotsSecond[k] == 0)) {
        //             if (!high) {
        //                 if (tempSpotsSecond[k] < targetSpotSecond) {
        //                     indexSecond = k;
        //                     targetSpotSecond = tempSpotsSecond[k];
        //                 }
        //             } else {
        //                 if (tempSpotsSecond[k] > targetSpotSecond) {
        //                     indexSecond = k;
        //                     targetSpotSecond = tempSpotsSecond[k];
        //                 }
        //             }
        //         }
        //     }
        //     Order memory order = orders[i];
        //     //console.logAddress(orderedPairs[i]);
        //     if (i != orders.length - 1) {
        //         (
        //             tempSpotsFirst[indexFirst],
        //             tempReservesFirst[indexFirst]
        //         ) = simulatePriceChange(
        //             uint128(order.quantity),
        //             tempReservesFirst[indexFirst]
        //         );
        //         (
        //             tempSpotsSecond[indexSecond],
        //             tempReservesSecond[indexSecond]
        //         ) = simulatePriceChange(
        //             ConveyorMath.mul128I(
        //                 order.quantity,
        //                 tempSpotsFirst[indexFirst]
        //             ),
        //             tempReservesSecond[indexSecond]
        //         );
        //     }
        //     simulatedSpotPrices[i][0] = targetSpotFirst;
        //     simulatedSpotPrices[i][1] = targetSpotSecond;
        //     orderedPairs[i][0] = pairAddressFirst[indexFirst];
        //     orderedPairs[i][1] = pairAddressSecond[indexSecond];
        // }
        // return (orderedPairs, simulatedSpotPrices);
    }

    /// @notice Helper function to determine the spot price change to the lp after introduction alphaX amount into the reserve pool
    /// @param alphaX uint256 amount to be added to reserve_x to get out token_y
    /// @param reserves current lp reserves for tokenIn and tokenOut
    /// @return unsigned The amount of proportional spot price change in the pool after adding alphaX to the tokenIn reserves
    function simulatePriceChange(uint128 alphaX, uint128[] memory reserves)
        internal
        pure
        returns (uint256, uint128[] memory)
    {
        uint128[] memory newReserves = new uint128[](2);

        unchecked {
            uint128 numerator = reserves[0] + alphaX;
            uint256 k = uint256(reserves[0] * reserves[1]);

            uint128 denominator = ConveyorMath.divUI(
                k,
                uint256(reserves[0] + alphaX)
            );

            uint256 spotPrice = uint256(
                ConveyorMath.div128x128(
                    uint256(numerator) << 128,
                    uint256(denominator) << 64
                )
            );

            require(
                spotPrice <=
                    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                "overflow"
            );
            newReserves[0] = numerator;
            newReserves[1] = denominator;
            return (uint256(spotPrice), newReserves);
        }
    }

    /// @notice Helper function to determine if order can execute based on the spot price of the lp, the determinig factor is the order.orderType
    /// @param order Order order.price to be checked against realtime lp spot price for execution
    /// @param lpSpotPrice realtime best lpSpotPrice found for the order
    /// @return bool indicator whether order can be executed or not
    function orderCanExecute(Order memory order, uint256[] memory lpSpotPrice)
        internal
        pure
        returns (bool)
    {
        uint128 spotInWeth = uint128(lpSpotPrice[0] >> 64);
        uint128 spotWethOut = uint128(lpSpotPrice[1] >> 64);

        if (order.orderType == OrderType.BUY) {
            return
                ConveyorMath.mul64x64(spotInWeth, spotWethOut) <= order.price;
        } else if (order.orderType == OrderType.SELL) {
            return
                ConveyorMath.mul64x64(spotInWeth, spotWethOut) >= order.price;
        } else if (order.orderType == OrderType.STOP) {
            return
                ConveyorMath.mul64x64(spotInWeth, spotWethOut) <= order.price;
        } else if (order.orderType == OrderType.TAKE_PROFIT) {
            return
                ConveyorMath.mul64x64(spotInWeth, spotWethOut) >= order.price;
        }
        return false;
    }

    /// @notice deposit gas credits publicly callable function
    /// @return bool boolean indicator whether deposit was successfully transferred into user's gas credit balance
    function depositCredits() public payable returns (bool) {
        //Require that deposit amount is strictly == ethAmount maybe keep this
        // require(msg.value == ethAmount, "Deposit amount misnatch");

        //Check if sender balance can cover eth deposit
        // Todo write this in assembly
        if (address(msg.sender).balance < msg.value) {
            return false;
        }

        //Add amount deposited to creditBalance of the user
        creditBalance[msg.sender] += msg.value;

        //Emit credit deposit event for beacon
        emit GasCreditEvent(true, msg.sender, msg.value);

        //return bool success
        return true;
    }
}
