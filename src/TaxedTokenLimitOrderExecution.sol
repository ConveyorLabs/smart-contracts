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
import "./interfaces/IOrderBook.sol";
import "./interfaces/IOrderRouter.sol";
import "./LimitOrderBatcher.sol";

//TODO: remove console from all contracts
import "./test/utils/Console.sol";

/// @title OrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract TaxedTokenLimitOrderExecution is LimitOrderBatcher {
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
        address _orderRouter
    ) LimitOrderBatcher(_weth, _quoterAddress, _orderRouter) {
        iQuoter = IQuoter(_quoterAddress);
        USDC = _usdc;
        ORDER_ROUTER = _orderRouter;
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

        uint256 totalBeaconReward = 0;

        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Create a variable to track the best execution price in the array of execution prices.
            uint256 bestPriceIndex = _findBestTokenToWethExecutionPrice(
                executionPrices,
                orders[i].buy
            );

            ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
            totalBeaconReward += _executeTokenToWethTaxedSingle(
                orders[i],
                maxBeaconReward,
                executionPrices[bestPriceIndex]
            );

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = simulateTokenToWethPriceChange(
                uint128(orders[i].quantity),
                executionPrices[bestPriceIndex]
            );

            unchecked {
                ++i;
            }
        }

        IOrderRouter(ORDER_ROUTER).transferBeaconReward(
            totalBeaconReward,
            tx.origin,
            WETH
        );
    }

    ///@notice Function to execute a single TokenToWeth order.
    ///@param order - The order to be executed.
    ///@param maxBeaconReward - The maximum beacon reward.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order.
    function _executeTokenToWethTaxedSingle(
        OrderBook.Order memory order,
        uint128 maxBeaconReward,
        OrderRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256) {
        ///@notice Execute the TokenIn to Weth order.
        (uint256 amountOut, uint256 beaconReward) = _executeTokenToWethOrder(
            order,
            executionPrice
        );

        IOrderRouter(ORDER_ROUTER).transferTokensOutToOwner(
            order.owner,
            amountOut,
            WETH
        );

        /**@notice If the maxBeaconReward is greater than the beaconReward then keep the beaconReward else set beaconReward
        to the maxBeaconReward
        */
        beaconReward = maxBeaconReward > beaconReward
            ? beaconReward
            : maxBeaconReward;

        return beaconReward;
    }

    ///@notice Function to execute a single Token To Weth order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order on.
    function _executeTokenToWethOrder(
        OrderBook.Order memory order,
        OrderRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        uint128 amountOutWeth = uint128(
            IOrderRouter(ORDER_ROUTER).swap(
                order.tokenIn,
                WETH,
                executionPrice.lpAddressAToWeth,
                order.feeIn,
                order.quantity,
                order.amountOutMin,
                ORDER_ROUTER,
                order.owner
            )
        );

        ///@notice Retrieve the protocol fee for the total amount out.
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
            amountOutWeth,
            USDC,
            WETH
        );

        ///@notice Get the conveyor and beacon reward from the total amount out.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(
            ORDER_ROUTER
        ).calculateReward(protocolFee, amountOutWeth);

        ///@notice Increment the conveyor balance by the conveyor reward
        conveyorBalance += conveyorReward;

        return (
            uint256(amountOutWeth - (beaconReward + conveyorReward)),
            uint256(beaconReward)
        );
    }

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToWethExecutionPrices(
        OrderBook.Order[] memory orders
    )
        internal
        view
        returns (OrderRouter.TokenToWethExecutionPrice[] memory, uint128)
    {
        ///@notice Get all prices for the pairing
        (
            OrderRouter.SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(
                orders[0].tokenIn,
                WETH,
                orders[0].feeIn
            );

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
        uint128 maxBeaconReward = IOrderRouter(ORDER_ROUTER)
            .calculateMaxBeaconReward(spotReserveAToWeth, orders, false);

        return (executionPrices, maxBeaconReward);
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

        uint256 totalBeaconReward = 0;

        for (uint256 i = 0; i < orders.length; ) {
            uint256 bestPriceIndex = _findBestTokenToTokenExecutionPrice(
                executionPrices,
                orders[i].buy
            );

            ///@notice Execute the batches of orders.
            totalBeaconReward += _executeTokenToTokenTaxedSingle(
                orders[i],
                maxBeaconReward,
                executionPrices[bestPriceIndex]
            );

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = simulateTokenToTokenPriceChange(
                uint128(orders[i].quantity),
                executionPrices[bestPriceIndex]
            );

            unchecked {
                ++i;
            }
        }

        IOrderRouter(ORDER_ROUTER).transferBeaconReward(
            totalBeaconReward,
            tx.origin,
            WETH
        );
    }

    ///@notice Function to execute a single Token To Token order.
    ///@param order - The order to be executed.
    ///@param maxBeaconReward - The maximum beacon reward.
    ///@param executionPrice - The best priced TokenToTokenExecutionPrice to execute the order on.
    function _executeTokenToTokenTaxedSingle(
        OrderBook.Order memory order,
        uint128 maxBeaconReward,
        OrderRouter.TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (uint256 beaconReward) {
        ///@notice Execute the order.
        (, beaconReward) = _executeTokenToTokenOrder(order, executionPrice);

        ///@notice Adjust the beaconReward according to the maxBeaconReward.
        beaconReward = beaconReward < maxBeaconReward
            ? beaconReward
            : maxBeaconReward;
    }

    ///@notice Function to execute a single Token To Token order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToTokenExecution price to execute the order on.
    function _executeTokenToTokenOrder(
        OrderBook.Order memory order,
        OrderRouter.TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Initialize variables to prevent stack too deep.
        uint256 amountInWethToB;
        uint128 conveyorReward;
        uint128 beaconReward;

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice If the tokenIn is not weth.
            if (order.tokenIn != WETH) {
                if (!order.taxed) {
                    ///@notice Transfer the TokenIn to the contract.
                    IOrderRouter(ORDER_ROUTER).transferTokensToContract(order);
                }

                amountInWethToB = _executeSwapTokenToWethOrder(
                    executionPrice,
                    order
                );
                if (amountInWethToB == 0) {
                    revert InsufficientOutputAmount();
                }
            } else {
                ///@notice Transfer the TokenIn to the contract.
                IOrderRouter(ORDER_ROUTER).transferTokensToContract(order);

                uint256 amountIn = order.quantity;
                ///@notice Take out fees from the batch amountIn since token0 is weth.
                uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
                    uint128(amountIn),
                    USDC,
                    WETH
                );

                ///@notice Calculate the conveyorReward and the off-chain logic executor reward.
                (conveyorReward, beaconReward) = IOrderRouter(ORDER_ROUTER)
                    .calculateReward(protocolFee, uint128(amountIn));

                ///@notice Increment the conveyor balance by the conveyor reward.
                conveyorBalance += conveyorReward;

                ///@notice Get the amountIn for the Weth to tokenB swap.
                amountInWethToB = amountIn - (beaconReward + conveyorReward);
            }
        }

        ///@notice Swap Weth for tokenB.
        uint256 amountOutInB = IOrderRouter(ORDER_ROUTER).swap(
            WETH,
            order.tokenOut,
            executionPrice.lpAddressWethToB,
            order.feeOut,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(ORDER_ROUTER)
        );

        if (amountOutInB == 0) {
            revert InsufficientOutputAmount();
        }

        return (amountOutInB, uint256(beaconReward));
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
                ORDER_ROUTER,
                order.owner
            )
        );

        ///@notice Take out fees from the amountOut.
        uint128 protocolFee = IOrderRouter(ORDER_ROUTER).calculateFee(
            amountOutWeth,
            USDC,
            WETH
        );

        ///@notice Calculate the conveyorReward and executor reward.
        (uint128 conveyorReward, uint128 beaconReward) = IOrderRouter(
            ORDER_ROUTER
        ).calculateReward(protocolFee, amountOutWeth);

        ///@notice Increment the conveyor protocol's balance of ether in the contract by the conveyorReward.
        conveyorBalance += conveyorReward;

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Initializes all routes from tokenA to Weth -> Weth to tokenB and returns an array of all combinations as ExectionPrice[]
    ///@param orders - Array of orders that are being evaluated for execution.
    function _initializeTokenToTokenExecutionPrices(
        OrderBook.Order[] memory orders
    )
        internal
        view
        returns (OrderRouter.TokenToTokenExecutionPrice[] memory, uint128)
    {
        address tokenIn = orders[0].tokenIn;
        ///@notice Get all prices for the pairing tokenIn to Weth
        (
            OrderRouter.SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(
                tokenIn,
                WETH,
                orders[0].feeIn
            );

        ///@notice Get all prices for the pairing Weth to tokenOut
        (
            OrderRouter.SpotReserve[] memory spotReserveWethToB,
            address[] memory lpAddressWethToB
        ) = IOrderRouter(ORDER_ROUTER).getAllPrices(
                WETH,
                orders[0].tokenOut,
                orders[0].feeOut
            );

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
                    executionPrices[index] = OrderRouter
                        .TokenToTokenExecutionPrice(
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
            ? IOrderRouter(ORDER_ROUTER).calculateMaxBeaconReward(
                spotReserveAToWeth,
                orders,
                false
            )
            : IOrderRouter(ORDER_ROUTER).calculateMaxBeaconReward(
                spotReserveWethToB,
                orders,
                true
            );

        return (executionPrices, maxBeaconReward);
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

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external onlyOwner {
        safeTransferETH(owner, conveyorBalance);
        conveyorBalance = 0;
    }
}
