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

    ///@notice State variable to track the amount of gas initally alloted during executeOrders.
    uint256 initialTxGas;

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
        ///@notice Initialize the total reward to be paid to the off-chain executor
        uint128 totalBeaconReward;

        uint256 orderOwnersIndex = 0;
        address[] memory orderOwners = new address[](
            tokenToWethBatchOrders[0].batchOwners.length
        );

        ///@notice For each batch in the tokenToWethBatchOrders array
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];
            for (uint256 j = 0; j < batch.batchLength; ) {
                ///@notice Execute each order one by one to avoid double taxing taxed tokens
                Order memory order = getOrderById(batch.orderIds[j]);
                totalBeaconReward += _executeTokenToWethTaxedOrder(
                    batch,
                    order
                );

                ///@notice Update the orderOwners array for gas credit adjustments
                orderOwners[orderOwnersIndex] = batch.batchOwners[j];
                ++orderOwnersIndex;

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        /**@notice Update the total reward payable to the off-chain executor. If the reward is greater than the 
        max reward, set the total reward to the max reward. */
        totalBeaconReward = maxBeaconReward > totalBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

        ///@notice Calculate the execution gas compensation.
        uint256 executionGasCompensation = calculateExecutionGasCompensation(
            orderOwners
        );

        ///@notice Transfer the reward to the off-chain executor.
        safeTransferETH(
            msg.sender,
            totalBeaconReward + executionGasCompensation
        );
    }

    ///@notice Function to execute a single TokenToWethTaxedOrder
    function _executeTokenToWethTaxedOrder(
        TokenToWethBatchOrder memory batch,
        Order memory order
    ) internal returns (uint128 beaconReward) {
        ///@notice Get the UniV3 fee.
        ///@dev This will return 0 if the lp address is a UniV2 address.
        uint24 fee = _getUniV3Fee(batch.lpAddress);

        ///@notice Execute the first swap from tokenIn to Weth
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

        if (amountOutWeth > 0) {
            ///@notice Calculate the protcol fee from the amount of Weth received from the first swap.
            uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

            ///@notice Mark the order as resolved from the limit order system.
            _resolveCompletedOrderAndEmitOrderFufilled(order);

            uint128 conveyorReward;

            ///@notice calculate the reward payable to the off-chain executor
            (conveyorReward, beaconReward) = _calculateReward(
                protocolFee,
                amountOutWeth
            );

            ///@notice Increment the conveyorBalance
            conveyorBalance+= conveyorReward;

            ///@notice Subtract the beacon/conveyor reward from the amountOutWeth and transer the funds to the order.owner
            amountOutWeth = amountOutWeth - (conveyorReward + beaconReward);
            safeTransferETH(order.owner, amountOutWeth);
        } else {
            _cancelOrder(order);
        }
    }

    ///@notice Function to execute a batch of Token to Weth Orders.
    function _executeTokenToWethOrders(Order[] memory orders) internal {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        (
            TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Get the batch of order's targeted on the best priced Lp's
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        ///@notice Pass the batches into the internal execution function to execute each individual batch.
        _executeTokenToWethBatchOrders(tokenToWethBatchOrders, maxBeaconReward);
    }

    ///@notice Function to execute multiple batch orders from TokenIn to Weth.
    ///@param tokenToWethBatchOrders Array of TokenToWeth batches.
    ///@param maxBeaconReward The maximum funds the beacon will recieve after execution.
    function _executeTokenToWethBatchOrders(
        TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        ///@notice Instantiate total beacon reward
        uint256 totalBeaconReward;

        uint256 orderOwnersIndex = 0;
        address[] memory orderOwners = new address[](
            tokenToWethBatchOrders[0].batchOwners.length
        );
        ///@notice Iterate through each tokenToWethBatchOrder
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            ///@notice If 0 order's exist in the batch continue
            if (tokenToWethBatchOrders[i].batchLength > 0) {
                ///@notice Set batch to the i'th batch order
                TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];

                ///@notice Execute the TokenIn to Weth batch
                (
                    uint256 amountOut,
                    uint256 beaconReward
                ) = _executeTokenToWethBatch(tokenToWethBatchOrders[i]);

                ///@notice Accumulate the totalBeaconReward
                totalBeaconReward += beaconReward;

                ///@notice OwnerShares represents the % of ownership over the out amount post execution
                uint256[] memory ownerShares = batch.ownerShares;

                ///@notice amountIn represents the total amountIn on the batch for all orders
                uint256 amountIn = batch.amountIn;

                ///@notice batchOrderLength represents the total amount of orders in the batch
                uint256 batchOrderLength = tokenToWethBatchOrders[i]
                    .batchLength;

                ///@notice Iterate through each order in the batch
                for (uint256 j = 0; j < batchOrderLength; ) {
                    ///@notice Calculate how much to pay each user from the shares they own
                    uint128 orderShare = ConveyorMath.divUI(
                        ownerShares[j],
                        amountIn
                    );

                    ///@notice Multiply the amountOut*orderShare to get the total amount out owned by the order
                    uint256 orderPayout = ConveyorMath.mul64I(
                        orderShare,
                        amountOut
                    );

                    ///@notice Send the order owner their orderPayout
                    safeTransferETH(batch.batchOwners[j], orderPayout);

                    ///@notice Update the orderOwners array for gas credit adjustments
                    orderOwners[orderOwnersIndex] = batch.batchOwners[j];
                    ++orderOwnersIndex;

                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }

        /**@notice If the maxBeaconReward is greater than the totalBeaconReward then keep the totalBeaconReward else set totalBeaconReward
        to the maxBeaconReward
        */
        totalBeaconReward = maxBeaconReward > totalBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

        ///@notice Calculate the execution gas compensation.
        uint256 executionGasCompensation = calculateExecutionGasCompensation(
            orderOwners
        );

        ///@notice Send the Total Reward to the beacon.
        safeTransferETH(
            msg.sender,
            totalBeaconReward + executionGasCompensation
        );
    }

    ///@notice Function to Execute a single batch of TokenIn to Weth Orders.
    ///@param batch A single batch of TokenToWeth orders
    function _executeTokenToWethBatch(TokenToWethBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        ///@notice Get the Uniswap V3 pool fee on the lp address for the batch.
        uint24 fee = _getUniV3Fee(batch.lpAddress);

        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
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

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice Iterate through all orderIds in the batch and delete the orders from the contract.
            for (uint256 i = 0; i < batch.batchLength; ) {
                ///@notice Cache the orderId
                bytes32 orderId = batch.orderIds[i];

                ///@notice Mark the order as resolved from the limit order system.
                _resolveCompletedOrder(orderIdToOrder[orderId]);

                unchecked {
                    ++i;
                }
            }

            ///@notice Emit an order fufilled event to notify the off-chain executors.
            emit OrderFufilled(batch.orderIds);
        }

        ///@notice Increment the conveyor balance by the conveyor reward
        conveyorBalance += conveyorReward;

        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToWethExecutionPrices(Order[] memory orders)
        internal
        view
        returns (TokenToWethExecutionPrice[] memory, uint128)
    {
        ///@notice Get all prices for the pairing
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

        ///@notice Initialize a new TokenToWethExecutionPrice array to store prices.
        TokenToWethExecutionPrice[]
            memory executionPrices = new TokenToWethExecutionPrice[](
                spotReserveAToWeth.length
            );

        ///@notice Scoping to avoid stack too deep.
        {
            ///@notice For each spot reserve, initialize a token to weth execution price.
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                executionPrices[i] = TokenToWethExecutionPrice(
                    spotReserveAToWeth[i].res0,
                    spotReserveAToWeth[i].res1,
                    spotReserveAToWeth[i].spotPrice,
                    lpAddressesAToWeth[i]
                );
            }
        }

        ///@notice Calculate the max beacon reward from the spot reserves.
        uint128 maxBeaconReward = calculateMaxBeaconReward(
            spotReserveAToWeth,
            orders,
            false
        );

        return (executionPrices, maxBeaconReward);
    }

    ///@notice Initialize a new token to weth batch order
    /**@param initArrayLength - The maximum amount of orders that will be included in the batch. This is used to initalize
    arrays in the token to weth batch order struct. */
    ///@param tokenIn - TokenIn for the batch order.
    ///@param lpAddressAToWeth - LP address for the tokenIn/Weth pairing.
    ///@return tokenToWethBatchOrder - Returns a new empty token to weth batch order.
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

    ///@notice Function to batch multiple token to weth orders together.
    ///@param orders - Array of orders to be batched into the most efficient ordering.
    ///@param executionPrices - Array of execution prices available to the batch orders. The batch order will be placed on the best execution price.
    ///@return  tokenToWethBatchOrders - Returns an array of TokenToWethBatchOrder.
    function _batchTokenToWethOrders(
        Order[] memory orders,
        TokenToWethExecutionPrice[] memory executionPrices
    ) internal returns (TokenToWethBatchOrder[] memory) {
        ///@notice Create a new token to weth batch order.
        TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = new TokenToWethBatchOrder[](
                orders.length
            );

        ///@notice Cache the first order in the array.
        Order memory firstOrder = orders[0];

        ///@notice Check if the order is a buy or sell to assign the buy/sell status for the batch.
        bool buyOrder = _buyOrSell(firstOrder);

        ///@notice Assign the batch's tokenIn.
        address batchOrderTokenIn = firstOrder.tokenIn;

        ///@notice Create a variable to track the best execution price in the array of execution prices.
        uint256 currentBestPriceIndex = _findBestTokenToWethExecutionPrice(
            executionPrices,
            buyOrder
        );

        ///@notice Initialize a new token to weth batch order.
        TokenToWethBatchOrder
            memory currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                orders.length,
                batchOrderTokenIn,
                executionPrices[currentBestPriceIndex].lpAddressAToWeth
            );

        ///@notice Initialize a variable to keep track of how many batch orders there are.
        uint256 currentTokenToWethBatchOrdersIndex = 0;

        ///@notice For each order in the orders array.
        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Get the index of the best exectuion price.
            uint256 bestPriceIndex = _findBestTokenToWethExecutionPrice(
                executionPrices,
                buyOrder
            );

            ///@notice if the best price has changed since the last order, add the batch order to the array and update the best price index.
            if (i > 0 && currentBestPriceIndex != bestPriceIndex) {
                ///@notice Add the current batch order to the batch orders array.
                tokenToWethBatchOrders[
                    currentTokenToWethBatchOrdersIndex
                ] = currentTokenToWethBatchOrder;

                ///@notice Increment the amount of to current token to weth batch orders index
                ++currentTokenToWethBatchOrdersIndex;

                ///@notice Update the index of the best execution price.
                currentBestPriceIndex = bestPriceIndex;

                ///@notice Initialize a new batch order.
                currentTokenToWethBatchOrder = _initializeNewTokenToWethBatchOrder(
                    orders.length,
                    batchOrderTokenIn,
                    executionPrices[bestPriceIndex].lpAddressAToWeth
                );
            }

            ///@notice Get the current order.
            Order memory currentOrder = orders[i];

            ///@notice Check that the order meets execution price.
            if (
                _orderMeetsExecutionPrice(
                    currentOrder.price,
                    executionPrices[bestPriceIndex].price,
                    buyOrder
                )
            ) {
                ///@notice Check that the order can execute without hitting slippage.
                if (
                    _orderCanExecute(
                        executionPrices[bestPriceIndex].price,
                        currentOrder.quantity,
                        currentOrder.amountOutMin
                    )
                ) {
                    ///@notice Transfer the tokenIn from the user's wallet to the contract. If the transfer fails, cancel the order.
                    bool success = transferTokensToContract(currentOrder);

                    if (success) {
                        ///@notice Get the batch length of the current batch order.
                        uint256 batchLength = currentTokenToWethBatchOrder
                            .batchLength;

                        ///@notice Add the order to the current batch order.
                        currentTokenToWethBatchOrder.amountIn += currentOrder
                            .quantity;

                        ///@notice Add the owner of the order to the batchOwners.
                        currentTokenToWethBatchOrder.batchOwners[
                            batchLength
                        ] = currentOrder.owner;

                        ///@notice Add the order quantity of the order to ownerShares.
                        currentTokenToWethBatchOrder.ownerShares[
                            batchLength
                        ] = currentOrder.quantity;

                        ///@notice Add the orderId to the batch order.
                        currentTokenToWethBatchOrder.orderIds[
                            batchLength
                        ] = currentOrder.orderId;

                        ///@notice Add the amountOutMin to the batch order.
                        currentTokenToWethBatchOrder
                            .amountOutMin += currentOrder.amountOutMin;

                        ///@notice Increment the batch length.
                        ++currentTokenToWethBatchOrder.batchLength;

                        ///@notice Update the best execution price.
                        (
                            executionPrices[bestPriceIndex]
                        ) = simulateTokenToWethPriceChange(
                            uint128(currentOrder.quantity),
                            executionPrices[bestPriceIndex]
                        );
                    }
                } else {
                    ///@notice If the order can not execute due to slippage, revert to notify the off-chain executor.
                    revert OrderHasInsufficientSlippage(currentOrder.orderId);
                }
            }

            unchecked {
                ++i;
            }
        }

        ///@notice Add the last batch to the tokenToWethBatchOrders array.
        tokenToWethBatchOrders[
            currentTokenToWethBatchOrdersIndex
        ] = currentTokenToWethBatchOrder;

        return tokenToWethBatchOrders;
    }

    ///@notice Transfer the order quantity to the contract.
    ///@return success - Boolean to indicate if the transfer was successful.
    function transferTokensToContract(Order memory order)
        internal
        returns (bool success)
    {
        try
            IERC20(order.tokenIn).transferFrom(
                order.owner,
                address(this),
                order.quantity
            )
        {} catch {
            _cancelOrder(order);
            return false;
        }
        return true;
    }

    ///@notice Function to return the index of the best price in the executionPrices array.
    ///@param executionPrices - Array of execution prices to evaluate.
    ///@param buyOrder - Boolean indicating whether the order is a buy or sell.
    ///@return bestPriceIndex - Index of the best price in the executionPrices array.
    function _findBestTokenToWethExecutionPrice(
        TokenToWethExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice If the order is a buy order, set the initial best price at 0.
        if (buyOrder) {
            uint256 bestPrice = 0;

            ///@notice For each exectution price in the executionPrices array.
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        } else {
            ///@notice If the order is a sell order, set the initial best price at max uint256.
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;

                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice > bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }

                unchecked {
                    ++i;
                }
            }
        }
    }

    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function _executeTokenToTokenOrders(Order[] memory orders) internal {
        ///@notice Get all execution prices.
        (
            TokenToTokenExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToTokenExecutionPrices(orders);

        ///@notice Batch the orders into optimized quantities to result in the best execution price and gas cost for each order.
        TokenToTokenBatchOrder[]
            memory tokenToTokenBatchOrders = _batchTokenToTokenOrders(
                orders,
                executionPrices
            );

        ///@notice Execute the batches of orders.
        _executeTokenToTokenBatchOrders(
            tokenToTokenBatchOrders,
            maxBeaconReward
        );
    }

    ///@notice Function to execute an array of TokenToTokenTaxed orders.
    ///@param orders - Array of orders to be executed.
    function _executeTokenToTokenTaxedOrders(Order[] memory orders) internal {
        ///@notice Get all execution prices.
        (
            TokenToTokenExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToTokenExecutionPrices(orders);

        ///@notice Batch the orders into optimized quantities to result in the best execution price and gas cost for each order.
        TokenToTokenBatchOrder[]
            memory tokenToTokenBatchOrders = _batchTokenToTokenOrders(
                orders,
                executionPrices
            );

        ///@notice Execute the batches of orders.
        _executeTokenToTokenBatchTaxedOrders(
            tokenToTokenBatchOrders,
            maxBeaconReward
        );
    }

    ///@notice Function to execute multiple batch orders from TokenIn to TokenOut for taxed orders.
    ///@param tokenToTokenBatchOrders Array of TokenToToken batches.
    ///@param maxBeaconReward The maximum funds the beacon will recieve after execution.
    function _executeTokenToTokenBatchTaxedOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        ///@notice For each batch order in the tokenToTokenBatchOrders array.
        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; ) {
            TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];

            ///@notice Initialize the total reward to be paid to the off-chain executor
            uint128 totalBeaconReward;

            uint256 orderOwnersIndex = 0;
            address[] memory orderOwners = new address[](
                tokenToTokenBatchOrders[0].batchOwners.length
            );

            ///@notice For each order in the batch.
            for (uint256 j = 0; j < batch.batchLength; ) {
                Order memory order = getOrderById(batch.orderIds[j]);

                ///@notice Execute the order.
                totalBeaconReward += _executeTokenToTokenTaxedOrder(
                    tokenToTokenBatchOrders[i],
                    order
                );

                ///@notice Update the orderOwners array for gas credit adjustments
                orderOwners[orderOwnersIndex] = batch.batchOwners[j];
                ++orderOwnersIndex;

                unchecked {
                    ++j;
                }
            }

            ///@notice If the total compensation awarded to the executor is greater than the max reward, set the reward to the max reward.
            totalBeaconReward = maxBeaconReward > totalBeaconReward
                ? totalBeaconReward
                : maxBeaconReward;

            ///@notice Calculate the execution gas compensation.
            uint256 executionGasCompensation = calculateExecutionGasCompensation(
                    orderOwners
                );
            ///@notice Send the reward to the off-chain executor.
            safeTransferETH(
                msg.sender,
                totalBeaconReward + executionGasCompensation
            );

            unchecked {
                ++i;
            }
        }
    }

    ///@notice Function to execute a single token to token taxed order
    ///@param batch - The batch containing order details (ex. lp address).
    ///@param order - The order to execute.
    ///@return beaconReward - The compensation rewarded to the off-chain executor who called the executeOrders function.
    function _executeTokenToTokenTaxedOrder(
        TokenToTokenBatchOrder memory batch,
        Order memory order
    ) internal returns (uint128) {
        ///@notice Initialize local variables to avoid stack too deep errors.
        uint128 protocolFee;
        uint128 beaconReward;
        uint256 amountInWethToB;
        uint24 fee;
        uint128 conveyorReward;

        ///@notice If the tokenIn is not Weth, swap from weth to token.
        if (order.tokenIn != WETH) {
            amountInWethToB = _executeSwapTokenToWeth(batch, order);
        } else {
            ///@notice Otherwise, if the tokenIn is weth, calculate the reward first.
            protocolFee = _calculateFee(uint128(order.quantity), USDC, WETH);

            ///@notice Take out beacon reward from the order quantity.
            (conveyorReward, beaconReward) = _calculateReward(
                protocolFee,
                uint128(order.quantity)
            );

            ///@notice Get the amountIn for Weth to tokenB
            amountInWethToB = order.quantity - (beaconReward + conveyorReward);
        }

        ///@notice Increment the conveyorBalance by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the UniV3 fee for the lp address.
        fee = _getUniV3Fee(batch.lpAddressWethToB);

        ///@notice Swap weth for tokenB
        uint256 amountOut = _swap(
            WETH,
            order.tokenOut,
            batch.lpAddressWethToB,
            fee,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(this)
        );

        ///@notice If the swap was successful.
        if (amountOut > 0) {
            ///@notice Mark the order as resolved from the limit order system.
            _resolveCompletedOrderAndEmitOrderFufilled(order);
        } else {
            ///@notice Cancel the order.
            _cancelOrder(order);
        }

        return beaconReward;
    }

    ///@notice Function to execute a swap from token to Weth.
    ///@param batch - The batch containing order details (ex. lp address).
    ///@param order - The order to execute.
    ///@return amountOutWeth - The amount out from the swap in Weth.
    function _executeSwapTokenToWeth(
        TokenToTokenBatchOrder memory batch,
        Order memory order
    ) internal returns (uint128 amountOutWeth) {
        ///@notice Get the UniV3 fee, this will be 0 if the lp is not UniV3.
        uint24 fee = _getUniV3Fee(batch.lpAddressAToWeth);

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
            batch.lpAddressAToWeth,
            order.quantity,
            batch.orderIds[0],
            order.taxIn
        );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
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

        ///@notice Take out fees from the amountOut.
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Function to execute token to token batch orders.
    ///@param tokenToTokenBatchOrders - Array of token to token batch orders.
    ///@param maxBeaconReward - Max beacon reward for the batch.
    function _executeTokenToTokenBatchOrders(
        TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        uint256 totalBeaconReward;

        uint256 orderOwnersIndex = 0;
        address[] memory orderOwners = new address[](
            tokenToTokenBatchOrders[0].batchOwners.length
        );

        ///@notice For each batch order in the array.
        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; ) {
            TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];

            ///@notice Execute the batch order
            (
                uint256 amountOut,
                uint256 beaconReward
            ) = _executeTokenToTokenBatch(tokenToTokenBatchOrders[i]);

            ///@notice aAd the beacon reward to the totalBeaconReward
            totalBeaconReward += beaconReward;

            ///@notice Calculate the amountOut owed to each order owner in the batch.
            uint256[] memory ownerShares = batch.ownerShares;
            uint256 amountIn = batch.amountIn;
            uint256 batchOrderLength = tokenToTokenBatchOrders[i].batchLength;
            for (uint256 j = 0; j < batchOrderLength; ) {
                ///@notice Calculate how much to pay each user from the shares they own
                uint128 orderShare = ConveyorMath.divUI(
                    ownerShares[j],
                    amountIn
                );

                ///@notice Calculate the orderPayout to the order owner.
                uint256 orderPayout = ConveyorMath.mul64I(
                    orderShare,
                    amountOut
                );

                ///@notice Send the order payout to the order owner.
                safeTransferETH(batch.batchOwners[j], orderPayout);

                ///@notice Update the orderOwners array for gas credit adjustments
                orderOwners[orderOwnersIndex] = batch.batchOwners[j];
                ++orderOwnersIndex;

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        ///@notice Adjust the totalBeaconReward according to the maxBeaconReward.
        totalBeaconReward = totalBeaconReward < maxBeaconReward
            ? totalBeaconReward
            : maxBeaconReward;

        ///@notice Calculate the execution gas compensation.
        uint256 executionGasCompensation = calculateExecutionGasCompensation(
            orderOwners
        );

        ///@notice Send the off-chain executor their reward.
        safeTransferETH(
            msg.sender,
            totalBeaconReward + executionGasCompensation
        );
    }

    ///@notice Helper function to calculate amountOutMin value agnostically across dexes on the first hop from tokenA to WETH.
    ///@param lpAddressAToWeth - lp address of A to weth pair.
    ///@param amountInOrder - The amountIn for the swap.
    ///@param orderId - The unique identifier of the order.
    ///@param taxIn - The token tax for the tokenIn. If the token is not taxed, this value is 0.
    function calculateAmountOutMinAToWeth(
        address lpAddressAToWeth,
        uint256 amountInOrder,
        bytes32 orderId,
        uint16 taxIn
    ) internal returns (uint256 amountOutMinAToWeth) {
        ///@notice Check if the lp is UniV3
        if (!_lpIsNotUniV3(lpAddressAToWeth)) {
            Order memory order = getOrderById(orderId);

            ///@notice 1000==100% so divide amountInOrder *taxIn by 10**5 to adjust to correct base
            uint256 amountInBuffer = (amountInOrder * taxIn) / 10**5;
            uint256 amountIn = amountInOrder - amountInBuffer;

            ///@notice Calculate the amountOutMin for the swap.
            amountOutMinAToWeth = iQuoter.quoteExactInputSingle(
                order.tokenIn,
                WETH,
                order.feeIn,
                amountIn,
                0
            );
        } else {
            ///@notice Otherwise if the lp is a UniV2 LP.

            ///@notice Get the reserves from the pool.
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(
                lpAddressAToWeth
            ).getReserves();

            ///@notice Initialize the reserve0 and reserve1 depending on if Weth is token0 or token1.
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

    ///@notice Function to get the amountOut from a UniV2 lp.
    ///@param amountIn - AmountIn for the swap.
    ///@param reserveIn - tokenIn reserve for the swap.
    ///@param reserveOut - tokenOut reserve for the swap.
    ///@return amountOut - AmountOut from the given parameters.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) {
            revert InsufficientInputAmount();
        }

        if (reserveIn == 0) {
            revert InsufficientLiquidity();
        }

        if (reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    ///@notice Function to execute a token to token batch
    ///@param batch - The token to token batch to execute.
    ///@return amountOut - The amount out recevied from the swap.
    ///@return beaconReward - Compensation reward amount to be sent to the off-chain logic executor.
    function _executeTokenToTokenBatch(TokenToTokenBatchOrder memory batch)
        internal
        returns (uint256, uint256)
    {
        uint128 protocolFee;
        uint128 beaconReward;
        uint128 conveyorReward;
        uint256 amountInWethToB;
        uint24 fee;

        ///@notice Check that the batch is not empty.
        if (!(batch.batchLength == 0)) {
            ///@notice If the tokenIn is not weth.
            if (batch.tokenIn != WETH) {
                ///@notice Calculate the amountOutMin for tokenA to Weth.
                uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
                    batch.lpAddressAToWeth,
                    batch.amountIn,
                    batch.orderIds[0],
                    0
                );

                ///@notice Get the UniV3 fee for the tokenA to Weth swap.
                fee = _getUniV3Fee(batch.lpAddressAToWeth);

                ///@notice Swap from tokenA to Weth.
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

                if (amountOutWeth == 0) {
                    revert InsufficientOutputAmount();
                }

                ///@notice Take out the fees from the amountOutWeth
                protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

                ///@notice Calculate the conveyorReward and the off-chain logic executor reward.
                (conveyorReward, beaconReward) = _calculateReward(
                    protocolFee,
                    amountOutWeth
                );

                ///@notice Increment the conveyor balance by the conveyor reward.
                conveyorBalance += conveyorReward;

                ///@notice Get the amountIn for the Weth to tokenB swap.
                amountInWethToB =
                    amountOutWeth -
                    (beaconReward + conveyorReward);
            } else {
                ///@notice Otherwise, if the tokenIn is Weth

                ///@notice Take out fees from the batch amountIn since token0 is weth.
                protocolFee = _calculateFee(
                    uint128(batch.amountIn),
                    USDC,
                    WETH
                );

                ///@notice Calculate the conveyorReward and the off-chain logic executor reward.
                (conveyorReward, beaconReward) = _calculateReward(
                    protocolFee,
                    uint128(batch.amountIn)
                );

                ///@notice Increment the conveyor balance by the conveyor reward.
                conveyorBalance += conveyorReward;

                ///@notice Get the amountIn for the Weth to tokenB swap.
                amountInWethToB =
                    batch.amountIn -
                    (beaconReward + conveyorReward);
            }

            ///@notice Get the UniV3 fee for the Weth to tokenB swap.
            fee = _getUniV3Fee(batch.lpAddressWethToB);

            ///@notice Swap Weth for tokenB.
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

            if (amountOutInB == 0) {
                revert InsufficientOutputAmount();
            }

            ///@notice Scoping to avoid stack too deep errors.
            {
                ///@notice Iterate through all orderIds in the batch and delete the orders from queue post execution.
                for (uint256 i = 0; i < batch.batchLength; ) {
                    bytes32 orderId = batch.orderIds[i];

                    ///@notice Mark the order as resolved from the system.
                    _resolveCompletedOrder(orderIdToOrder[orderId]);

                    unchecked {
                        ++i;
                    }
                }

                ///@notice Emit an order fufilled event to notify the off-chain executors.
                emit OrderFufilled(batch.orderIds);
            }

            return (amountOutInB, uint256(beaconReward));
        } else {
            ///@notice If there are no orders in the batch, return 0 values for the amountOut (in tokenB) and the off-chain executor reward.
            return (0, 0);
        }
    }

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToTokenExecutionPrices(Order[] memory orders)
        internal
        view
        returns (TokenToTokenExecutionPrice[] memory, uint128)
    {
        address tokenIn = orders[0].tokenIn;
        ///@notice Get all prices for the pairing tokenIn to Weth
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(tokenIn, WETH, orders[0].feeIn);

        ///@notice Get all prices for the pairing Weth to tokenOut
        (
            SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = _getAllPrices(WETH, orders[0].tokenOut, orders[0].feeOut);

        ///@notice Initialize a new TokenToTokenExecutionPrice array to store prices.
        TokenToTokenExecutionPrice[]
            memory executionPrices = new TokenToTokenExecutionPrice[](
                spotReserveAToWeth.length * spotReserveWethToB.length
            );

        ///@notice If TokenIn is Weth
        if (tokenIn == WETH) {
            ///@notice Iterate through each SpotReserve on Weth to TokenB
            for (uint256 i = 0; i < spotReserveWethToB.length; ++i) {
                ///@notice Then set res0, and res1 for tokenInToWeth to 0 and lpAddressAToWeth to the 0 address
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
            ///@notice Initialize index to 0
            uint256 index = 0;
            ///@notice Iterate through each SpotReserve on TokenA to Weth
            for (uint256 i = 0; i < spotReserveAToWeth.length; ) {
                ///@notice Iterate through each SpotReserve on Weth to TokenB
                for (uint256 j = 0; j < spotReserveWethToB.length; ) {
                    ///@notice Calculate the spot price from tokenA to tokenB represented as 128.128 fixed point.
                    uint256 spotPriceFinal = uint256(
                        _calculateTokenToWethToTokenSpotPrice(
                            spotReserveAToWeth[i].spotPrice,
                            spotReserveWethToB[j].spotPrice
                        )
                    ) << 64;

                    ///@notice Set the executionPrices at index to TokenToTokenExecutionPrice
                    executionPrices[index] = TokenToTokenExecutionPrice(
                        spotReserveAToWeth[i].res0,
                        spotReserveAToWeth[i].res1,
                        spotReserveWethToB[j].res1,
                        spotReserveWethToB[j].res0,
                        spotPriceFinal,
                        lpAddressesAToWeth[i],
                        lpAddressWethToB[j]
                    );
                    ///@notice Increment the index
                    unchecked {
                        ++index;
                    }

                    unchecked {
                        ++j;
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        ///@notice Get the Max beacon reward on the SpotReserves
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

    ///@notice Function to batch multiple token to weth orders together.
    ///@param orders - Array of orders to be batched into the most efficient ordering.
    ///@param executionPrices - Array of execution prices available to the batch orders. The batch order will be placed on the best execution price.
    ///@return  tokenToTokenBatchOrders - Returns an array of TokenToWethBatchOrder.
    function _batchTokenToTokenOrders(
        Order[] memory orders,
        TokenToTokenExecutionPrice[] memory executionPrices
    )
        internal
        returns (TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders)
    {
        ///@notice Create a new token to weth batch order.
        tokenToTokenBatchOrders = new TokenToTokenBatchOrder[](orders.length);

        ///@notice Cache the first order in the array.
        Order memory firstOrder = orders[0];

        ///@notice Check if the order is a buy or sell to assign the buy/sell status for the batch.
        bool buyOrder = _buyOrSell(firstOrder);

        ///@notice Assign the batch's tokenIn.
        address batchOrderTokenIn = firstOrder.tokenIn;

        ///@notice Assign the batch's tokenOut.
        address batchOrderTokenOut = firstOrder.tokenOut;

        ///@notice Create a variable to track the best execution price in the array of execution prices.
        uint256 currentBestPriceIndex = _findBestTokenToTokenExecutionPrice(
            executionPrices,
            buyOrder
        );

        ///@notice Initialize a new token to token batch order.
        TokenToTokenBatchOrder
            memory currentTokenToTokenBatchOrder = _initializeNewTokenToTokenBatchOrder(
                orders.length,
                batchOrderTokenIn,
                batchOrderTokenOut,
                executionPrices[currentBestPriceIndex].lpAddressAToWeth,
                executionPrices[currentBestPriceIndex].lpAddressWethToB
            );

        ///@notice Initialize a variable to keep track of how many batch orders there are.
        uint256 currentTokenToTokenBatchOrdersIndex = 0;

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice For each order in the orders array.
            for (uint256 i = 0; i < orders.length; ) {
                ///@notice Get the index of the best exectuion price.
                uint256 bestPriceIndex = _findBestTokenToTokenExecutionPrice(
                    executionPrices,
                    buyOrder
                );

                ///@notice if the best price has changed since the last order, add the batch order to the array and update the best price index.
                if (i > 0 && currentBestPriceIndex != bestPriceIndex) {
                    ///@notice add the current batch order to the batch orders array
                    tokenToTokenBatchOrders[
                        currentTokenToTokenBatchOrdersIndex
                    ] = currentTokenToTokenBatchOrder;

                    ///@notice Increment the amount of to current token to weth batch orders index
                    currentTokenToTokenBatchOrdersIndex++;

                    ///@notice Update the index of the best execution price.
                    currentBestPriceIndex = bestPriceIndex;

                    ///@notice Initialize a new batch order.
                    currentTokenToTokenBatchOrder = _initializeNewTokenToTokenBatchOrder(
                        orders.length,
                        batchOrderTokenIn,
                        batchOrderTokenOut,
                        executionPrices[bestPriceIndex].lpAddressAToWeth,
                        executionPrices[bestPriceIndex].lpAddressWethToB
                    );
                }

                ///@notice Get the current order.
                Order memory currentOrder = orders[i];

                ///@notice Check that the order meets execution price.
                if (
                    _orderMeetsExecutionPrice(
                        currentOrder.price,
                        executionPrices[bestPriceIndex].price,
                        buyOrder
                    )
                ) {
                    ///@notice Check that the order can execute without hitting slippage.
                    if (
                        _orderCanExecute(
                            executionPrices[bestPriceIndex].price,
                            currentOrder.quantity,
                            currentOrder.amountOutMin
                        )
                    ) {
                        ///@notice Transfer the tokenIn from the user's wallet to the contract. If the transfer fails, cancel the order.
                        bool success = transferTokensToContract(currentOrder);

                        if (success) {
                            ///@notice Get the batch length of the current batch order.
                            uint256 batchLength = currentTokenToTokenBatchOrder
                                .batchLength;

                            ///@notice Add the order to the current batch order.
                            currentTokenToTokenBatchOrder
                                .amountIn += currentOrder.quantity;

                            ///@notice Add the amountOutMin to the batch order.
                            currentTokenToTokenBatchOrder
                                .amountOutMin += currentOrder.amountOutMin;

                            ///@notice Add the owner of the order to the batchOwners.
                            currentTokenToTokenBatchOrder.batchOwners[
                                    batchLength
                                ] = currentOrder.owner;

                            ///@notice Add the order quantity of the order to ownerShares.
                            currentTokenToTokenBatchOrder.ownerShares[
                                    batchLength
                                ] = currentOrder.quantity;

                            ///@notice Add the orderId to the batch order.
                            currentTokenToTokenBatchOrder.orderIds[
                                    batchLength
                                ] = currentOrder.orderId;

                            ///@notice Increment the batch length.
                            ++currentTokenToTokenBatchOrder.batchLength;

                            ///@notice Update the best execution price.
                            (
                                executionPrices[bestPriceIndex]
                            ) = simulateTokenToTokenPriceChange(
                                uint128(currentTokenToTokenBatchOrder.amountIn),
                                executionPrices[bestPriceIndex]
                            );
                        }
                    } else {
                        ///@notice If the order can not execute due to slippage, revert to notify the off-chain executor. 
                        revert OrderHasInsufficientSlippage(currentOrder.orderId);
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        ///@notice add the last batch to the tokenToWethBatchOrders array
        tokenToTokenBatchOrders[
            currentTokenToTokenBatchOrdersIndex
        ] = currentTokenToTokenBatchOrder;
    }

    ///@notice Function to return the index of the best price in the executionPrices array.
    ///@param executionPrices - Array of execution prices to evaluate.
    ///@param buyOrder - Boolean indicating whether the order is a buy or sell.
    ///@return bestPriceIndex - Index of the best price in the executionPrices array.
    function _findBestTokenToTokenExecutionPrice(
        TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) internal pure returns (uint256 bestPriceIndex) {
        ///@notice If the order is a buy order, set the initial best price at 0.
        if (buyOrder) {
            uint256 bestPrice = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            ///@notice For each exectution price in the executionPrices array.
            for (uint256 i = 0; i < executionPrices.length; ) {
                uint256 executionPrice = executionPrices[i].price;
                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice < bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            uint256 bestPrice = 0;
            ///@notice If the order is a sell order, set the initial best price at max uint256.
            for (uint256 i = 0; i < executionPrices.length; i++) {
                uint256 executionPrice = executionPrices[i].price;
                ///@notice If the execution price is better than the best exectuion price, update the bestPriceIndex.
                if (executionPrice > bestPrice && executionPrice != 0) {
                    bestPrice = executionPrice;
                    bestPriceIndex = i;
                }
            }
        }
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

    ///@notice Function to retrieve the buy/sell status of a single order.
    ///@param order Order to determine buy/sell status on.
    ///@return bool Boolean indicating the buy/sell status of the order.
    function _buyOrSell(Order memory order) internal pure returns (bool) {
        if (order.buy) {
            return true;
        } else {
            return false;
        }
    }

    ///@notice Fallback function to receive ether.
    // receive() external payable {}

    ///@notice Function to simulate the price change from TokanA to Weth on an amount into the pool
    ///@param alphaX The amount supplied to the TokenA reserves of the pool.
    ///@param executionPrice The TokenToWethExecutionPrice to simulate the price change on.
    function simulateTokenToWethPriceChange(
        uint128 alphaX,
        TokenToWethExecutionPrice memory executionPrice
    ) internal returns (TokenToWethExecutionPrice memory) {
        ///@notice Cache the liquidity pool address
        address pool = executionPrice.lpAddressAToWeth;

        ///@notice Cache token0 and token1 from the pool address
        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();

        ///@notice Get the decimals of the tokenIn on the swap
        uint8 tokenInDecimals = token1 == WETH
            ? IERC20(token0).decimals()
            : IERC20(token1).decimals();

        ///@notice Convert to 18 decimals to have correct price change on the reserve quantities in common 18 decimal form
        uint128 amountIn = tokenInDecimals <= 18
            ? uint128(alphaX * 10**(18 - tokenInDecimals))
            : uint128(alphaX / (10**(tokenInDecimals - 18)));

        ///@notice Simulate the price change on the 18 decimal amountIn quantity, and set executionPrice struct to the updated quantities.
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

    ///@notice Function to simulate the TokenToToken price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
    function simulateTokenToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        ///@notice Check if the reserves are set to 0. This indicated the tokenPair is Weth to TokenOut if true.
        if (
            executionPrice.aToWethReserve0 != 0 &&
            executionPrice.aToWethReserve1 != 0
        ) {
            ///@notice Initialize variables to prevent stack too deep
            address pool = executionPrice.lpAddressAToWeth;
            address token0;
            address token1;
            bool _isUniV2 = _lpIsNotUniV3(pool);
            ///@notice Scope to prevent stack too deep.
            {
                ///@notice Check if the pool is Uni V2 and get the token0 and token1 address.
                if (_isUniV2) {
                    token0 = IUniswapV2Pair(pool).token0();
                    token1 = IUniswapV2Pair(pool).token1();
                } else {
                    token0 = IUniswapV3Pool(pool).token0();
                    token1 = IUniswapV3Pool(pool).token1();
                }
            }

            ///@notice Get the tokenIn decimals
            uint8 tokenInDecimals = token1 == WETH
                ? IERC20(token0).decimals()
                : IERC20(token1).decimals();

            ///@notice Convert to 18 decimals to have correct price change on the reserve quantities in common 18 decimal form.
            uint128 amountIn = tokenInDecimals <= 18
                ? uint128(alphaX * 10**(18 - tokenInDecimals))
                : uint128(alphaX / (10**(tokenInDecimals - 18)));

            ///@notice Abstracted function call to simulate the token to token price change on the common decimal amountIn
            executionPrice = _simulateTokenToTokenPriceChange(
                amountIn,
                executionPrice
            );
        } else {
            ///@notice Abstracted function call to simulate the weth to token price change on the common decimal amountIn
            executionPrice = _simulateWethToTokenPriceChange(
                alphaX,
                executionPrice
            );
        }

        return executionPrice;
    }

    ///@notice Function to simulate the WethToToken price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
    function _simulateWethToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        ///@notice Cache the Weth and TokenOut reserves
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;

        ///@notice Cache the pool address
        address poolAddressWethToB = executionPrice.lpAddressWethToB;

        ///@notice Get the simulated spot price and reserve values.
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

        ///@notice Update TokenToTokenExecutionPrice to the new simulated values.
        executionPrice.price = newSpotPriceB;
        executionPrice.aToWethReserve0 = 0;
        executionPrice.aToWethReserve1 = 0;
        executionPrice.wethToBReserve0 = newReserveBWeth;
        executionPrice.wethToBReserve1 = newReserveBToken;

        return executionPrice;
    }

    ///@notice Function to simulate the TokenToToken price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
    function _simulateTokenToTokenPriceChange(
        uint128 alphaX,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (TokenToTokenExecutionPrice memory) {
        ///@notice Retrive the new simulated spot price, reserve values, and amount out on the TokenIn To Weth pool
        (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        ) = _simulateAToWethPriceChange(alphaX, executionPrice);

        ///@notice Retrive the new simulated spot price, and reserve values on the Weth to tokenOut pool.
        ///@notice Use the amountOut value from the previous simulation as the amountIn on the current simulation.
        (
            uint256 newSpotPriceB,
            uint128 newReserveBToken,
            uint128 newReserveBWeth
        ) = _simulateWethToBPriceChange(amountOut, executionPrice);

        {
            ///@notice Calculate the new spot price over both swaps from the simulated values.
            uint256 newTokenToTokenSpotPrice = uint256(
                ConveyorMath.mul64x64(
                    uint128(newSpotPriceA >> 64),
                    uint128(newSpotPriceB >> 64)
                )
            ) << 64;

            ///@notice Update executionPrice to the simulated values, and return executionPrice.
            executionPrice.price = newTokenToTokenSpotPrice;
            executionPrice.aToWethReserve0 = newReserveAToken;
            executionPrice.aToWethReserve1 = newReserveAWeth;
            executionPrice.wethToBReserve0 = newReserveBWeth;
            executionPrice.wethToBReserve1 = newReserveBToken;
        }
        return executionPrice;
    }

    ///@notice Function to simulate the AToWeth price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
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
        ///@notice Cache the Reserves and the pool address on the liquidity pool
        uint128 reserveAToken = executionPrice.aToWethReserve0;
        uint128 reserveAWeth = executionPrice.aToWethReserve1;
        address poolAddressAToWeth = executionPrice.lpAddressAToWeth;

        ///@notice Simulate the price change from TokenIn To Weth and return the values.
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

    ///@notice Function to simulate the WethToB price change on a pair.
    ///@param alphaX - The input quantity to simulate the price change on.
    ///@param executionPrice - The TokenToTokenExecutionPrice to simulate the price change on.
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
        ///@notice Cache the reserve values, and the pool address on the token pair.
        uint128 reserveBWeth = executionPrice.wethToBReserve0;
        uint128 reserveBToken = executionPrice.wethToBReserve1;
        address poolAddressWethToB = executionPrice.lpAddressWethToB;

        ///@notice Simulate the Weth to TokenOut price change and return the values.
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

    /// @notice Function to calculate the price change of a token pair on a specified input quantity.
    /// @param alphaX Quantity to be added into the TokenA reserves
    /// @param reserveA Reserves of tokenA
    /// @param reserveB Reserves of tokenB
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
        ///@notice Initialize Array to hold the simulated reserve quantities.
        uint128[] memory newReserves = new uint128[](2);

        ///@notice If the liquidity pool is not Uniswap V3 then the calculation is different.
        if (_lpIsNotUniV3(pool)) {
            unchecked {
                ///@notice Supply alphaX to the tokenA reserves.
                uint256 denominator = reserveA + alphaX;

                ///@notice Numerator is the new tokenB reserve quantity i.e k/(reserveA+alphaX)
                uint256 numerator = FullMath.mulDiv(
                    uint256(reserveA),
                    uint256(reserveB),
                    denominator
                );

                ///@notice Spot price = reserveB/reserveA
                uint256 spotPrice = uint256(
                    ConveyorMath.divUI(numerator, denominator)
                ) << 64;

                ///@notice Update update the new reserves array to the simulated reserve values.
                newReserves[0] = uint128(denominator);
                newReserves[1] = uint128(numerator);

                ///@notice Set the amountOut of the swap on alphaX input amount.
                uint128 amountOut = uint128(
                    getAmountOut(alphaX, reserveA, reserveB)
                );

                return (spotPrice, newReserves[0], newReserves[1], amountOut);
            }
            ///@notice If the liquidity pool is Uniswap V3.
        } else {
            ///@notice Get the Uniswap V3 spot price change and amountOut from the simuulating alphaX on the pool.
            (
                uint128 spotPrice64x64,
                uint128 amountOut
            ) = calculateNextSqrtPriceX96(isTokenToWeth, pool, alphaX);

            ///@notice Set the reserves to 0 since they are not required for Uniswap V3
            newReserves[0] = 0;
            newReserves[1] = 0;

            ///@notice Left shift 64 to adjust spot price to 128.128 fixed point
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

                ///@notice sqrtSpotPrice64x64 == token1/token0 spot, since token1 is our tokenIn take the inverse of sqrtSpotPrice64x64 and square it to be in standard form usable for two hop finalSpot calculation
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

                ///@notice sqrtSpotPrice64x64 == token1/token0 which is the correct direction so, simply square the 64.64 sqrt price. 
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
                ///@notice Since token0 = weth token1/token0 is the proper exchange rate so convert to 64.64 and square to yield the spot price
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 which is the correct direction so, simply square the 64.64 sqrt price. 
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

                ///@notice Convert to 64.64.
                uint128 sqrtSpotPrice64x64 = ConveyorTickMath.fromX96(
                    nextSqrtPriceX96
                );

                ///@notice sqrtSpotPrice64x64 == token1/token0 spot, since token1 is our tokenIn take the inverse of sqrtSpotPrice64x64 and square it to be in standard form usable for two hop finalSpot calculation
                spotPrice = ConveyorMath.mul64x64(
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64),
                    ConveyorMath.div64x64(uint128(1) << 64, sqrtSpotPrice64x64)
                );
            }
        }
    }

    /// @notice Function to determine if an order meets the execution price.
    ///@param orderPrice The Spot price for execution of the order.
    ///@param executionPrice The current execution price of the best prices lp.
    ///@param buyOrder The buy/sell status of the order.
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

    ///@notice Checks if order can complete without hitting slippage
    ///@param spot_price The spot price of the liquidity pool.
    ///@param order_quantity The input quantity of the order.
    ///@param amountOutMin The slippage set by the order owner.
    function _orderCanExecute(
        uint256 spot_price,
        uint256 order_quantity,
        uint256 amountOutMin
    ) internal pure returns (bool) {
        return ConveyorMath.mul128I(spot_price, order_quantity) >= amountOutMin;
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner nonReentrant {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
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
}
