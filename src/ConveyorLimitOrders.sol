// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "./test/utils/Console.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "./test/utils/Console.sol";
import "./OrderBook.sol";
import "./OrderRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";

/// @title OrderRouter
/// @author LeytonTaylor, 0xKitsune
/// @notice TODO:
contract ConveyorLimitOrders is OrderBook, OrderRouter {
    // ========================================= Modifiers =============================================

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlyEOA() {
        if (msg.sender != tx.origin) {
            revert MsgSenderIsNotTxOrigin();
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
    //TODO: FIXME: we need to set the refresh fee
    uint256 immutable REFRESH_FEE = 5;
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

    ///@notice IQuoter instance to quote the amountOut for a given amountIn on a UniV3 pool.
    IQuoter immutable iQuoter;

    // ========================================= Constructor =============================================

    ///@param _gasOracle - Address of the ChainLink fast gas oracle.
    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _quoterAddress - Address for the IQuoter instance.
    ///@param _executionCost - The execution cost of fufilling a standard ERC20 swap from tokenIn to tokenOut
    ///@param _initByteCodes - Array of initBytecodes required to calculate pair addresses for each DEX.
    ///@param _dexFactories - Array of DEX factory addresses to be added to the system.
    ///@param _isUniV2 - Array indicating if a DEX factory passed in during initialization is a UniV2 compatiable DEX.
    ///@param _swapRouter - Address of the UniV3 SwapRouter for the chain.
    ///@param _alphaXDivergenceThreshold - Threshold between UniV3 and UniV2 spot price that determines if maxBeaconReward should be used.
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        address _quoterAddress,
        uint256 _executionCost,
        bytes32[] memory _initByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _swapRouter,
        uint256 _alphaXDivergenceThreshold
    )
        OrderBook(_gasOracle)
        OrderRouter(
            _initByteCodes,
            _dexFactories,
            _isUniV2,
            _swapRouter,
            _alphaXDivergenceThreshold,
            _weth
        )
    {
        iQuoter = IQuoter(_quoterAddress);
        REFRESH_FEE;
        WETH = _weth;
        USDC = _usdc;
        ORDER_EXECUTION_GAS_COST = _executionCost;
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

            ///@notice Require that current timestamp is not past order expiration, otherwise cancel the order and continue the loop.
            if (block.timestamp > order.expirationTimestamp) {
                _cancelOrder(orderId);

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
                _cancelOrder(orderId);

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
            _removeOrderFromSystem(order);

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
    /// @param orderId - Order Id of the order to cancel.
    /// @return success - Boolean to indicate if the order was successfully cancelled.
    function _cancelOrder(bytes32 orderId) internal returns (bool success) {
        ///@notice Cache order into memory
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

        ///@notice Remove the order from the limit order system.
        _removeOrderFromSystem(order);

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

    // ==================== Order Execution Functions =========================

    ///@notice This function is called by off-chain executors, passing in an array of orderIds to execute a specific batch of orders.
    /// @param orderIds - Array of orderIds to indicate which orders should be executed.
    function executeOrders(bytes32[] calldata orderIds) external onlyEOA {
        ///@notice Get all of the orders by orderId and add them to a temporary orders array
        Order[] memory orders = new Order[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getOrderById(orderIds[i]);

            unchecked {
                ++i;
            }
        }

        ///@notice Validate that the orders in the batch are passed in with increasing quantity.
        _validateOrderSequencing(orders);

        ///@notice Check if the order contains any taxed tokens.
        if (orders[0].taxed == true) {
            ///@notice If the tokenOut on the order is Weth
            if (orders[0].tokenOut == WETH) {
                _executeTokenToWethTaxedOrders(orders);
            } else {
                ///@notice Otherwise, if the tokenOut is not Weth and the order is a taxed order.
                _executeTokenToTokenTaxedOrders(orders);
            }
        } else {
            ///@notice If the order is not taxed and the tokenOut on the order is Weth
            if (orders[0].tokenOut == WETH) {
                _executeTokenToWethOrders(orders);
            } else {
                ///@notice Otherwise, if the tokenOut is not weth, continue with a regular token to token execution.
                _executeTokenToTokenOrders(orders);
            }
        }
    }

    ///@notice Function to execute orders from a taxed token to Weth.
    ///@param orders - Array of orders to be evaluated and executed.
    function _executeTokenToWethTaxedOrders(Order[] memory orders) internal {
        ///@notice Get all possible execution prices across all of the available DEXs.s
        (
            TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Batch the orders into optimized quantities to result in the best execution price and gas cost for each order.
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        ///@notice Execute the batched orders
        _executeTokenToWethBatchTaxedOrders(
            tokenToWethBatchOrders,
            maxBeaconReward
        );
    }

    ///@notice Function to execute batch orders from a taxed token to Weth.
    function _executeTokenToWethBatchTaxedOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        uint128 totalBeaconReward;
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];
            for (uint256 j = 0; j < batch.batchLength; ) {
                Order memory order = getOrderById(batch.orderIds[j]);
                totalBeaconReward += _executeTokenToWethTaxedOrder(
                    batch,
                    order
                );

                unchecked {
                    ++j;
                }

                //TODO: FIXME:
                //add functionality to decrement from the gas credit balance depending on the execution cost
            }

            unchecked {
                ++i;
            }
        }

        totalBeaconReward = maxBeaconReward > totalBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

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
        (
            TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice optimize the execution into batch orders, ensuring the best price for the least amount of gas possible
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        ///@notice execute the batch orders
        _executeTokenToWethBatchOrders(tokenToWethBatchOrders, maxBeaconReward);
    }

    function _executeTokenToWethBatchOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        uint256 totalBeaconReward;

        for (uint256 i = 0; i < tokenToWethBatchOrders.length; i++) {
            if (tokenToWethBatchOrders[i].batchLength > 0) {
                TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];

                (
                    uint256 amountOut,
                    uint256 beaconReward
                ) = _executeTokenToWethBatch(tokenToWethBatchOrders[i]);

                ///@notice add the beacon reward to the totalBeaconReward
                totalBeaconReward += beaconReward;

                uint256[] memory ownerShares = batch.ownerShares;
                uint256 amountIn = batch.amountIn;

                uint256 batchOrderLength = tokenToWethBatchOrders[i]
                    .batchLength;

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
        }
        totalBeaconReward = maxBeaconReward > totalBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;
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

        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        //Scope all this
        {
            //Iterate through all orderIds in the batch and delete the orders from queue post execution
            for (uint256 i = 0; i < batch.batchLength; ++i) {
                bytes32 orderId = batch.orderIds[i];

                ///@notice cache the order to avoid unecessary sloads
                Order memory cachedOrder = orderIdToOrder[orderId];

                //decrement from total orders per address
                --totalOrdersPerAddress[cachedOrder.owner];

                //Decrement total orders quantity for each order
                decrementTotalOrdersQuantity(
                    cachedOrder.tokenIn,
                    cachedOrder.owner,
                    cachedOrder.quantity
                );

                // Delete Order Orders[order.orderId] from ActiveOrders mapping
                delete addressToOrderIds[orderIdToOrder[orderId].owner][
                    orderId
                ];

                delete orderIdToOrder[orderId];
            }
        }
        ///TODO: FIXME: safeTransfer(conveyorReward) to conveyor address
        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    // ==================== Token to Weth Helper Functions =========================

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToWethExecutionPrices(Order[] memory orders)
        internal
        returns (TokenToWethExecutionPrice[] memory, uint128)
    {
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

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

        uint128 maxBeaconReward = calculateMaxBeaconReward(
            spotReserveAToWeth,
            orders,
            false
        );

        console.log("max beacon reward");
        console.log(maxBeaconReward);
        return (executionPrices, maxBeaconReward);
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

                    uint256 batchLength = currentTokenToWethBatchOrder
                        .batchLength;

                    ///@notice add the order to the current batch order
                    currentTokenToWethBatchOrder.amountIn += currentOrder
                        .quantity;

                    ///@notice add owner of the order to the batchOwners
                    currentTokenToWethBatchOrder.batchOwners[
                        batchLength
                    ] = currentOrder.owner;

                    ///@notice add the order quantity of the order to ownerShares
                    currentTokenToWethBatchOrder.ownerShares[
                        batchLength
                    ] = currentOrder.quantity;

                    ///@notice add the orderId to the batch order
                    currentTokenToWethBatchOrder.orderIds[
                        batchLength
                    ] = currentOrder.orderId;

                    ///@notice add the orderId to the batch order
                    currentTokenToWethBatchOrder.amountOutMin += currentOrder
                        .amountOutMin;

                    ///@notice increment the batch length
                    ++currentTokenToWethBatchOrder.batchLength;

                    // console.log(executionPrices[bestPriceIndex].price);
                    ///@notice update the best execution price
                    (
                        executionPrices[bestPriceIndex]
                    ) = simulateTokenToWethPriceChange(
                        uint128(currentOrder.quantity),
                        executionPrices[bestPriceIndex]
                    );
                    // console.log(executionPrices[bestPriceIndex].price);
                } else {
                    bytes32[] memory orderId = new bytes32[](1);
                    orderId[0] = currentOrder.orderId;
                    //Delete order from queue after swap execution
                    delete orderIdToOrder[currentOrder.orderId];
                    delete addressToOrderIds[currentOrder.owner][
                        currentOrder.orderId
                    ];
                    //decrement from total orders per address
                    --totalOrdersPerAddress[currentOrder.owner];

                    //Decrement totalOrdersQuantity for order owner
                    decrementTotalOrdersQuantity(
                        currentOrder.tokenIn,
                        currentOrder.owner,
                        currentOrder.quantity
                    );
                    emit OrderCancelled(orderId);
                }
            }
        }

        ///@notice add the last batch to the tokenToWethBatchOrders array
        tokenToWethBatchOrders[
            currentTokenToWethBatchOrdersIndex
        ] = currentTokenToWethBatchOrder;

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
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        } else {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                if (executionPrice > bestPrice && executionPrice != 0) {
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
        (
            TokenToTokenExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToTokenExecutionPrices(orders);

        ///@notice optimize the execution into batch orders, ensuring the best price for the least amount of gas possible
        TokenToTokenBatchOrder[]
            memory tokenToTokenBatchOrders = _batchTokenToTokenOrders(
                orders,
                executionPrices
            );

        ///@notice execute the batch orders
        _executeTokenToTokenBatchOrders(
            tokenToTokenBatchOrders,
            maxBeaconReward
        );
    }

    ///@notice execute an array of orders from token to token
    function _executeTokenToTokenTaxedOrders(Order[] memory orders) internal {
        ///@notice get all execution price possibilities
        (
            TokenToTokenExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToTokenExecutionPrices(orders);

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
            for (uint256 j = 0; j < batch.batchLength; j++) {
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

            uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
                batch.lpAddressAToWeth,
                order.quantity,
                batch.orderIds[0],
                order.taxIn
            );

            ///@notice swap from A to weth
            uint128 amountOutWeth = uint128(
                _swap(
                    order.tokenIn,
                    WETH,
                    batch.lpAddressAToWeth,
                    fee,
                    order.quantity,
                    batchAmountOutMinAToWeth,
                    address(this),
                    order.owner
                )
            );

            ///@notice take out fees
            protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

            (, beaconReward) = _calculateReward(protocolFee, amountOutWeth);

            ///@notice get amount in for weth to B
            amountInWethToB = amountOutWeth - beaconReward;
        } else {
            //If token in == weth calculate fee on amount In
            protocolFee = _calculateFee(uint128(order.quantity), USDC, WETH);

            //Take out beacon reward from order quantity
            (, beaconReward) = _calculateReward(
                protocolFee,
                uint128(order.quantity)
            );

            ///@notice get amount in for weth to B
            amountInWethToB = order.quantity - beaconReward;
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
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders,
        uint128 maxBeaconReward
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

        totalBeaconReward = totalBeaconReward < maxBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

        ///@notice calculate the beacon runner profit and pay the beacon
        safeTransferETH(msg.sender, totalBeaconReward);
    }

    ///TODO: Account for v3 fee on amountOut conversion
    ///@notice Helper function to calculate amountOutMin value agnostically across dexes on the first hop from tokenA to WETH
    ///@param lpAddressAToWeth lp address of A to weth pair
    ///@param amountInOrder the order.quantity
    ///@param orderId bytes32 identifier of the order
    ///@param taxIn tax of tokenA if any
    function calculateAmountOutMinAToWeth(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        bytes32 orderId,
        uint16 taxIn
    ) internal returns (uint256 amountOutMinAToWeth) {
        if (!_lpIsNotUniV3(lpAddressAToWeth)) {
            Order memory order = getOrderById(orderId);

            ///@notice 1000==100% so divide amountInOrder *taxIn by 10**5 to adjust to correct base
            uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
            uint256 amountIn = amountInOrder - amountInBuffer;

            amountOutMinAToWeth = iQuoter.quoteExactInputSingle(
                order.tokenIn,
                WETH,
                order.feeIn,
                amountIn,
                0
            );
        } else {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(
                lpAddressAToWeth
            ).getReserves();
            if (WETH == IUniswapV2Pair(lpAddressAToWeth).token0()) {
                uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
                uint256 amountIn = amountInOrder - amountInBuffer;
                amountOutMinAToWeth = getAmountOut(
                    amountIn,
                    uint256(reserve1),
                    uint256(reserve0)
                );
            } else {
                uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
                uint256 amountIn = amountInOrder - amountInBuffer;
                amountOutMinAToWeth = getAmountOut(
                    amountIn,
                    uint256(reserve0),
                    uint256(reserve1)
                );
            }
        }
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    ///@return (amountOut, beaconReward)
    ///@dev the amountOut is the amount out - protocol fees
    function _executeTokenToTokenBatch(TokenToTokenBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        uint128 protocolFee;
        uint128 beaconReward;
        uint128 conveyorReward;
        uint256 amountInWethToB;
        uint24 fee;

        if (!(batch.batchLength == 0)) {
            if (batch.tokenIn != WETH) {
                uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
                    batch.lpAddressAToWeth,
                    batch.amountIn,
                    batch.orderIds[0],
                    0
                );

                fee = _getUniV3Fee(batch.lpAddressAToWeth);

                ///@notice swap from A to weth
                uint128 amountOutWeth = uint128(
                    _swap(
                        batch.tokenIn,
                        WETH,
                        batch.lpAddressAToWeth,
                        fee,
                        batch.amountIn,
                        batchAmountOutMinAToWeth,
                        address(this),
                        address(this)
                    )
                );

                ///@notice take out fees
                protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

                (conveyorReward, beaconReward) = _calculateReward(
                    protocolFee,
                    amountOutWeth
                );

                ///@notice get amount in for weth to B
                amountInWethToB =
                    amountOutWeth -
                    (beaconReward + conveyorReward);
            } else {
                ///@notice take out fees from the batch amountIn since token0 is weth
                protocolFee = _calculateFee(
                    uint128(batch.amountIn),
                    USDC,
                    WETH
                );

                //Take out beacon/conveyor reward
                (conveyorReward, beaconReward) = _calculateReward(
                    protocolFee,
                    uint128(batch.amountIn)
                );

                ///@notice get amount in for weth to B
                amountInWethToB =
                    batch.amountIn -
                    (beaconReward + conveyorReward);
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
                for (uint256 i = 0; i < batch.batchLength; ++i) {
                    bytes32 orderId = batch.orderIds[i];

                    Order memory cachedOrder = orderIdToOrder[orderId];

                    //decrement from total orders per address
                    --totalOrdersPerAddress[cachedOrder.owner];

                    //Decrement total orders quantity for each order
                    decrementTotalOrdersQuantity(
                        cachedOrder.tokenIn,
                        cachedOrder.owner,
                        cachedOrder.quantity
                    );

                    // Delete Order Orders[order.orderId] from ActiveOrders mapping

                    delete addressToOrderIds[orderIdToOrder[orderId].owner][
                        orderId
                    ];

                    delete orderIdToOrder[orderId];
                }
            }

            return (amountOutInB, uint256(beaconReward));
        } else {
            return (0, 0);
        }
    }

    // ==================== Token to Token Helper Functions =========================

    ///@notice initializes all routes from a to weth -> weth to b and returns an array of all combinations as ExectionPrice[]
    function _initializeTokenToTokenExecutionPrices(Order[] memory orders)
        internal
        returns (TokenToTokenExecutionPrice[] memory, uint128)
    {
        address tokenIn = orders[0].tokenIn;

        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(tokenIn, WETH, orders[0].feeIn);

        (
            SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = _getAllPrices(WETH, orders[0].tokenOut, orders[0].feeOut);

        TokenToTokenExecutionPrice[]
            memory executionPrices = new TokenToTokenExecutionPrice[](
                spotReserveAToWeth.length * spotReserveWethToB.length
            );

        if (tokenIn == WETH) {
            for (uint256 i = 0; i < spotReserveWethToB.length; ++i) {
                executionPrices[i] = TokenToTokenExecutionPrice(
                    0,
                    0,
                    spotReserveWethToB[i].res0,
                    spotReserveWethToB[i].res1,
                    spotReserveWethToB[i].spotPrice,
                    address(0),
                    lpAddressWethToB[i]
                );
            }
        } else {
            uint256 index = 0;
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                for (uint256 j = 0; j < spotReserveWethToB.length; ++j) {
                    //TODO: update this comment: the first hop is skipped so only use the second spot price
                    uint256 spotPriceFinal = uint256(
                        _calculateTokenToWethToTokenSpotPrice(
                            spotReserveAToWeth[i].spotPrice,
                            spotReserveWethToB[j].spotPrice
                        )
                    ) << 64;

                    executionPrices[index] = TokenToTokenExecutionPrice(
                        spotReserveAToWeth[i].res0,
                        spotReserveAToWeth[i].res1,
                        spotReserveWethToB[j].res1,
                        spotReserveWethToB[j].res0,
                        spotPriceFinal,
                        lpAddressesAToWeth[i],
                        lpAddressWethToB[j]
                    );
                    index++;
                }
            }
        }

        //Used as a protective hard cap on the beacon reward to prevent flashloaning the orders in the queue
        uint128 maxBeaconReward = WETH != tokenIn
            ? calculateMaxBeaconReward(spotReserveAToWeth, orders, false)
            : calculateMaxBeaconReward(spotReserveWethToB, orders, true);

        return (executionPrices, maxBeaconReward);
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

    ///@notice Helper function to initialize a blank TokenToTokenBatchOrder to be populated
    ///@param initArrayLength Length of the order's in the batch
    ///@param tokenIn tokenIn address on the batch
    ///@param tokenOut tokenOut address on the batch
    ///@param lpAddressAToWeth lp address of tokenIn to Weth
    ///@param lpAddressWethToB lp address of Weth to tokenOut
    ///@return TokenToTokenBatchOrder empty batch to be populated with orders
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

    ///@notice Helper function to batch TokenToToken order's in the context of order execution
    ///@param orders Array of order's to be batched retrieved from orderID's
    ///@param executionPrices Array of TokenToTokenExecutionPrices to be used to determine order batches
    ///@return tokenToTokenBatchOrders Order batches on respective Dex's
    function _batchTokenToTokenOrders(
        Order[] memory orders,
        TokenToTokenExecutionPrice[] memory executionPrices
    )
        internal
        returns (TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders)
    {
        tokenToTokenBatchOrders = new TokenToTokenBatchOrder[](orders.length);
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

        uint256 currentTokenToTokenBatchOrdersIndex = 0;
        {
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
                        currentTokenToTokenBatchOrdersIndex
                    ] = currentTokenToTokenBatchOrder;

                    currentTokenToTokenBatchOrdersIndex++;

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
                    if (
                        _orderCanExecute(
                            executionPrices[bestPriceIndex].price,
                            currentOrder.quantity,
                            currentOrder.amountOutMin
                        )
                    ) {
                        transferTokensToContract(
                            currentOrder.owner,
                            currentOrder.tokenIn,
                            currentOrder.quantity
                        );

                        uint256 batchLength = currentTokenToTokenBatchOrder
                            .batchLength;

                        ///@notice add the order to the current batch order
                        currentTokenToTokenBatchOrder.amountIn += currentOrder
                            .quantity;

                        currentTokenToTokenBatchOrder
                            .amountOutMin += currentOrder.amountOutMin;

                        ///@notice add owner of the order to the batchOwners
                        currentTokenToTokenBatchOrder.batchOwners[
                                batchLength
                            ] = currentOrder.owner;

                        ///@notice add the order quantity of the order to ownerShares
                        currentTokenToTokenBatchOrder.ownerShares[
                                batchLength
                            ] = currentOrder.quantity;

                        ///@notice add the orderId to the batch order
                        currentTokenToTokenBatchOrder.orderIds[
                            batchLength
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
                        bytes32[] memory orderId = new bytes32[](1);
                        orderId[0] = currentOrder.orderId;
                        //Delete order from queue after swap execution
                        delete orderIdToOrder[currentOrder.orderId];
                        delete addressToOrderIds[currentOrder.owner][
                            currentOrder.orderId
                        ];
                        //decrement from total orders per address
                        --totalOrdersPerAddress[currentOrder.owner];

                        //Decrement totalOrdersQuantity for order owner
                        decrementTotalOrdersQuantity(
                            currentOrder.tokenIn,
                            currentOrder.owner,
                            currentOrder.quantity
                        );
                        emit OrderCancelled(orderId);
                    }
                }
            }
        }

        ///@notice add the last batch to the tokenToWethBatchOrders array
        tokenToTokenBatchOrders[
            currentTokenToTokenBatchOrdersIndex
        ] = currentTokenToTokenBatchOrder;
    }

    ///@notice returns the index of the best price in the executionPrices array
    ///@param buyOrder indicates if the batch is a buy or a sell
    function _findBestTokenToTokenExecutionPrice(
        TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice if the order is a buy order, set the initial best price at 0, else set the initial best price at max uint256

        if (buyOrder) {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;

                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        } else {
            uint256 bestPrice = 0;
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;

                if (executionPrice > bestPrice && executionPrice != 0) {
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

    function _buyOrSell(Order memory order) internal pure returns (bool) {
        //Determine high bool from batched OrderType
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    receive() external payable {}

    function simulateTokenToWethPriceChange(
        uint128 alphaX,
        TokenToWethExecutionPrice memory executionPrice
    ) internal returns (TokenToWethExecutionPrice memory) {
        address pool = executionPrice.lpAddressAToWeth;

        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();

        uint8 tokenInDecimals = token1 == WETH
            ? IERC20(token0).decimals()
            : IERC20(token1).decimals();

        ///@notice Convert to 18 decimals to have correct price change on the reserve quantities in common 18 decimal form
        uint128 amountIn = tokenInDecimals <= 18
            ? uint128(alphaX * 10**(18 - tokenInDecimals))
            : uint128(alphaX / (10**(tokenInDecimals - 18)));

        (
            executionPrice.price,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1,

        ) = _simulateAToBPriceChange(
            amountIn,
            executionPrice.aToWethReserve0,
            executionPrice.aToWethReserve1,
            pool,
            true
        );

        return executionPrice;
    }

    function simulateTokenToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        if (
            executionPrice.aToWethReserve0 != 0 &&
            executionPrice.aToWethReserve1 != 0
        ) {
            address pool = executionPrice.lpAddressAToWeth;
            address token0;
            address token1;
            bool _isUniV2 = _lpIsNotUniV3(pool);
            {
                if (_isUniV2) {
                    token0 = IUniswapV2Pair(pool).token0();
                    token1 = IUniswapV2Pair(pool).token1();
                } else {
                    token0 = IUniswapV3Pool(pool).token0();
                    token1 = IUniswapV3Pool(pool).token1();
                }
            }

            uint8 tokenInDecimals = token1 == WETH
                ? IERC20(token0).decimals()
                : IERC20(token1).decimals();

            ///@notice Convert to 18 decimals to have correct price change on the reserve quantities in common 18 decimal form
            uint128 amountIn = tokenInDecimals <= 18
                ? uint128(alphaX * 10**(18 - tokenInDecimals))
                : uint128(alphaX / (10**(tokenInDecimals - 18)));

            executionPrice = _simulateTokenToTokenPriceChange(
                amountIn,
                executionPrice
            );
        } else {
            executionPrice = _simulateWethToTokenPriceChange(
                alphaX,
                executionPrice
            );
        }

        return executionPrice;
    }

    function _simulateWethToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;

        address poolAddressWethToB = executionPrice.lpAddressWethToB;

        (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken,

        ) = _simulateAToBPriceChange(
                alphaX,
                reserveBWeth,
                reserveBToken,
                poolAddressWethToB,
                false
            );

        executionPrice.price = newSpotPriceB;
        executionPrice.aToWethReserve0 = 0;
        executionPrice.aToWethReserve1 = 0;
        executionPrice.wethToBReserve0 = newReserveBWeth;
        executionPrice.wethToBReserve1 = newReserveBToken;

        return executionPrice;
    }

    function _simulateTokenToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        ) = _simulateAToWethPriceChange(alphaX, executionPrice);

        (
            uint256 newSpotPriceB,
            uint128 newReserveBToken,
            uint128 newReserveBWeth
        ) = _simulateWethToBPriceChange(amountOut, executionPrice);

        {
            //Signifying that it weth is token0
            uint256 newTokenToTokenSpotPrice = uint256(
                ConveyorMath.mul64x64(
                    uint128(newSpotPriceA >> 64),
                    uint128(newSpotPriceB >> 64)
                )
            ) << 64;

            executionPrice.price = newTokenToTokenSpotPrice;
            executionPrice.aToWethReserve0 = newReserveAToken;
            executionPrice.aToWethReserve1 = newReserveAWeth;
            executionPrice.wethToBReserve0 = newReserveBWeth;
            executionPrice.wethToBReserve1 = newReserveBToken;
        }
        return executionPrice;
    }

    function _simulateAToWethPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        internal
        returns (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        )
    {
        uint128 reserveAToken = executionPrice.aToWethReserve0;
        uint128 reserveAWeth = executionPrice.aToWethReserve1;
        address poolAddressAToWeth = executionPrice.lpAddressAToWeth;

        (
            newSpotPriceA,
            newReserveAToken,
            newReserveAWeth,
            amountOut
        ) = _simulateAToBPriceChange(
            alphaX,
            reserveAToken,
            reserveAWeth,
            poolAddressAToWeth,
            true
        );
    }

    function _simulateWethToBPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    )
        internal
        returns (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        )
    {
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;
        address poolAddressWethToB = executionPrice.lpAddressWethToB;

        (
            newSpotPriceB,
            newReserveBWeth,
            newReserveBToken,

        ) = _simulateAToBPriceChange(
            alphaX,
            reserveBToken,
            reserveBWeth,
            poolAddressWethToB,
            false
        );
    }

    /// @notice Helper function to determine the spot price change to the lp after introduction alphaX amount into the reserve pool
    /// @param alphaX uint256 amount to be added to reserve_x to get out token_y
    /// @param reserveA current lp reserves for tokenIn and tokenOut
    /// @param reserveB current lp reserves for tokenIn and tokenOut
    /// @return unsigned The amount of proportional spot price change in the pool after adding alphaX to the tokenIn reserves
    function _simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB,
        address pool,
        bool isTokenToWeth
    )
        internal
        returns (
            uint256,
            uint128,
            uint128,
            uint128
        )
    {
        uint128[] memory newReserves = new uint128[](2);

        //If not uni v3 do constant product calculation
        if (_lpIsNotUniV3(pool)) {
            unchecked {
                uint256 denominator = reserveA + alphaX;

                uint256 numerator = FullMath.mulDiv(
                    uint256(reserveA),
                    uint256(reserveB),
                    denominator
                );

                uint256 spotPrice = uint256(
                    ConveyorMath.divUI(numerator, denominator)
                ) << 64;

                require(
                    spotPrice <=
                        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
                    "overflow"
                );

                newReserves[0] = uint128(denominator);
                newReserves[1] = uint128(numerator);

                uint128 amountOut = uint128(
                    getAmountOut(alphaX, reserveA, reserveB)
                );

                return (spotPrice, newReserves[0], newReserves[1], amountOut);
            }
        } else {
            (
                uint128 spotPrice64x64,
                uint128 amountOut
            ) = calculateNextSqrtPriceX96(isTokenToWeth, pool, alphaX);

            newReserves[0] = 1;
            newReserves[1] = 1;

            uint256 spotPrice = uint256(spotPrice64x64) << 64;

            return (spotPrice, newReserves[0], newReserves[1], amountOut);
        }
    }

    ///@notice Helper function to calculate precise price change in a uni v3 pool after alphaX value is added to the liquidity on either token
    ///@param isTokenToWeth boolean indicating whether swap is happening from token->weth or weth->token respectively
    ///@param pool address of the Uniswap v3 pool to simulate the price change on
    ///@param alphaX quantity to be added to the liquidity of tokenIn
    ///@return spotPrice 64.64 fixed point spot price after the input quantity has been added to the pool
    ///@return amountOut quantity recieved on the out token post swap
    function calculateNextSqrtPriceX96(
        bool isTokenToWeth,
        address pool,
        uint256 alphaX
    ) internal returns (uint128 spotPrice, uint128 amountOut) {
        ///@notice sqrtPrice Fixed point 64.96 form token1/token0 exchange rate
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        ///@notice Concentrated liquidity in current price tick range
        uint128 liquidity = IUniswapV3Pool(pool).liquidity();

        ///@notice Get token0/token1 from the pool
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        ///@notice Boolean indicating whether weth is token0 or token1
        bool wethIsToken0 = token0 == WETH ? true : false;

        ///@notice Instantiate nextSqrtPriceX96 to hold adjusted price after simulated swap
        uint160 nextSqrtPriceX96;

        ///@notice Cache pool fee
        uint24 fee = IUniswapV3Pool(pool).fee();

        ///@notice Conditional whether swap is happening from tokenToWeth or wethToToken
        if (isTokenToWeth) {
            if (wethIsToken0) {
                ///@notice If weth is token0 and swap is happening from tokenToWeth ==> token1 = token & alphaX is in token1
                ///@notice Assign amountOut to hold output amount in Weth for subsequent simulation calls
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(token1, WETH, fee, alphaX, 0)
                );

                ///@notice tokenIn is token1 therefore 0for1 is false & alphaX is input into tokenIn liquidity ==> rounding down
                nextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtPriceX96,
                    liquidity,
                    alphaX,
                    false
                );

                ///@notice Convert output to 64.64 fixed point representation
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                spotPrice = ConveyorMath.mul64x64(
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64),
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64)
                );
            } else {
                ///@notice weth is token1 therefore tokenIn is token0, assign amountOut to wethOut value for subsequent simulations
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(token0, WETH, fee, alphaX, 0)
                );

                ///@notice calculate nextSqrtPriceX96 price change on wethOutAmount add false since we are removing the weth liquidity from the pool
                nextSqrtPriceX96 = SqrtPriceMath
                    .getNextSqrtPriceFromAmount1RoundingDown(
                        sqrtPriceX96,
                        liquidity,
                        amountOut,
                        false
                    );

                ///@notice Since weth is token1 we have the correct form of sqrtPrice i.e token1/token0 spot, so just convert to 64.64 and square it
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 spot, since token1 is our tokenIn take the inverse of sqrtSpotPrice64x64 and square it to be in standard form usable for two hop finalSpot calculation
                spotPrice = ConveyorMath.mul64x64(
                    sqrtSpotPrice64x64,
                    sqrtSpotPrice64x64
                );
            }
        } else {
            ///@notice isTokenToWeth =false ==> we are exchanging weth -> token
            if (wethIsToken0) {
                ///@notice since weth is token0 set amountOut to token quoted amount out on alphaX Weth into the pool
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(WETH, token1, fee, alphaX, 0)
                );

                ///@notice amountOut is in our out token, so set nextSqrtPriceX96 to change in price on amountOut value
                ///@notice weth is token 0 so set add to false since we are removing token1 liquidity from the pool
                nextSqrtPriceX96 = SqrtPriceMath
                    .getNextSqrtPriceFromAmount1RoundingDown(
                        sqrtPriceX96,
                        liquidity,
                        amountOut,
                        false
                    );
                ///@notice since token0 = weth token1/token0 is the proper exchange rate so convert to 64.64 and square to yield the spot price
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                spotPrice = ConveyorMath.mul64x64(
                    sqrtSpotPrice64x64,
                    sqrtSpotPrice64x64
                );
            } else {
                ///@notice weth == token1 so initialize amountOut on weth-token0
                amountOut = uint128(
                    iQuoter.quoteExactInputSingle(WETH, token0, fee, alphaX, 0)
                );

                ///@notice set nextSqrtPriceX96 to change on Input alphaX which will be in Weth, since weth is token1 0To1=false
                nextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtPriceX96,
                    liquidity,
                    alphaX,
                    false
                );

                ///@notice convert to 64.64 and take the inverse ^2 to yield token0/token1 spotPrice out
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );
                spotPrice = ConveyorMath.mul64x64(
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64),
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64)
                );
            }
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
        return ConveyorMath.mul128I(spot_price, order_quantity) >= amountOutMin;
    }
}
