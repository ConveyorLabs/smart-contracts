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

    //----------------------Functions------------------------------------//

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

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders array of orders to be executed within the mapping
    function executeOrders(Order[] calldata orders) external onlyEOA {
        ///@notice validate that the order array is in ascending order by quantity
        _validateOrderSequencing(orders);

        ///@notice Initialize a bool to determine if the batch is a buy or sell
        bool buy = _buyOrSell(orders[0]);

        //TODO: initialize reserves, lpaddresses, batches

        //TODO: return batch order, only orders that return can execute
        //Simulated pairAddress and spotPrice Order of entire order batch
        (
            address[][] memory pairAddressOrder,
            uint256[][] memory simulatedSpotPrices
        ) = _optimizeBatchLPOrder(
                orders,
                lpReservesAToWeth,
                lpReservesWethToB,
                lpPairAddressAToWeth,
                lpPairAddressWethToB,
                buy
            );

        //TODO: create logic to execute each batch order
        //TODO: after swap, payout and rebase math logic

        // //Initialize structure to hold order batches per lp
        // Order[][] memory orderBatches = new Order[][](pairAddressOrder.length);

        // {
        //     //iterate through orders and try to fill order
        //     for (uint256 i = 0; i < orders.length; ++i) {
        //         //Pass in single order
        //         Order memory order = orders[i];

        //         //Check if order can execute at simulated price and add to orderBatches on the respective lp
        //         if (orderCanExecute(order, simulatedSpotPrices)) {
        //             for (uint256 j = 0; j < lpPairAddressFirst.length; ++j) {
        //                 if (pairAddressOrder[i][0] == lpPairAddressFirst[j]) {
        //                     //Batch size is used here to be accumulating index of 2nd order orderBatches array
        //                     //To know how many orders there are per batch
        //                     orderBatchesFirst[j][batchSize[j]] = order;
        //                     ++batchSize[j];
        //                 }
        //             }

        //             for (uint256 j = 0; j < lpPairAddressSecond.length; ++j) {
        //                 if (
        //                     pairAddressOrderSecond[i] == lpPairAddressSecond[j]
        //                 ) {
        //                     //Batch size is used here to be accumulating index of 2nd order orderBatches array
        //                     //To know how many orders there are per batch
        //                     orderBatchesSecond[j][batchSizeSecond[j]] = order;
        //                     ++batchSizeSecond[j];
        //                 }
        //             }
        //         }
        //     }
        // }

        // //Pass each batch into private execution function
        // for (uint256 index = 0; index < orderBatches.length; ++index) {
        //     if (batchSizeFirst[index] > 0) {
        //         _executeOrder(
        //             orderBatches[index],
        //             index,
        //             lpPairAddress[index],
        //             300
        //         );
        //     }
        // }
    }

    function _initializeReservesAndLPAddresses(Order[] calldata orders)
        internal
        returns (
            //TODO: return values
            uint128[][] memory lpReservesAToWeth,
            uint128[][] memory lpReservesWethToB,
            uint256[] memory batchSizeAToWeth,
            uint256[] memory batchSizeWethToB
        )
    {
        //Retrive Array of SpotReserve structs as well as lpPairAddress's, strict indexing is assumed between both structures
        //SpotReserve[] indicates the spot price and reserves across the first pairing in the two hop router
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpPairAddressAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, 300, 1);

        //Retrive Array of SpotReserve structs as well as lpPairAddress's, strict indexing is assumed between both structures
        //SpotReserve[] indicates the spot price and reserves across the second pairing in the two hop router
        (
            SpotReserve[] memory spotReserveWethToB,
            address[] memory lpPairAddressWethToB
        ) = _getAllPrices(WETH, orders[0].tokenOut, 300, 1);

        //Initialize lpReserves and populate with spotReserve indexed reserve values to pass into optimizeBatchLPOrder
        uint128[][] memory lpReservesAToWeth = new uint128[][](
            spotReserveAToWeth.length
        );

        //Initialize lpReserves and populate with spotReserve indexed reserve values to pass into optimizeBatchLPOrder
        uint128[][] memory lpReservesWethToB = new uint128[][](
            spotReserveWethToB.length
        );

        //Initialize batchSize array to index orderBatches[n]
        uint256[] memory batchSizeAToWeth = new uint256[](
            spotReserveAToWeth.length
        );

        //Initialize batchSize array to index orderBatches[n]
        uint256[] memory batchSizeWethToB = new uint256[](
            spotReserveWethToB.length
        );

        {
            for (uint256 k = 0; k < spotReserveAToWeth.length; ++k) {
                (lpReservesAToWeth[k][0], lpReservesAToWeth[k][1]) = (
                    uint128(spotReserveAToWeth[k].res0),
                    uint128(spotReserveAToWeth[k].res1)
                );
            }

            //TODO: determine which token is weth, weth must be the denominator ie, res 1
            for (uint256 k = 0; k < spotReserveWethToB.length; ++k) {
                (lpReservesWethToB[k][0], lpReservesWethToB[k][1]) = (
                    uint128(spotReserveWethToB[k].res0),
                    uint128(spotReserveWethToB[k].res1)
                );
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

    function _buyOrSell(Order calldata order) internal {
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
        if (dexes[dexIndex].isUniV2) {
            for (uint256 i = 0; i < orders.length; ++i) {
                uint128 amountOutWeth = uint128(
                    _swapV2(
                        orders[i].tokenIn,
                        WETH,
                        pairAddress,
                        orders[i].quantity,
                        orders[i].amountOutMin
                    )
                );
                uint128 _userFee = _calculateFee(amountOutWeth);

                (
                    uint128 conveyorReward,
                    uint128 beaconReward
                ) = _calculateReward(_userFee, amountOutWeth);
            }
        } else {
            for (uint256 i = 0; i < orders.length; ++i) {
                uint128 amountOutWeth = uint128(
                    _swapV3(
                        orders[i].tokenIn,
                        WETH,
                        FEE,
                        pairAddress,
                        orders[i].amountOutMin,
                        orders[i].quantity
                    )
                );
                uint128 _userFee = _calculateFee(amountOutWeth);

                (
                    uint128 conveyorReward,
                    uint128 beaconReward
                ) = _calculateReward(_userFee, amountOutWeth);
            }
        }
    }

    /// @notice helper function to determine the most spot price advantagous trade route for lp ordering of the batch
    /// @notice Should be called prior to batch execution time to generate the final lp ordering on execution
    /// @param orders all of the verifiably executable orders in the batch filtered prior to passing as parameter
    /// @param reserveSizesFirst nested array of uint256 reserve0,reserv1 for each lp on first hop
    /// @param reserveSizesSecond nested array of uint256 reserve0, reserve1 for each lp on second hop
    /// @param pairAddressFirst address[] ordered by [uniswapV2, Sushiswap, UniswapV3] for first hop
    /// @param pairAddressSecond address[] ordered by [uniswapV2, Sushiswap, UniswapV3] for second hop
    // /// @return optimalOrder array of pair addresses of size orders.length corresponding to the indexed pair address to use for each order
    function _optimizeBatchLPOrder(
        Order[] memory orders,
        uint128[][] memory reserveSizesFirst,
        uint128[][] memory reserveSizesSecond,
        address[] memory pairAddressFirst,
        address[] memory pairAddressSecond,
        bool high
    ) public pure returns (address[][] memory, uint256[][] memory) {
        (
            uint256[][] simulatedSpotPrices,
            uint256[] tempSpotsFirst,
            uint256[] tempSpotsSecond,
            uint128[][] tempReservesFirst,
            uint128[][] tempReservesSecond,
            address[][] orderedPairs
        ) = _initializeSpotPriceAndReserves(
                orders,
                reserveSizesFirst,
                reserveSizesSecond,
                pairAddressFirst,
                pairAddressSecond,
                high
            );

        return
            _batchOrders(
                orders,
                simulatedSpotPrices,
                tempSpotsFirst,
                tempSpotsSecond,
                tempReservesFirst,
                tempReservesSecond,
                orderedPairs,
                pairAddressFirst,
                pairAddressSecond,
                high
            );
    }

    function _initializeSpotPriceAndReserves(
        Order[] memory orders,
        uint128[][] memory reserveSizesFirst,
        uint128[][] memory reserveSizesSecond,
        address[] memory pairAddressFirst,
        address[] memory pairAddressSecond,
        bool high
    )
        internal
        returns (
            uint256[][] simulatedSpotPrices,
            uint256[] tempSpotsFirst,
            uint256[] tempSpotsSecond,
            uint128[][] tempReservesFirst,
            uint128[][] tempReservesSecond,
            address[][] orderedPairs
        )
    {
        //Scope everything where possible
        {
            // Fill tempSpots array
            for (uint256 j = 0; j < tempSpotsFirst.length; j++) {
                tempSpotsFirst[j] = (pairAddressFirst[j] == address(0))
                    ? 0
                    : uint256(
                        ConveyorMath.divUI(
                            reserveSizesFirst[j][0],
                            reserveSizesFirst[j][1]
                        )
                    ) << 64;
                tempSpotsSecond[j] = (pairAddressSecond[j] == address(0))
                    ? 0
                    : uint256(
                        ConveyorMath.divUI(
                            reserveSizesSecond[j][0],
                            reserveSizesSecond[j][1]
                        )
                    ) << 64;
                tempReservesFirst[j] = reserveSizesFirst[j];
                tempReservesSecond[j] = reserveSizesSecond[j];
            }
        }
    }

    function _batchOrders(
        Order[] memory orders,
        uint256[][] simulatedSpotPrices,
        uint256[] tempSpotsFirst,
        uint256[] tempSpotsSecond,
        uint128[][] tempReservesFirst,
        uint128[][] tempReservesSecond,
        address[][] orderedPairs,
        address[] memory pairAddressFirst,
        address[] memory pairAddressSecond,
        bool high
    ) internal returns (address[][], uint256[][]) {
        (uint256 targetSpotFirst, uint256 targetSpotSecond) = (!high)
            ? (
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            )
            : (0, 0);

        for (uint256 i = 0; i < orders.length; i++) {
            uint256 indexFirst;
            uint256 indexSecond;

            for (uint256 k = 0; k < tempSpotsFirst.length; k++) {
                if (!(tempSpotsFirst[k] == 0)) {
                    if (!high) {
                        if (tempSpotsFirst[k] < targetSpotFirst) {
                            indexFirst = k;
                            targetSpotFirst = tempSpotsFirst[k];
                        }
                    } else {
                        if (tempSpotsFirst[k] > targetSpotFirst) {
                            indexFirst = k;
                            targetSpotFirst = tempSpotsFirst[k];
                        }
                    }
                }

                if (!(tempSpotsSecond[k] == 0)) {
                    if (!high) {
                        if (tempSpotsSecond[k] < targetSpotSecond) {
                            indexSecond = k;
                            targetSpotSecond = tempSpotsSecond[k];
                        }
                    } else {
                        if (tempSpotsSecond[k] > targetSpotSecond) {
                            indexSecond = k;
                            targetSpotSecond = tempSpotsSecond[k];
                        }
                    }
                }
            }

            Order memory order = orders[i];

            //console.logAddress(orderedPairs[i]);
            if (i != orders.length - 1) {
                (
                    tempSpotsFirst[indexFirst],
                    tempReservesFirst[indexFirst]
                ) = simulatePriceChange(
                    uint128(order.quantity),
                    tempReservesFirst[indexFirst]
                );
                (
                    tempSpotsSecond[indexSecond],
                    tempReservesSecond[indexSecond]
                ) = simulatePriceChange(
                    ConveyorMath.mul128I(
                        order.quantity,
                        tempSpotsFirst[indexFirst]
                    ),
                    tempReservesSecond[indexSecond]
                );
            }
            simulatedSpotPrices[i][0] = targetSpotFirst;
            simulatedSpotPrices[i][1] = targetSpotSecond;
            orderedPairs[i][0] = pairAddressFirst[indexFirst];
            orderedPairs[i][1] = pairAddressSecond[indexSecond];
        }

        return (orderedPairs, simulatedSpotPrices);
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
