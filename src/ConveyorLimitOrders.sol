// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.15;

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
import "./ConveyorErrors.sol";
import "../lib/interfaces/token/IWETH.sol";

///@notice for all order placement, order updates and order cancelation logic, see OrderBook
///@notice for all order fulfuillment logic, see OrderRouter
contract ConveyorLimitOrders is OrderBook, OrderRouter {
    // ========================================= Modifiers =============================================
    modifier onlyEOA() {
        if (msg.sender != tx.origin) {
            revert MsgSenderIsNotTxOrigin();
        }
        _;
    }

    // ========================================= State Variables =============================================

    //mapping to hold users gas credit balances
    mapping(address => uint256) public gasCreditBalance;

    //Immutable weth address
    address immutable WETH;

    //Immutable usdc address
    address immutable USDC;

    //Immutable refresh fee paid monthly by an order to stay in the Conveyor queue
    uint256 immutable refreshFee;

    //Immutable refreshInterval set to 1 month on contract deployment
    uint256 immutable refreshInterval;

    //Immutable execution cost of an order
    uint256 immutable executionCost;

    // ========================================= Constructor =============================================

    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        uint256 _refreshFee,
        uint256 _refreshInterval,
        uint256 _executionCost
    ) OrderBook(_gasOracle) {
        refreshFee = _refreshFee;
        WETH = _weth;
        USDC = _usdc;
        refreshInterval = _refreshInterval;
        executionCost = _executionCost;
    }

    // ========================================= Events  =============================================

    event GasCreditEvent(
        bool indexed deposit,
        address indexed sender,
        uint256 amount
    );

    // ========================================= FUNCTIONS =============================================

    //------------Gas Credit Functions------------------------

    /// @notice deposit gas credits publicly callable function
    /// @return bool boolean indicator whether deposit was successfully transferred into user's gas credit balance
    function depositGasCredits() public payable returns (bool) {
        //Add amount deposited to creditBalance of the user
        gasCreditBalance[msg.sender] += msg.value;

        //Emit credit deposit event for beacon
        emit GasCreditEvent(true, msg.sender, msg.value);

        //return bool success
        return true;
    }

    ///TODO: make nonReentrant
    /// @notice Public helper to withdraw user gas credit balance
    /// @param _value uint256 value which the user would like to withdraw
    /// @return bool boolean indicator whether withdrawal was successful
    function withdrawGasCredits(uint256 _value) public returns (bool) {
        //Require user's credit balance is larger than value
        if (gasCreditBalance[msg.sender] < _value) {
            revert InsufficientGasCreditBalance();
        }

        //Get current gas price from v3 Aggregator
        uint256 gasPrice = getGasPrice();

        //Require gas credit withdrawal doesn't exceeed minimum gas credit requirements
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    executionCost,
                    msg.sender,
                    gasCreditBalance[msg.sender] - _value
                )
            )
        ) {
            revert InsufficientGasCreditBalanceForOrderExecution();
        }

        //Decrease user creditBalance
        gasCreditBalance[msg.sender] = gasCreditBalance[msg.sender] - _value;

        safeTransferETH(msg.sender, _value);

        return true;
    }

    //Todo add reentrancy guard
    /// @notice External helper function to allow beacon to refresh an oder after 30 days in unix time
    /// @param orderId order to refresh timestamp
    function refreshOrder(bytes32 orderId) external returns (bool) {
        Order memory order = getOrderById(orderId);

        //Require 30 days has elapsed since last refresh

        if (block.timestamp - order.lastRefreshTimestamp < refreshInterval) {
            revert OrderNotRefreshable();
        }

        //Require current timestamp is not past order expiration
        if (block.timestamp < order.expirationTimestamp) {
            revert OrderHasReachedExpiration();
        }

        //Require credit balance is sufficient to cover refresh feee
        if (gasCreditBalance[order.owner] < refreshFee) {
            revert InsufficientGasCreditBalance();
        }

        //Get current gas price from v3 Aggregator
        uint256 gasPrice = getGasPrice();
        //Require gas credit withdrawal doesn't exceeed minimum gas credit requirements
        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    executionCost,
                    order.owner,
                    gasCreditBalance[order.owner] - refreshFee
                )
            )
        ) {
            revert InsufficientGasCreditBalanceForOrderExecution();
        }

        //Transfer refresh fee to beacon
        safeTransferETH(msg.sender, refreshFee);

        //Decrement order.owner credit balance
        gasCreditBalance[order.owner] =
            gasCreditBalance[order.owner] -
            refreshFee;

        //Change order.lastRefreshTimestamp to current block.timestamp
        order.lastRefreshTimestamp = block.timestamp;

        return true;
    }

    //------------Order Cancellation Functions---------------------------------
    /// Todo Add reentrancy guard
    /// @notice Helper function for beacon to externally cancel an Order with below minimum gas credit balance for execution
    /// @param orderId Id of the order to cancel
    /// @return bool indicator whether order was successfully cancelled with compensation
    function validateAndCancelOrder(bytes32 orderId) external returns (bool) {
        //Order to be validated for cancellation
        Order memory order = orderIdToOrder[orderId];
        /// Check if order exists in active orders. Revert if order does not exist
        bool orderExists = addressToOrderIds[order.owner][orderId];
        if (!orderExists) {
            revert OrderDoesNotExist(orderId);
        }
        //Amount of order's owned by order owner
        uint256 totalOrders = totalOrdersPerAddress[order.owner];

        //Get current gas price from v3 Aggregator
        uint256 gasPrice = getGasPrice();

        uint256 minimumGasCreditsForAllOrders = _calculateMinGasCredits(
            gasPrice,
            300000,
            order.owner,
            1
        );

        uint256 minimumGasCreditsForSingleOrder = minimumGasCreditsForAllOrders /
                totalOrders;

        if (
            !(
                _hasMinGasCredits(
                    gasPrice,
                    executionCost,
                    order.owner,
                    gasCreditBalance[order.owner]
                )
            )
        ) {
            safeTransferETH(msg.sender, minimumGasCreditsForSingleOrder);

            delete orderIdToOrder[orderId];
            delete addressToOrderIds[order.owner][orderId];

            //decrement from total orders per address
            --totalOrdersPerAddress[order.owner];

            //Decrement totalOrdersQuantity on order.tokenIn for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );

            bytes32[] memory orderIds = new bytes32[](1);
            orderIds[0] = order.orderId;

            emit OrderCancelled(orderIds);

            return true;
        }
        return false;
    }

    /// @notice Internal helper function to cancel order with implicit validation within refreshOrder
    /// @param orderId Id of the order to cancel
    /// @param sender address of beacon caller to refreshOrder to be compensated for cancellation
    /// @return bool indicator whether order was successfully cancelled with compensation
    function _cancelOrder(bytes32 orderId, address sender)
        internal
        returns (bool)
    {
        Order memory order = orderIdToOrder[orderId];

        /// Check if order exists in active orders. Revert if order does not exist
        bool orderExists = addressToOrderIds[order.owner][orderId];
        if (!orderExists) {
            revert OrderDoesNotExist(orderId);
        }
        //Amount of order's owned by order owner
        uint256 totalOrders = totalOrdersPerAddress[order.owner];

        //Get current gas price from v3 Aggregator
        uint256 gasPrice = getGasPrice();

        uint256 minimumGasCreditsForAllOrders = _calculateMinGasCredits(
            gasPrice,
            300000,
            order.owner,
            1
        );

        uint256 minimumGasCreditsForSingleOrder = minimumGasCreditsForAllOrders /
                totalOrders;

        delete orderIdToOrder[orderId];
        delete addressToOrderIds[order.owner][orderId];

        //Decrement totalOrdersQuantity for order
        decrementTotalOrdersQuantity(order.tokenIn, msg.sender, order.quantity);

        //decrement from total orders per address
        --totalOrdersPerAddress[order.owner];

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;

        safeTransferETH(sender, minimumGasCreditsForSingleOrder);

        emit OrderCancelled(orderIds);

        return false;
    }

    // ==================== Order Execution Functions =========================

    ///@notice This function takes in an array of orders,
    /// @param orderIds array of orders to be executed within the mapping
    function executeOrders(bytes32[] calldata orderIds) external onlyEOA {
        ///@notice validate that the order array is in ascending order by quantity

        Order[] memory orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            orders[i] = getOrderById(orderIds[i]);
        }

        _validateOrderSequencing(orders);

        ///@notice Sequence the orders by priority fee
        // Order[] memory sequencedOrders = _sequenceOrdersByPriorityFee(orders);

        ///@notice check if the token out is weth to determine what type of order execution to use
        if (orders[0].taxed == true) {
            if (orders[0].tokenOut == WETH) {
                _executeTokenToWethTaxedOrders(orders);
            } else {
                //If second token is taxed and first token is weth
                //Then don't do first swap, and out amount of second swap directly to the eoa of the swap
                //Take out fee's from amount in
                _executeTokenToTokenTaxedOrders(orders);
            }
        } else {
            if (orders[0].tokenOut == WETH) {
                _executeTokenToWethOrders(orders);
            } else {
                //If first token is weth, don't do the first swap, and take out the fee's from the amountIn
                _executeTokenToTokenOrders(orders);
            }
        }
    }

    //------------Single Swap Best Dex price Aggregation---------------------------------

    function swapTokenToTokenOnBestDex(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 FEE,
        address reciever,
        address sender
    ) public returns (uint256 amountOut) {
        //Initialize tick second to smallest range
        uint32 tickSecond = 1;

        (SpotReserve[] memory prices, address[] memory lps) = _getAllPrices(
            tokenIn,
            tokenOut,
            tickSecond,
            FEE
        );

        uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        address bestLp;

        //Iterate through all dex's and get best price and corresponding lp
        for (uint256 i = 0; i < prices.length; ++i) {
            if (prices[i].spotPrice != 0) {
                if (prices[i].spotPrice < bestPrice) {
                    bestPrice = prices[i].spotPrice;
                    bestLp = lps[i];
                }
            }
        }

        if (_lpIsNotUniV3(bestLp)) {
            //Call swap univ2
            amountOut = _swapV2(
                tokenIn,
                tokenOut,
                bestLp,
                amountIn,
                amountOutMin,
                reciever,
                sender
            );
        } else {
            amountOut = _swapV3(
                tokenIn,
                tokenOut,
                FEE,
                amountIn,
                amountOutMin,
                reciever,
                sender
            );
        }
    }

    function swapETHToTokenOnBestDex(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 FEE
    ) external payable returns (uint256 amountOut) {
        if (msg.value != amountIn) {
            revert InsufficientDepositAmount();
        }

        (bool success, ) = address(IWETH(WETH)).call{value: amountIn}(
            abi.encodeWithSignature("deposit()")
        );
        // require(false, "Got here");
        if (success) {
            amountOut = swapTokenToTokenOnBestDex(
                WETH,
                tokenOut,
                amountIn,
                amountOutMin,
                FEE,
                msg.sender,
                address(this)
            );
        }
    }

    function swapTokenToETHOnBestDex(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 FEE
    ) external returns (uint256) {
        // IERC20(tokenIn).approve(address(this), amountIn);
        uint256 amountOutWeth = swapTokenToTokenOnBestDex(
            tokenIn,
            WETH,
            amountIn,
            amountOutMin,
            FEE,
            address(this),
            msg.sender
        );
        uint256 balanceBefore = address(this).balance;
        // require(false,"Got here");
        IWETH(WETH).withdraw(amountOutWeth);
        if ((address(this).balance - balanceBefore != amountOutWeth)) {
            revert WethWithdrawUnsuccessful();
        }

        safeTransferETH(msg.sender, amountOutWeth);

        return amountOutWeth;
    }

    // ==================== Order Execution Functions =========================

    // ==================== Token To Weth Order Execution Logic =========================
    ///@notice execute an array of orders from token to weth
    function _executeTokenToWethTaxedOrders(Order[] memory orders) internal {
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
        _executeTokenToWethBatchTaxedOrders(tokenToWethBatchOrders);
    }

    function _executeTokenToWethBatchTaxedOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders
    ) internal {
        uint128 totalBeaconReward;
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; i++) {
            TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];
            for (uint256 j = 0; j < batch.orderIds.length; j++) {
                Order memory order = getOrderById(batch.orderIds[i]);
                totalBeaconReward += _executeTokenToWethTaxedOrder(
                    batch,
                    order
                );
            }
        }

        safeTransferETH(msg.sender, totalBeaconReward);
    }

    function _executeTokenToWethTaxedOrder(
        TokenToWethBatchOrder memory batch,
        Order memory order
    ) internal returns (uint128 beaconReward) {
        uint24 fee = _getUniV3Fee(batch.lpAddress);
        ///@notice swap from A to weth
        uint128 amountOutWeth = uint128(
            _swap(
                order.tokenIn,
                WETH,
                batch.lpAddress,
                fee,
                order.quantity,
                order.amountOutMin,
                address(this),
                order.owner
            )
        );

        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        // safeTransferETH(msg.sender, beaconReward);

        //Cache orderId
        bytes32 orderId = order.orderId;

        //Scope all this
        {
            //Delete order from queue after swap execution
            delete orderIdToOrder[orderId];
            delete addressToOrderIds[order.owner][orderId];
            //decrement from total orders per address
            --totalOrdersPerAddress[order.owner];

            //Decrement totalOrdersQuantity for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );
        }

        (, beaconReward) = _calculateReward(protocolFee, amountOutWeth);
    }

    ///@notice execute an array of orders from token to weth
    function _executeTokenToWethOrders(Order[] memory orders) internal {
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

            uint256[] memory ownerShares = batch.ownerShares;
            uint256 amountIn = batch.amountIn;

            uint256 batchOrderLength = tokenToWethBatchOrders[i].batchLength;

            for (uint256 j = 0; j < batchOrderLength; ++j) {
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
        uint24 fee = _getUniV3Fee(batch.lpAddress);
        ///@notice swap from A to weth
        uint128 amountOutWeth = uint128(
            _swap(
                batch.tokenIn,
                WETH,
                batch.lpAddress,
                fee,
                batch.amountIn,
                batch.amountOutMin,
                address(this),
                address(this)
            )
        );

        //TODO: require amountOutWeth> batchAmountOutMin ?

        ///@notice take out fees
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        (, uint128 beaconReward) = _calculateReward(protocolFee, amountOutWeth);

        //Scope all this
        {
            //Iterate through all orderIds in the batch and delete the orders from queue post execution
            for (uint256 i = 0; i < batch.orderIds.length; ++i) {
                bytes32 orderId = batch.orderIds[i];

                // Delete Order Orders[order.orderId] from ActiveOrders mapping
                delete orderIdToOrder[orderId];
                delete addressToOrderIds[orderIdToOrder[orderId].owner][
                    orderId
                ];
                //decrement from total orders per address
                --totalOrdersPerAddress[orderIdToOrder[orderId].owner];
                //Decrement total orders quantity for each order
                decrementTotalOrdersQuantity(
                    orderIdToOrder[orderId].tokenIn,
                    orderIdToOrder[orderId].owner,
                    orderIdToOrder[orderId].quantity
                );
            }
        }
        return (uint256(amountOutWeth - protocolFee), uint256(beaconReward));
    }

    // ==================== Token to Weth Helper Functions =========================

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToWethExecutionPrices(Order[] memory orders)
        internal
        view
        returns (TokenToWethExecutionPrice[] memory)
    {
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, 500, 1);

        TokenToWethExecutionPrice[]
            memory executionPrices = new TokenToWethExecutionPrice[](
                spotReserveAToWeth.length
            );
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
        return executionPrices;
    }

    function _initializeNewTokenToWethBatchOrder(
        uint256 initArrayLength,
        address tokenIn,
        address lpAddressAToWeth
    ) internal pure returns (TokenToWethBatchOrder memory) {
        ///@notice initialize a new batch order
        return
            TokenToWethBatchOrder(
                ///@notice initialize batch length to 0
                0,
                ///@notice initialize amountIn
                0,
                ///@notice initialize amountOutMin
                0,
                ///@notice add the token in
                tokenIn,
                ///@notice initialize A to weth lp
                lpAddressAToWeth,
                ///@notice initialize batchOwners
                new address[](initArrayLength),
                ///@notice initialize ownerShares
                new uint256[](initArrayLength),
                ///@notice initialize orderIds
                new bytes32[](initArrayLength)
            );
    }

    function _batchTokenToWethOrders(
        Order[] memory orders,
        TokenToWethExecutionPrice[] memory executionPrices
    ) internal returns (TokenToWethBatchOrder[] memory) {
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = new TokenToWethBatchOrder[](
                orders.length
            );

        Order memory firstOrder = orders[0];
        bool buyOrder = _buyOrSell(firstOrder);

        address batchOrderTokenIn = firstOrder.tokenIn;

        uint256 currentBestPriceIndex = _findBestTokenToWethExecutionPrice(
            executionPrices,
            buyOrder
        );

        TokenToWethBatchOrder
            memory currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                orders.length,
                batchOrderTokenIn,
                executionPrices[currentBestPriceIndex].lpAddressAToWeth
            );

        uint256 currentTokenToWethBatchOrdersIndex = 0;

        //loop each order
        for (uint256 i = 0; i < orders.length; i++) {
            ///@notice get the index of the best exectuion price
            uint256 bestPriceIndex = _findBestTokenToWethExecutionPrice(
                executionPrices,
                buyOrder
            );

            ///@notice if the best price has changed since the last order
            if (i > 0 && currentBestPriceIndex != bestPriceIndex) {
                ///@notice add the current batch order to the batch orders array
                tokenToWethBatchOrders[
                    currentTokenToWethBatchOrdersIndex
                ] = currentTokenToWethBatchOrder;

                ++currentTokenToWethBatchOrdersIndex;

                //-
                ///@notice update the currentBestPriceIndex
                currentBestPriceIndex = bestPriceIndex;

                ///@notice initialize a new batch order
                //TODO: need to implement logic to trim 0 val orders
                currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                    orders.length,
                    batchOrderTokenIn,
                    executionPrices[bestPriceIndex].lpAddressAToWeth
                );
            }

            Order memory currentOrder = orders[i];

            ///@notice if the order meets the execution price
            if (
                _orderMeetsExecutionPrice(
                    currentOrder.price,
                    executionPrices[bestPriceIndex].price,
                    buyOrder
                )
            ) {
                ///@notice if the order can execute without hitting slippage
                if (
                    _orderCanExecute(
                        executionPrices[bestPriceIndex].price,
                        currentOrder.quantity,
                        currentOrder.amountOutMin
                    )
                ) {
                    //Transfer the tokenIn from the user's wallet to the contract
                    ///TODO: Check if success, if not cancel the order
                    transferTokensToContract(
                        currentOrder.owner,
                        currentOrder.tokenIn,
                        currentOrder.quantity
                    );

                    uint256 batchOrderDepth = currentTokenToWethBatchOrder
                        .batchOwners
                        .length - 1;

                    ///@notice add the order to the current batch order
                    currentTokenToWethBatchOrder.amountIn += currentOrder
                        .quantity;

                    ///@notice add owner of the order to the batchOwners
                    currentTokenToWethBatchOrder.batchOwners[
                        batchOrderDepth
                    ] = currentOrder.owner;

                    ///@notice add the order quantity of the order to ownerShares
                    currentTokenToWethBatchOrder.ownerShares[
                        batchOrderDepth
                    ] = currentOrder.quantity;

                    ///@notice add the orderId to the batch order
                    currentTokenToWethBatchOrder.orderIds[
                        batchOrderDepth
                    ] = currentOrder.orderId;

                    ///@notice increment the batch length
                    ++currentTokenToWethBatchOrder.batchLength;

                    ///@notice update the best execution price
                    (
                        executionPrices[bestPriceIndex]
                    ) = simulateTokenToWethPriceChange(
                        uint128(currentTokenToWethBatchOrder.amountIn),
                        executionPrices[bestPriceIndex]
                    );
                } else {
                    ///@notice cancel the order due to insufficient slippage
                    cancelOrder(currentOrder.orderId);
                    bytes32[] memory canceledOrderIds = new bytes32[](1);
                    canceledOrderIds[0] = currentOrder.orderId;
                    emit OrderCancelled(canceledOrderIds);
                }
            }
        }

        return tokenToWethBatchOrders;
    }

    function transferTokensToContract(
        address sender,
        address token,
        uint256 amount
    ) internal returns (bool) {
        try IERC20(token).transferFrom(sender, address(this), amount) {} catch {
            return false;
        }
        return true;
    }

    ///@notice returns the index of the best price in the executionPrices array
    function _findBestTokenToWethExecutionPrice(
        TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice if the order is a buy order, set the initial best price at 0, else set the initial best price at max uint256

        if (buyOrder) {
            uint256 bestPrice = 0;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                if (executionPrice > bestPrice) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        } else {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                if (executionPrice < bestPrice) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        }
    }

    // ==================== Token To Token Order Execution Logic =========================

    ///@notice execute an array of orders from token to token
    function _executeTokenToTokenOrders(Order[] memory orders) internal {
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

    ///@notice execute an array of orders from token to token
    function _executeTokenToTokenTaxedOrders(Order[] memory orders) internal {
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
        _executeTokenToTokenBatchTaxedOrders(tokenToTokenBatchOrders);
    }

    function _executeTokenToTokenBatchTaxedOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders
    ) internal {
        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; i++) {
            TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];
            uint128 totalBeaconReward;
            for (uint256 j = 0; j < batch.orderIds.length; j++) {
                Order memory order = getOrderById(batch.orderIds[j]);
                totalBeaconReward += _executeTokenToTokenTaxedOrder(
                    tokenToTokenBatchOrders[i],
                    order
                );
            }

            safeTransferETH(msg.sender, totalBeaconReward);
        }
    }

    ///@dev the amountOut is the amount out - protocol fees
    function _executeTokenToTokenTaxedOrder(
        TokenToTokenBatchOrder memory batch,
        Order memory order
    ) internal returns (uint128) {
        uint128 protocolFee;
        uint128 beaconReward;
        uint256 amountInWethToB;
        uint24 fee;
        if (order.tokenIn != WETH) {
            fee = _getUniV3Fee(batch.lpAddressAToWeth);
            ///@notice swap from A to weth
            uint128 amountOutWeth = uint128(
                _swap(
                    order.tokenIn,
                    WETH,
                    batch.lpAddressAToWeth,
                    fee,
                    order.quantity,
                    order.amountOutMin,
                    address(this),
                    order.owner
                )
            );

            ///@notice take out fees
            protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

            (, beaconReward) = _calculateReward(protocolFee, amountOutWeth);

            ///@notice get amount in for weth to B
            amountInWethToB = amountOutWeth - protocolFee;
        } else {
            //If token in == weth calculate fee on amount In
            protocolFee = _calculateFee(uint128(order.quantity), USDC, WETH);

            //Take out beacon reward from order quantity
            (, beaconReward) = _calculateReward(
                protocolFee,
                uint128(order.quantity)
            );

            ///@notice get amount in for weth to B
            amountInWethToB = order.quantity - protocolFee;
        }
        fee = _getUniV3Fee(batch.lpAddressWethToB);
        ///@notice swap weth for B
        _swap(
            WETH,
            order.tokenOut,
            batch.lpAddressWethToB,
            fee,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(this)
        );

        //Cache orderId
        bytes32 orderId = order.orderId;

        {
            //Delete order from queue after swap execution
            delete orderIdToOrder[orderId];
            delete addressToOrderIds[order.owner][orderId];
            //decrement from total orders per address
            --totalOrdersPerAddress[order.owner];

            //Decrement totalOrdersQuantity for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );
        }

        return beaconReward;
    }

    function _executeTokenToTokenBatchOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders
    ) internal {
        uint256 totalBeaconReward;

        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; i++) {
            TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];

            (
                uint256 amountOut,
                uint256 beaconReward
            ) = _executeTokenToTokenBatch(tokenToTokenBatchOrders[i]);

            ///@notice add the beacon reward to the totalBeaconReward
            totalBeaconReward += beaconReward;

            uint256[] memory ownerShares = batch.ownerShares;
            uint256 amountIn = batch.amountIn;

            uint256 batchOrderLength = tokenToTokenBatchOrders[i].batchLength;

            for (uint256 j = 0; j < batchOrderLength; ++j) {
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
        uint128 protocolFee;
        uint128 beaconReward;
        uint256 amountInWethToB;
        uint24 fee;
        if (batch.tokenIn != WETH) {
            fee = _getUniV3Fee(batch.lpAddressAToWeth);
            ///@notice swap from A to weth
            uint128 amountOutWeth = uint128(
                _swap(
                    batch.tokenIn,
                    WETH,
                    batch.lpAddressAToWeth,
                    fee,
                    batch.amountIn,
                    batch.amountOutMin,
                    address(this),
                    address(this)
                )
            );

            ///@notice take out fees
            protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

            (, beaconReward) = _calculateReward(protocolFee, amountOutWeth);

            ///@notice get amount in for weth to B
            amountInWethToB = amountOutWeth - protocolFee;
        } else {
            ///@notice take out fees from the batch amountIn since token0 is weth
            protocolFee = _calculateFee(uint128(batch.amountIn), USDC, WETH);

            //Take out beacon/conveyor reward
            (, beaconReward) = _calculateReward(
                protocolFee,
                uint128(batch.amountIn)
            );

            ///@notice get amount in for weth to B
            amountInWethToB = batch.amountIn - protocolFee;
        }

        fee = _getUniV3Fee(batch.lpAddressWethToB);
        ///@notice swap weth for B
        uint256 amountOutInB = _swap(
            WETH,
            batch.tokenOut,
            batch.lpAddressWethToB,
            fee,
            amountInWethToB,
            batch.amountOutMin,
            address(this),
            address(this)
        );

        //Scope all this
        {
            //Iterate through all orderIds in the batch and delete the orders from queue post execution
            for (uint256 i = 0; i < batch.orderIds.length; ++i) {
                bytes32 orderId = batch.orderIds[i];

                // Delete Order Orders[order.orderId] from ActiveOrders mapping
                delete orderIdToOrder[orderId];
                delete addressToOrderIds[orderIdToOrder[orderId].owner][
                    orderId
                ];
                //decrement from total orders per address
                --totalOrdersPerAddress[orderIdToOrder[orderId].owner];
                //Decrement total orders quantity for each order
                decrementTotalOrdersQuantity(
                    orderIdToOrder[orderId].tokenIn,
                    orderIdToOrder[orderId].owner,
                    orderIdToOrder[orderId].quantity
                );
            }
        }

        return (amountOutInB, uint256(beaconReward));
    }

    // ==================== Token to Token Helper Functions =========================

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToTokenExecutionPrices(Order[] memory orders)
        internal
        view
        returns (TokenToTokenExecutionPrice[] memory)
    {
        //TODO: need to make fee dynamic
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, 3000, 1);

        (
            SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = _getAllPrices(WETH, orders[0].tokenOut, 3000, 1);

        TokenToTokenExecutionPrice[]
            memory executionPrices = new TokenToTokenExecutionPrice[](
                spotReserveAToWeth.length
            );

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
        return executionPrices;
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

    function _initializeNewTokenToTokenBatchOrder(
        uint256 initArrayLength,
        address tokenIn,
        address tokenOut,
        address lpAddressAToWeth,
        address lpAddressWethToB
    ) internal pure returns (TokenToTokenBatchOrder memory) {
        ///@notice initialize a new batch order

        return (
            TokenToTokenBatchOrder(
                ///@notice initialize batch length to 0
                0,
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
            )
        );
    }

    function _batchTokenToTokenOrders(
        Order[] memory orders,
        TokenToTokenExecutionPrice[] memory executionPrices
    )
        internal
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

            Order memory currentOrder = orders[i];

            ///@notice if the order meets the execution price
            if (
                _orderMeetsExecutionPrice(
                    currentOrder.price,
                    executionPrices[bestPriceIndex].price,
                    buyOrder
                )
            ) {
                ///@notice if the order can execute without hitting slippage
                if (
                    _orderCanExecute(
                        executionPrices[bestPriceIndex].price,
                        currentOrder.quantity,
                        currentOrder.amountOutMin
                    )
                ) {
                    uint256 batchOrderLength = currentTokenToTokenBatchOrder
                        .batchOwners
                        .length;

                    ///@notice add the order to the current batch order
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

                    ///@notice increment the batch length
                    ++currentTokenToTokenBatchOrder.batchLength;

                    ///@notice update the best execution price
                    (
                        executionPrices[bestPriceIndex]
                    ) = simulateTokenToTokenPriceChange(
                        uint128(currentTokenToTokenBatchOrder.amountIn),
                        executionPrices[bestPriceIndex]
                    );
                } else {
                    ///@notice cancel the order due to insufficient slippage
                    cancelOrder(currentOrder.orderId);
                    //TODO: emit order cancellation
                }
            }
        }
    }

    ///@notice returns the index of the best price in the executionPrices array
    ///@param buyOrder indicates if the batch is a buy or a sell
    function _findBestTokenToTokenExecutionPrice(
        TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice if the order is a buy order, set the initial best price at 0, else set the initial best price at max uint256

        if (buyOrder) {
            uint256 bestPrice = 0;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                if (executionPrice > bestPrice) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        } else {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                if (executionPrice < bestPrice) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        }
    }

    // ==================== Misc Helper Functions =========================

    function _validateOrderSequencing(Order[] memory orders) internal pure {
        for (uint256 i = 0; i < orders.length - 1; i++) {
            Order memory currentOrder = orders[i];
            Order memory nextOrder = orders[i + 1];

            ///@notice check if the current order is less than or equal to the next order
            if (currentOrder.quantity > nextOrder.quantity) {
                revert InvalidBatchOrder();
            }

            ///@notice check if the token in is the same for the last order
            if (currentOrder.tokenIn != nextOrder.tokenIn) {
                revert IncongruentInputTokenInBatch();
            }

            ///@notice check if the token out is the same for the last order
            if (currentOrder.tokenOut != nextOrder.tokenOut) {
                revert IncongruentOutputTokenInBatch();
            }

            ///@notice check if the token tax status is the same for the last order
            if (currentOrder.buy != nextOrder.buy) {
                revert IncongruentBuySellStatusInBatch();
            }

            ///@notice check if the token tax status is the same for the last order
            if (currentOrder.taxed != nextOrder.taxed) {
                revert IncongruentTaxedTokenInBatch();
            }
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
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    receive() external payable {}

    // fallback() external payable{}

    //TODO: just import solmate safeTransferETh

    function simulateTokenToWethPriceChange(
        uint128 alphaX,
        TokenToWethExecutionPrice memory executionPrice
    ) internal pure returns (TokenToWethExecutionPrice memory) {
        //TODO: update this to make sure weth is the right reserve position
        (
            executionPrice.price,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1
        ) = simulateAToBPriceChange(
            alphaX,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1
        );
        //TODO:^^
        //---------------------------------------------------

        return executionPrice;
    }

    function simulateTokenToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal pure returns (TokenToTokenExecutionPrice memory) {
        //TODO: check if weth to token or token to weth and then change these vals
        uint128 reserveAToken = executionPrice.aToWethReserve0;
        uint128 reserveAWeth = executionPrice.aToWethReserve1;
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;

        //TODO:^^
        //---------------------------------------------------

        (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth
        ) = simulateAToBPriceChange(alphaX, reserveAToken, reserveAWeth);

        (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        ) = simulateAToBPriceChange(alphaX, reserveBWeth, reserveBToken);

        // return(newSpotPriceA*newSpotPriceB, )

        uint256 newTokenToTokenSpotPrice = uint256(
            ConveyorMath.mul64x64(
                uint128(newSpotPriceA >> 64),
                uint128(newSpotPriceB >> 64)
            )
        ) << 64;

        //TODO: update this to make sure weth is the right reserve position
        executionPrice.price = newTokenToTokenSpotPrice;
        executionPrice.aToWethReserve0 = newReserveAToken;
        executionPrice.aToWethReserve1 = newReserveAWeth;
        executionPrice.wethToBReserve0 = newReserveBWeth;
        executionPrice.wethToBReserve1 = newReserveBToken;
        //TODO:^^
        //---------------------------------------------------

        return executionPrice;
    }

    /// @notice Helper function to determine the spot price change to the lp after introduction alphaX amount into the reserve pool
    // / @param alphaX uint256 amount to be added to reserve_x to get out token_y
    // / @param reserves current lp reserves for tokenIn and tokenOut
    // / @return unsigned The amount of proportional spot price change in the pool after adding alphaX to the tokenIn reserves
    function simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB
    )
        internal
        pure
        returns (
            uint256,
            uint128,
            uint128
        )
    {
        uint128[] memory newReserves = new uint128[](2);

        unchecked {
            uint128 numerator = reserveA + alphaX;
            uint256 k = uint256(reserveA * reserveB);

            uint128 denominator = ConveyorMath.divUI(
                k,
                uint256(reserveA + alphaX)
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
            return (spotPrice, newReserves[0], newReserves[1]);
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
    function _orderCanExecute(
        uint256 spot_price,
        uint256 order_quantity,
        uint256 amountOutMin
    ) internal pure returns (bool) {
        return spot_price * order_quantity >= amountOutMin;
    }
}
