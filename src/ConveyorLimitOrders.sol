// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

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

    address immutable WETH;

    //----------------------Constructor------------------------------------//

    constructor(address _gasOracle, address _weth) OrderBook(_gasOracle) {
        WETH = _weth;
    }

    //----------------------Events------------------------------------//
    event GasCreditEvent(
        bool indexed deposit,
        address indexed sender,
        uint256 amount
    );

    //----------------------Functions------------------------------------//

    //------------Gas Credit Functions------------------------

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

    /// @notice Public helper to withdraw user gas credit balance
    /// @param _value uint256 value which the user would like to withdraw
    /// @return bool boolean indicator whether withdrawal was successful
    function withdrawGasCredits(uint256 _value) public returns (bool) {
        //Require user's credit balance is larger than value
        if (creditBalance[msg.sender] < _value) {
            return false;
        }

        //Get current gas price from v3 Aggregator
        uint256 gasPrice = getGasPrice();

        //Require gas credit withdrawal doesn't exceeed minimum gas credit requirements
        if (
            !(
                hasMinGasCredits(
                    gasPrice,
                    300000,
                    msg.sender,
                    creditBalance[msg.sender] - _value
                )
            )
        ) {
            return false;
        }

        //Decrease user creditBalance
        creditBalance[msg.sender] = creditBalance[msg.sender] - _value;

        payable(msg.sender).transfer(_value);
        return true;
    }

    //------------Order Execution Functions------------------------
    ///@notice This function takes in an array of orders,
    /// @param orders array of orders to be executed within the mapping
    function executeOrders(Order[] calldata orders) external onlyEOA {
        ///@notice validate that the order array is in ascending order by quantity
        _validateOrderSequencing(orders);

        ///@notice Sequence the orders by priority fee
        // Order[] memory sequencedOrders = _sequenceOrdersByPriorityFee(orders);

        //TODO: figure out weth to token

        ///@notice check if the token out is weth to determine what type of order execution to use
        if (orders[0].tokenOut == WETH) {
            _executeTokenToWethOrders(orders);
        } else {
            _executeTokenToTokenOrders(orders);
        }
    }

    //----------------------Token To Weth Order Execution Logic------------------------------------//

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

        ///@notice execute the batch orders
        _executeTokenToWethBatchOrders(tokenToWethBatchOrders);
    }

    function _executeTokenToWethBatchOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders
    ) internal {
        uint256 totalBeaconReward;

        for (uint256 i = 0; i < tokenToWethBatchOrders.length; i++) {
            TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];

            (
                uint256 amountOut,
                uint256 beaconReward
            ) = _executeTokenToWethBatch(tokenToWethBatchOrders[i]);

            ///@notice add the beacon reward to the totalBeaconReward
            totalBeaconReward += beaconReward;

            uint256 ownerSharesLength = batch.ownerShares.length;

            uint256[] memory ownerShares = batch.ownerShares;
            uint256 amountIn = batch.amountIn;

            for (uint256 j = 0; j < ownerSharesLength; ++j) {
                ///@notice calculate how much to pay each user from the shares they own
                uint128 orderShare = ConveyorMath.divUI(
                    ownerShares[j],
                    amountIn
                );

                uint256 orderPayout = ConveyorMath.mul64I(
                    orderShare,
                    amountOut
                );

                ///@notice send the swap profit to the user
                safeTransferETH(batch.batchOwners[j], orderPayout);
            }
        }

        ///@notice calculate the beacon runner profit and pay the beacon
        safeTransferETH(msg.sender, totalBeaconReward);
    }

    function _executeTokenToWethBatch(TokenToWethBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        ///@notice swap from A to weth
        uint128 amountOutWeth = uint128(
            _swap(
                batch.tokenIn,
                WETH,
                batch.lpAddress,
                batch.amountIn,
                batch.amountOutMin
            )
        );

        ///@notice take out fees
        uint128 protocolFee = _calculateFee(amountOutWeth);

        (, uint128 beaconReward) = _calculateReward(protocolFee, amountOutWeth);

        return (uint256(amountOutWeth - protocolFee), uint256(beaconReward));
    }

    //------------Token to Weth Helper Functions------------------------

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToWethExecutionPrices(Order[] calldata orders)
        internal
        view
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
                    spotReserveAToWeth[i].spotPrice,
                    lpAddressesAToWeth[i]
                );
            }
        }
    }

    function _batchTokenToWethOrders(
        Order[] memory orders,
        TokenToWethExecutionPrice[] memory executionPrices
    ) internal returns (TokenToWethBatchOrder[] memory) {}

    /// @notice helper function to determine the most spot price advantagous trade route for lp ordering of the batch
    /// @notice Should be called prior to batch execution time to generate the final lp ordering on execution
    /// @param orders all of the verifiably executable orders in the batch filtered prior to passing as parameter
    /// @param reserveSizes nested array of uint256 reserve0,reserv1 for each lp
    /// @param pairAddress address[] ordered by [uniswapV2, Sushiswap, UniswapV3]
    // /// @return optimalOrder array of pair addresses of size orders.length corresponding to the indexed pair address to use for each order
    function _optimizeBatchLPOrder(
        Order[] memory orders,
        uint128[][] memory reserveSizes,
        address[] memory pairAddress,
        bool high
    ) public pure returns (address[] memory, uint256[] memory) {
        //continually mock the execution of each order and find the most advantagios spot price after each simulated execution
        // aggregate address[] optimallyOrderedPair to be an order's array of the optimal pair address to perform execution on for the respective indexed order in orders
        // Note order.length == optimallyOrderedPair.length

        uint256[] memory tempSpots = new uint256[](reserveSizes.length);
        address[] memory orderedPairs = new address[](orders.length);

        uint128[][] memory tempReserves = new uint128[][](reserveSizes.length);
        uint256[] memory simulatedSpotPrices = new uint256[](orders.length);

        uint256 targetSpot = (!high)
            ? 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            : 0;

        // Fill tempSpots array
        for (uint256 j = 0; j < tempSpots.length; j++) {
            tempSpots[j] = (pairAddress[j] == address(0))
                ? 0
                : uint256(
                    ConveyorMath.divUI(reserveSizes[j][0], reserveSizes[j][1])
                );
            tempReserves[j] = reserveSizes[j];
        }

        for (uint256 i = 0; i < orders.length; i++) {
            uint256 index;

            for (uint256 k = 0; k < tempSpots.length; k++) {
                if (!(tempSpots[k] == 0)) {
                    if (!high) {
                        if (tempSpots[k] < targetSpot) {
                            index = k;
                            targetSpot = tempSpots[k];
                        }
                    } else {
                        if (tempSpots[k] > targetSpot) {
                            index = k;
                            targetSpot = tempSpots[k];
                        }
                    }
                }
            }

            Order memory order = orders[i];
            //console.logAddress(orderedPairs[i]);
            if (i != orders.length - 1) {
                (tempSpots[index], tempReserves[index]) = simulatePriceChange(
                    uint128(order.quantity),
                    tempReserves[index]
                );
            }
            simulatedSpotPrices[i] = targetSpot;
            orderedPairs[i] = pairAddress[index];
        }

        return (orderedPairs, simulatedSpotPrices);
    }

    ///@notice returns the index of the best price in the executionPrices array
    function _findBestTokenToWethExecutionPrice(
        TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice if the order is a buy order, set the initial best price at 0, else set the initial best price at max uint256
        uint256 bestPrice = buyOrder
            ? 0
            : 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

        for (uint256 i = 0; i < executionPrices.length; i++) {
            uint256 executionPrice = executionPrices[i].price;
            if (executionPrice > bestPrice) {
                bestPrice = executionPrice;
                bestPriceIndex = i;
            }
        }
    }

    //----------------------Token To Token Order Execution Logic------------------------------------//

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

        ///@notice execute the batch orders
        _executeTokenToTokenBatchOrders(tokenToTokenBatchOrders);
    }

    function _executeTokenToTokenBatchOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders
    ) internal {
        uint256 totalBeaconReward;

        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; i++) {
            TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];

            ///@notice _execute order
            //TODO: return the (amountOut, protocolRevenue)
            (
                uint256 amountOut,
                uint256 beaconReward
            ) = _executeTokenToTokenBatch(tokenToTokenBatchOrders[i]);

            ///@notice add the beacon reward to the totalBeaconReward
            totalBeaconReward += beaconReward;

            uint256 ownerSharesLength = batch.ownerShares.length;
            uint256[] memory ownerShares = batch.ownerShares;
            uint256 amountIn = batch.amountIn;

            for (uint256 j = 0; j < ownerSharesLength; ++j) {
                //64.64
                ///@notice calculate how much to pay each user from the shares they own
                uint128 orderShare = ConveyorMath.divUI(
                    ownerShares[j],
                    amountIn
                );

                uint256 orderPayout = ConveyorMath.mul64I(
                    orderShare,
                    amountOut
                );

                safeTransferETH(batch.batchOwners[j], orderPayout);
            }
        }

        ///@notice calculate the beacon runner profit and pay the beacon
        safeTransferETH(msg.sender, totalBeaconReward);
    }

    ///@return (amountOut, beaconReward)
    ///@dev the amountOut is the amount out - protocol fees
    function _executeTokenToTokenBatch(TokenToTokenBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        ///@notice swap from A to weth
        uint128 amountOutWeth = uint128(
            _swap(
                batch.tokenIn,
                WETH,
                batch.lpAddressAToWeth,
                batch.amountIn,
                batch.amountOutMin
            )
        );

        ///@notice take out fees
        uint128 protocolFee = _calculateFee(amountOutWeth);
        (, uint128 beaconReward) = _calculateReward(protocolFee, amountOutWeth);

        ///@notice get amount in for weth to B
        uint256 amountInWethToB = amountOutWeth - protocolFee;

        ///@notice swap weth for B
        uint256 amountOutInB = _swap(
            WETH,
            batch.tokenOut,
            batch.lpAddressWethToB,
            amountInWethToB,
            //TODO: determine how much for amount out min
            batch.amountOutMin
        );

        return (amountOutInB, uint256(beaconReward));
    }

    //------------Token to Token Helper Functions------------------------

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToTokenExecutionPrices(Order[] calldata orders)
        internal
        view
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
                    uint128 spotPriceFinal = _calculateTokenToWethToTokenSpotPrice(
                            spotReserveAToWeth[i].spotPrice,
                            spotReserveWethToB[j].spotPrice
                        );
                    executionPrices[i] = TokenToTokenExecutionPrice(
                        spotReserveAToWeth[i].res0,
                        spotReserveAToWeth[i].res1,
                        spotReserveWethToB[j].res0,
                        spotReserveWethToB[j].res1,
                        spotPriceFinal,
                        lpAddressesAToWeth[i],
                        lpAddressWethToB[j]
                    );
                }
            }
        }
    }

    ///@notice Helper to calculate the multiplicative spot price over both router hops
    ///@param spotPriceAToWeth spotPrice of Token A relative to Weth
    ///@param spotPriceWethToB spotPrice of Weth relative to Token B
    ///@return spotPriceFinal multiplicative finalSpot
    function _calculateTokenToWethToTokenSpotPrice(
        uint256 spotPriceAToWeth,
        uint256 spotPriceWethToB
    ) internal pure returns (uint128 spotPriceFinal) {
        spotPriceFinal = ConveyorMath.mul64x64(
            uint128(spotPriceAToWeth >> 64),
            uint128(spotPriceWethToB >> 64)
        );
    }

    function _batchTokenToTokenOrders(
        Order[] memory orders,
        TokenToTokenExecutionPrice[] memory executionPrices
    )
        internal
        pure
        returns (TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders)
    {
        Order memory firstOrder = orders[0];
        bool buyOrder = _buyOrSell(firstOrder);

        address batchOrderTokenIn = firstOrder.tokenIn;
        address batchOrderTokenOut = firstOrder.tokenOut;

        uint256 currentBestPriceIndex = _findBestTokenToTokenExecutionPrice(
            executionPrices,
            buyOrder
        );

        TokenToTokenBatchOrder
            memory currentTokenToTokenBatchOrder = _initializeNewTokenToTokenBatchOrder(
                orders.length,
                batchOrderTokenIn,
                batchOrderTokenOut,
                executionPrices[currentBestPriceIndex].lpAddressAToWeth,
                executionPrices[currentBestPriceIndex].lpAddressWethToB
            );

        //loop each order
        for (uint256 i = 0; i < orders.length; i++) {
            //TODO: this is repetitive, we can do the first iteration and then start from n=1
            ///@notice get the index of the best exectuion price
            uint256 bestPriceIndex = _findBestTokenToTokenExecutionPrice(
                executionPrices,
                buyOrder
            );

            ///@notice if the best price has changed since the last order
            if (i > 0 && currentBestPriceIndex != bestPriceIndex) {
                ///@notice add the current batch order to the batch orders array
                tokenToTokenBatchOrders[
                    tokenToTokenBatchOrders.length
                ] = currentTokenToTokenBatchOrder;

                //-
                ///@notice update the currentBestPriceIndex
                currentBestPriceIndex = bestPriceIndex;

                ///@notice initialize a new batch order
                //TODO: need to implement logic to trim 0 val orders
                currentTokenToTokenBatchOrder = _initializeNewTokenToTokenBatchOrder(
                    orders.length,
                    batchOrderTokenIn,
                    batchOrderTokenOut,
                    executionPrices[bestPriceIndex].lpAddressAToWeth,
                    executionPrices[bestPriceIndex].lpAddressWethToB
                );
            }

            ///@notice get the best execution price
            uint256 executionPrice = executionPrices[bestPriceIndex].price;

            Order memory currentOrder = orders[i];

            ///@notice if the order meets the execution price
            if (
                _orderMeetsExecutionPrice(
                    currentOrder.price,
                    executionPrice,
                    buyOrder
                )
            ) {
                ///@notice if the order can execute without hitting slippage
                if (_orderCanExecute()) {
                    uint256 batchOrderLength = currentTokenToTokenBatchOrder
                        .batchOwners
                        .length;

                    ///@notice add the order to the current batch order
                    //TODO: can reduce size by just adding ownerShares on execution
                    currentTokenToTokenBatchOrder.amountIn += currentOrder
                        .quantity;

                    ///@notice add owner of the order to the batchOwners
                    currentTokenToTokenBatchOrder.batchOwners[
                        batchOrderLength
                    ] = currentOrder.owner;

                    ///@notice add the order quantity of the order to ownerShares
                    currentTokenToTokenBatchOrder.ownerShares[
                        batchOrderLength
                    ] = currentOrder.quantity;

                    ///@notice add the orderId to the batch order
                    currentTokenToTokenBatchOrder.orderIds[
                        batchOrderLength
                    ] = currentOrder.orderId;

                    ///TODO: update execution price at the previous index
                } else {
                    //TODO:
                    ///@notice cancel the order due to insufficient slippage
                }
            }
        }
    }

    function _initializeNewTokenToTokenBatchOrder(
        uint256 initArrayLength,
        address tokenIn,
        address tokenOut,
        address lpAddressAToWeth,
        address lpAddressWethToB
    ) internal pure returns (TokenToTokenBatchOrder memory) {
        ///@notice initialize a new batch order
        return
            TokenToTokenBatchOrder(
                ///@notice initialize amountIn
                0,
                ///@notice initialize amountOutMin
                0,
                ///@notice add the token in
                tokenIn,
                ///@notice add the token out
                tokenOut,
                ///@notice initialize A to weth lp
                lpAddressAToWeth,
                ///@notice initialize weth to B lp
                lpAddressWethToB,
                ///@notice initialize batchOwners
                new address[](initArrayLength),
                ///@notice initialize ownerShares
                new uint256[](initArrayLength),
                ///@notice initialize orderIds
                new bytes32[](initArrayLength)
            );
    }

    ///@notice returns the index of the best price in the executionPrices array
    ///@param buyOrder indicates if the batch is a buy or a sell
    function _findBestTokenToTokenExecutionPrice(
        TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice if the order is a buy order, set the initial best price at 0, else set the initial best price at max uint256
        uint256 bestPrice = buyOrder
            ? 0
            : 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

        for (uint256 i = 0; i < executionPrices.length; i++) {
            uint256 executionPrice = executionPrices[i].price;
            if (executionPrice > bestPrice) {
                bestPrice = executionPrice;
                bestPriceIndex = i;
            }
        }
    }

    //------------Misc Helper Functions------------------------

    function _validateOrderSequencing(Order[] calldata orders) internal pure {
        for (uint256 i = 0; i < orders.length - 1; i++) {
            Order memory currentOrder = orders[i];
            Order memory nextOrder = orders[i + 1];

            //TODO: change this to custom errors
            require(
                currentOrder.quantity <= nextOrder.quantity,
                "Invalid Batch Ordering"
            );

            require(
                currentOrder.tokenIn == nextOrder.tokenIn,
                "incongruent token group"
            );

            require(
                currentOrder.tokenOut == nextOrder.tokenOut,
                "incongruent token group"
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

    function _buyOrSell(Order memory order) internal pure returns (bool) {
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

    function safeTransferETH(address to, uint256 amount) internal {
        bool success;

        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
        require(success, "ETH_TRANSFER_FAILED");
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

    function _orderMeetsExecutionPrice(
        uint256 orderPrice,
        uint256 executionPrice,
        bool buyOrder
    ) internal pure returns (bool) {
        if (buyOrder) {
            return executionPrice <= orderPrice;
        } else {
            return executionPrice >= orderPrice;
        }
    }

    ///@notice checks if order can complete without hitting slippage
    //TODO:
    function _orderCanExecute() internal pure returns (bool) {}
}
