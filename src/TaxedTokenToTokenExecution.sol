// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/ConveyorMath.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "./OrderRouter.sol";
import "./ConveyorErrors.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/interfaces/token/IWETH.sol";
import "../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../lib/libraries/ConveyorTickMath.sol";
import "./IOrderBook.sol";
import "./IOrderRouter.sol";
import "./LimitOrderBatcher.sol";

/// @title OrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract TaxedTokenToTokenExecution is LimitOrderBatcher {
    // ========================================= Modifiers =============================================

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

    // ========================================= Constants  =============================================

    ///@notice The USD pegged token address for the chain.
    address immutable USDC;

    ///@notice IQuoter instance to quote the amountOut for a given amountIn on a UniV3 pool.
    IQuoter immutable iQuoter;

    ///@notice Contract address of OrderBook.
    address immutable orderBookAddress;

    address immutable ORDER_ROUTER;

    address owner;
    // ========================================= Constructor =============================================

    ///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _quoterAddress - Address for the IQuoter instance.
    ///@param _orderRouter - Address of the OrderRouter contract. 
    constructor(
        address _weth,
        address _usdc,
        address _quoterAddress,
        address _orderRouter,
        address _orderBookAddress
    ) LimitOrderBatcher(_weth, _quoterAddress, _orderRouter)
    {
        orderBookAddress = _orderBookAddress;
        iQuoter = IQuoter(_quoterAddress);
        USDC = _usdc;
        ORDER_ROUTER= _orderRouter;
        owner = msg.sender;
    }


    // ========================================= FUNCTIONS =============================================

    // ==================== Order Execution Functions =========================


    ///@notice Function to execute orders from a taxed token to Weth.
    ///@param orders - Array of orders to be evaluated and executed.
    function executeTokenToWethTaxedOrders(OrderBook.Order[] memory orders)
        external
    {
        ///@notice Get all possible execution prices across all of the available DEXs.s
        (
            OrderRouter.TokenToWethExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToWethExecutionPrices(orders);

        ///@notice Batch the orders into optimized quantities to result in the best execution price and gas cost for each order.
        OrderRouter.TokenToWethBatchOrder[]
            memory tokenToWethBatchOrders = _batchTokenToWethOrders(
                orders,
                executionPrices
            );

        ///@notice Execute the batched orders
        _executeTokenToWethBatchTaxedOrders(
            tokenToWethBatchOrders,
            maxBeaconReward,
            orders
        );
    }

    ///@notice Function to execute batch orders from a taxed token to Weth.
    function _executeTokenToWethBatchTaxedOrders(
        OrderRouter.TokenToWethBatchOrder[] memory tokenToWethBatchOrders,
        uint128 maxBeaconReward,
        OrderBook.Order[] memory orders
    ) internal {
        ///@notice Initialize the total reward to be paid to the off-chain executor
        uint128 totalBeaconReward;

        ///@notice For each batch in the tokenToWethBatchOrders array
        for (uint256 i = 0; i < tokenToWethBatchOrders.length; ) {
            OrderRouter.TokenToWethBatchOrder memory batch = tokenToWethBatchOrders[i];
            for (uint256 j = 0; j < batch.batchLength; ) {
                ///@notice Execute each order one by one to avoid double taxing taxed tokens
                OrderBook.Order memory order = IOrderBook(orderBookAddress)
                    .getOrderById(batch.orderIds[j]);
                totalBeaconReward += _executeTokenToWethTaxedOrder(
                    batch,
                    order
                );

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

        ///@notice Unwrap the ETH before sending to the beacon.
        IWETH(WETH).withdraw(totalBeaconReward);

        ///@notice Transfer the reward to the off-chain executor.
        safeTransferETH(msg.sender, totalBeaconReward);
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

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToWethExecutionPrices(
        OrderBook.Order[] memory orders
    ) internal view returns (OrderRouter.TokenToWethExecutionPrice[] memory, uint128) {
        ///@notice Get all prices for the pairing
        (
            OrderRouter.SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

        ///@notice Initialize a new TokenToWethExecutionPrice array to store prices.
        OrderRouter.TokenToWethExecutionPrice[]
            memory executionPrices = new OrderRouter.TokenToWethExecutionPrice[](
                spotReserveAToWeth.length
            );

        ///@notice Scoping to avoid stack too deep.
        {
            ///@notice For each spot reserve, initialize a token to weth execution price.
            for (uint256 i = 0; i < spotReserveAToWeth.length; ++i) {
                executionPrices[i] = OrderRouter.TokenToWethExecutionPrice(
                    spotReserveAToWeth[i].res0,
                    spotReserveAToWeth[i].res1,
                    spotReserveAToWeth[i].spotPrice,
                    lpAddressesAToWeth[i]
                );
            }
        }

        ///@notice Calculate the max beacon reward from the spot reserves.
        uint128 maxBeaconReward = IOrderRouter(ORDER_ROUTER).calculateMaxBeaconReward(
            spotReserveAToWeth,
            orders,
            false
        );

        return (executionPrices, maxBeaconReward);
    }

    ///@notice Helper function to get Uniswap V3 fee from a pool address.
    ///@param lpAddress - Address of the lp.
    ///@return fee The fee on the lp.
    function _getUniV3Fee(address lpAddress) internal returns (uint24 fee) {
        if (!_lpIsNotUniV3(lpAddress)) {
            return IUniswapV3Pool(lpAddress).fee();
        } else {
            return uint24(0);
        }
    }

    ///@notice Function to execute a single TokenToWethTaxedOrder
    function _executeTokenToWethTaxedOrder(
        OrderRouter.TokenToWethBatchOrder memory batch,
        OrderBook.Order memory order
    ) internal returns (uint128 beaconReward) {
        ///@notice Get the UniV3 fee.
        ///@dev This will return 0 if the lp address is a UniV2 address.
        uint24 fee = _getUniV3Fee(batch.lpAddress);

        ///@notice Execute the first swap from tokenIn to Weth
        uint128 amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
                batch.tokenIn,
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
            uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(amountOutWeth, USDC, WETH);

            uint128 conveyorReward;

            ///@notice calculate the reward payable to the off-chain executor
            (conveyorReward, beaconReward) = IOrderRouter(ORDER_ROUTER).calculateReward(
                protocolFee,
                amountOutWeth
            );

            ///@notice Increment the conveyorBalance
            conveyorBalance += conveyorReward;

            ///@notice Subtract the beacon/conveyor reward from the amountOutWeth and transer the funds to the order.owner
            amountOutWeth = amountOutWeth - (conveyorReward + beaconReward);

            ///@notice Transfer the out amount in Weth to the order owner.
            IERC20(WETH).transfer(order.owner, amountOutWeth);
        } else {
            ///@notice If the swap failed revert the tx.
            revert SwapFailed(order.orderId);
        }
    }

    ///@notice Function to execute multiple batch orders from TokenIn to TokenOut for taxed orders.
    ///@param tokenToTokenBatchOrders Array of TokenToToken batches.
    ///@param maxBeaconReward The maximum funds the beacon will recieve after execution.
    function _executeTokenToTokenBatchTaxedOrders(
        OrderRouter.TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders,
        uint128 maxBeaconReward
    ) internal {
        ///@notice For each batch order in the tokenToTokenBatchOrders array.
        for (uint256 i = 0; i < tokenToTokenBatchOrders.length; ) {
            OrderRouter.TokenToTokenBatchOrder memory batch = tokenToTokenBatchOrders[i];

            ///@notice Initialize the total reward to be paid to the off-chain executor
            uint128 totalBeaconReward;

            ///@notice For each order in the batch.
            for (uint256 j = 0; j < batch.batchLength; ) {
                OrderBook.Order memory order = IOrderBook(orderBookAddress)
                    .getOrderById(batch.orderIds[j]);

                ///@notice Execute the order.
                totalBeaconReward += _executeTokenToTokenTaxedOrder(
                    tokenToTokenBatchOrders[i],
                    order
                );

                unchecked {
                    ++j;
                }
            }

            ///@notice If the total compensation awarded to the executor is greater than the max reward, set the reward to the max reward.
            totalBeaconReward = maxBeaconReward > totalBeaconReward
                ? totalBeaconReward
                : maxBeaconReward;

            ///@notice Unwrap the total beacon reward.
            IWETH(WETH).withdraw(totalBeaconReward);

            ///@notice Send the reward to the off-chain executor.
            safeTransferETH(msg.sender, totalBeaconReward);

            unchecked {
                ++i;
            }
        }
    }

    ///@notice Function to execute a swap from token to Weth.
    ///@param batch - The batch containing order details (ex. lp address).
    ///@param order - The order to execute.
    ///@return amountOutWeth - The amount out from the swap in Weth.
    function _executeSwapTokenToWeth(
        OrderRouter.TokenToTokenBatchOrder memory batch,
        OrderBook.Order memory order
    ) internal returns (uint128 amountOutWeth) {
        ///@notice Get the UniV3 fee, this will be 0 if the lp is not UniV3.
        uint24 fee = _getUniV3Fee(batch.lpAddressAToWeth);

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
            batch.lpAddressAToWeth,
            order.quantity,
            order.taxIn,
            order.feeIn,
            order.tokenIn
        );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
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
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(ORDER_ROUTER).calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Function to execute a single token to token taxed order
    ///@param batch - The batch containing order details (ex. lp address).
    ///@param order - The order to execute.
    ///@return beaconReward - The compensation rewarded to the off-chain executor who called the executeOrders function.
    function _executeTokenToTokenTaxedOrder(
        OrderRouter.TokenToTokenBatchOrder memory batch,
        OrderBook.Order memory order
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
            protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(uint128(order.quantity), USDC, WETH);

            ///@notice Take out beacon reward from the order quantity.
            (conveyorReward, beaconReward) = IOrderRouter(ORDER_ROUTER).calculateReward(
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
        uint256 amountOut = IOrderRouter(ORDER_ROUTER).swap(
            WETH,
            order.tokenOut,
            batch.lpAddressWethToB,
            fee,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(this)
        );

        ///@notice If the swap failed revert the tx.
        if (amountOut == 0) {
            ///@notice Cancel the order.
            revert SwapFailed(order.orderId);
        }

        return beaconReward;
    }

    ///@notice Function to execute an array of TokenToTokenTaxed orders.
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenTaxedOrders(OrderBook.Order[] memory orders)
        external
    {
        ///@notice Get all execution prices.
        (
            OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices,
            uint128 maxBeaconReward
        ) = _initializeTokenToTokenExecutionPrices(orders);

        ///@notice Batch the orders into optimized quantities to result in the best execution price and gas cost for each order.
        OrderRouter.TokenToTokenBatchOrder[]
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

    ///@notice Function to execute a swap from TokenToWeth for an order.
    ///@param executionPrice - The best priced TokenToTokenExecutionPrice for the order to be executed on.
    ///@param order - The order to be executed.
    ///@return amountOutWeth - The amountOut in Weth after the swap.
    function _executeSwapTokenToWethOrder(
        OrderRouter.TokenToTokenExecutionPrice memory executionPrice,
        OrderBook.Order memory order
    ) internal returns (uint128 amountOutWeth) {
        ///@notice Cache the liquidity pool address.
        address lpAddressAToWeth = executionPrice.lpAddressAToWeth;

        ///@notice Cache the order Quantity.
        uint256 orderQuantity = order.quantity;

        uint24 feeIn = order.feeIn;
        address tokenIn = order.tokenIn;

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = calculateAmountOutMinAToWeth(
            lpAddressAToWeth,
            orderQuantity,
            order.taxIn,
            feeIn,
            tokenIn
        );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
                tokenIn,
                WETH,
                lpAddressAToWeth,
                feeIn,
                order.quantity,
                batchAmountOutMinAToWeth,
                address(this),
                order.owner
            )
        );

        ///@notice Take out fees from the amountOut.
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(ORDER_ROUTER).calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }
    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToTokenExecutionPrices(
        OrderBook.Order[] memory orders
    ) internal view returns (OrderRouter.TokenToTokenExecutionPrice[] memory, uint128) {
        address tokenIn = orders[0].tokenIn;
        ///@notice Get all prices for the pairing tokenIn to Weth
        (
            OrderRouter.SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(tokenIn, WETH, orders[0].feeIn);

        ///@notice Get all prices for the pairing Weth to tokenOut
        (
            OrderRouter.SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(WETH, orders[0].tokenOut, orders[0].feeOut);

        ///@notice Initialize a new TokenToTokenExecutionPrice array to store prices.
        OrderRouter.TokenToTokenExecutionPrice[]
            memory executionPrices = new OrderRouter.TokenToTokenExecutionPrice[](
                spotReserveAToWeth.length * spotReserveWethToB.length
            );

        ///@notice If TokenIn is Weth
        if (tokenIn == WETH) {
            ///@notice Iterate through each SpotReserve on Weth to TokenB
            for (uint256 i = 0; i < spotReserveWethToB.length; ++i) {
                ///@notice Then set res0, and res1 for tokenInToWeth to 0 and lpAddressAToWeth to the 0 address
                executionPrices[i] = OrderRouter.TokenToTokenExecutionPrice(
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
                    executionPrices[index] = OrderRouter.TokenToTokenExecutionPrice(
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
            ? IOrderRouter(ORDER_ROUTER).calculateMaxBeaconReward(spotReserveAToWeth, orders, false)
            : IOrderRouter(ORDER_ROUTER).calculateMaxBeaconReward(spotReserveWethToB, orders, true);

        return (executionPrices, maxBeaconReward);
    }



    ///@notice Function to batch multiple token to weth orders together.
    ///@param orders - Array of orders to be batched into the most efficient ordering.
    ///@param executionPrices - Array of execution prices available to the batch orders. The batch order will be placed on the best execution price.
    ///@return  tokenToTokenBatchOrders - Returns an array of TokenToWethBatchOrder.
    function _batchTokenToTokenOrders(
        OrderBook.Order[] memory orders,
        OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices
    )
        internal
        returns (OrderRouter.TokenToTokenBatchOrder[] memory tokenToTokenBatchOrders)
    {
        ///@notice Create a new token to weth batch order.
        tokenToTokenBatchOrders = new OrderRouter.TokenToTokenBatchOrder[](orders.length);

        ///@notice Cache the first order in the array.
        OrderBook.Order memory firstOrder = orders[0];

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
        OrderRouter.TokenToTokenBatchOrder
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
                OrderBook.Order memory currentOrder = orders[i];

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
                        bool success = IOrderRouter(ORDER_ROUTER).transferTokensToContract(currentOrder);

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
                        revert OrderHasInsufficientSlippage(
                            currentOrder.orderId
                        );
                    }
                    ///@notice Revert if Order does not meet execution price.
                    revert OrderDoesNotMeetExecutionPrice(currentOrder.orderId);
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

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
    }
}
