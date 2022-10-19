// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./SwapRouter.sol";
import "./interfaces/ILimitOrderQuoter.sol";
import "./lib/ConveyorFeeMath.sol";
import "./LimitOrderRouter.sol";

contract LimitOrderExecutor is SwapRouter {
    using SafeERC20 for IERC20;
    ///====================================Immutable Storage Variables==============================================//
    address immutable WETH;
    address immutable USDC;
    address immutable LIMIT_ORDER_QUOTER;
    address public immutable LIMIT_ORDER_ROUTER;

    ///@notice The contract owner.
    address owner;

    ///@notice Conveyor funds balance in the contract.
    uint256 conveyorBalance;

    ///@notice Boolean responsible for indicating if a function has been entered when the nonReentrant modifier is used.
    bool reentrancyStatus = false;

    ///@param _weth The wrapped native token on the chain.
    ///@param _usdc Pegged stable token on the chain.
    ///@param _limitOrderQuoterAddress The address of the LimitOrderQuoter contract.
    ///@param _deploymentByteCodes The deployment bytecodes of all dex factory contracts.
    ///@param _dexFactories The Dex factory addresses.
    ///@param _isUniV2 Array of booleans indication whether the Dex is V2 architecture.
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoterAddress,
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _gasOracle
    ) SwapRouter(_deploymentByteCodes, _dexFactories, _isUniV2) {
        USDC = _usdc;
        WETH = _weth;
        LIMIT_ORDER_QUOTER = _limitOrderQuoterAddress;
        owner = msg.sender;

        LIMIT_ORDER_ROUTER = address(
            new LimitOrderRouter(_gasOracle, _weth, address(this))
        );
    }

    ///@notice Function to execute a batch of Token to Weth Orders.
    function executeTokenToWethOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256)
    {
        ///@notice Get all of the execution prices on TokenIn to Weth for each dex.
        ///@notice Get all prices for the pairing
        (
            SpotReserve[] memory spotReserveAToWeth,
            address[] memory lpAddressesAToWeth
        ) = _getAllPrices(orders[0].tokenIn, WETH, orders[0].feeIn);

        ///@notice Initialize all execution prices for the token pair.
        TokenToWethExecutionPrice[] memory executionPrices = ILimitOrderQuoter(
            LIMIT_ORDER_QUOTER
        )._initializeTokenToWethExecutionPrices(
                spotReserveAToWeth,
                lpAddressesAToWeth
            );

        ///@notice Calculate the max beacon reward from the spot reserves.
        uint128 maxBeaconReward = calculateMaxBeaconReward(
            spotReserveAToWeth,
            orders,
            false
        );

        ///@notice Set totalBeaconReward to 0
        uint256 totalBeaconReward = 0;

        ///@notice Set totalConveyorReward to 0
        uint256 totalConveyorReward = 0;

        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Create a variable to track the best execution price in the array of execution prices.
            uint256 bestPriceIndex = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._findBestTokenToWethExecutionPrice(
                    executionPrices,
                    orders[i].buy
                );

            {
                ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
                (
                    uint256 beaconReward,
                    uint256 conveyorReward
                ) = _executeTokenToWethOrder(
                        orders[i],
                        maxBeaconReward,
                        executionPrices[bestPriceIndex]
                    );
                ///@notice Increment the total beacon and conveyor reward.
                totalBeaconReward += beaconReward;
                totalConveyorReward += conveyorReward;
            }

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = ILimitOrderQuoter(
                LIMIT_ORDER_QUOTER
            ).simulateTokenToWethPriceChange(
                    uint128(orders[i].quantity),
                    executionPrices[bestPriceIndex]
                );

            unchecked {
                ++i;
            }
        }
        ///@notice Transfer the totalBeaconReward to the off chain executor.
        transferBeaconReward(totalBeaconReward, tx.origin, WETH);

        ///@notice Increment the conveyor balance.
        conveyorBalance += totalConveyorReward;

        return (totalBeaconReward, totalConveyorReward);
    }

    ///@notice Function to execute a single Token To Weth order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToWethExecutionPrice to execute the order on.
    function _executeTokenToWethOrder(
        OrderBook.Order memory order,
        uint128 maxBeaconReward,
        SwapRouter.TokenToWethExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Swap the batch amountIn on the batch lp address and send the weth back to the contract.
        (
            uint128 amountOutWeth,
            uint128 conveyorReward,
            uint128 beaconReward
        ) = _executeSwapTokenToWethOrder(
                executionPrice.lpAddressAToWeth,
                order
            );

        beaconReward = maxBeaconReward > beaconReward
            ? beaconReward
            : maxBeaconReward;

        ///@notice Transfer the tokenOut amount to the order owner.
        transferTokensOutToOwner(
            order.owner,
            amountOutWeth,
            WETH
        );

        return (uint256(conveyorReward), uint256(beaconReward));
    }

    ///@notice Function to execute a swap from TokenToWeth for an order.
    ///@param lpAddressAToWeth - The best priced TokenToTokenExecutionPrice for the order to be executed on.
    ///@param order - The order to be executed.
    ///@return amountOutWeth - The amountOut in Weth after the swap.
    function _executeSwapTokenToWethOrder(
        address lpAddressAToWeth,
        OrderBook.Order memory order
    )
        internal
        returns (
            uint128 amountOutWeth,
            uint128 conveyorReward,
            uint128 beaconReward
        )
    {
        ///@notice Cache the order Quantity.
        uint256 orderQuantity = order.quantity;

        uint24 feeIn = order.feeIn;
        address tokenIn = order.tokenIn;

        ///@notice Calculate the amountOutMin for the tokenA to Weth swap.
        uint256 batchAmountOutMinAToWeth = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
            .calculateAmountOutMinAToWeth(
                lpAddressAToWeth,
                orderQuantity,
                order.taxIn,
                feeIn,
                tokenIn
            );

        ///@notice Swap from tokenA to Weth.
        amountOutWeth = uint128(
            swap(
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
        uint128 protocolFee = _calculateFee(amountOutWeth, USDC, WETH);

        ///@notice Calculate the conveyorReward and executor reward.
        (conveyorReward, beaconReward) = ConveyorFeeMath.calculateReward(
            protocolFee,
            amountOutWeth
        );

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
    }

    ///@notice Function to execute an array of TokenToToken orders
    ///@param orders - Array of orders to be executed.
    function executeTokenToTokenOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256)
    {
        TokenToTokenExecutionPrice[] memory executionPrices;
        address tokenIn = orders[0].tokenIn;
        uint128 maxBeaconReward;
        uint24 feeIn = orders[0].feeIn;
        uint24 feeOut = orders[0].feeOut;

        {
            ///@notice Get all execution prices.
            ///@notice Get all prices for the pairing tokenIn to Weth
            (
                SpotReserve[] memory spotReserveAToWeth,
                address[] memory lpAddressesAToWeth
            ) = _getAllPrices(tokenIn, WETH, feeIn);

            ///@notice Get all prices for the pairing Weth to tokenOut
            (
                SpotReserve[] memory spotReserveWethToB,
                address[] memory lpAddressWethToB
            ) = _getAllPrices(WETH, orders[0].tokenOut, feeOut);

            executionPrices = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._initializeTokenToTokenExecutionPrices(
                    tokenIn,
                    spotReserveAToWeth,
                    lpAddressesAToWeth,
                    spotReserveWethToB,
                    lpAddressWethToB
                );
            ///@notice Get the Max beacon reward on the SpotReserves
            maxBeaconReward = WETH != tokenIn
                ? calculateMaxBeaconReward(spotReserveAToWeth, orders, false)
                : calculateMaxBeaconReward(spotReserveWethToB, orders, true);
        }
        ///@notice Set totalBeaconReward to 0
        uint256 totalBeaconReward = 0;
        ///@notice Set totalConveyorReward to 0
        uint256 totalConveyorReward = 0;

        ///@notice Loop through each Order.
        for (uint256 i = 0; i < orders.length; ) {
            ///@notice Create a variable to track the best execution price in the array of execution prices.
            uint256 bestPriceIndex = ILimitOrderQuoter(LIMIT_ORDER_QUOTER)
                ._findBestTokenToTokenExecutionPrice(
                    executionPrices,
                    orders[i].buy
                );

            {
                ///@notice Pass the order, maxBeaconReward, and TokenToWethExecutionPrice into _executeTokenToWethSingle for execution.
                (
                    uint256 beaconReward,
                    uint256 conveyorReward
                ) = _executeTokenToTokenOrder(
                        orders[i],
                        maxBeaconReward,
                        executionPrices[bestPriceIndex]
                    );
                totalBeaconReward += beaconReward;
                totalConveyorReward += conveyorReward;
            }

            ///@notice Update the best execution price.
            executionPrices[bestPriceIndex] = ILimitOrderQuoter(
                LIMIT_ORDER_QUOTER
            ).simulateTokenToTokenPriceChange(
                    uint128(orders[i].quantity),
                    executionPrices[bestPriceIndex]
                );

            unchecked {
                ++i;
            }
        }
        ///@notice Transfer the totalBeaconReward to the off chain executor.
        transferBeaconReward(totalBeaconReward, tx.origin, WETH);

        conveyorBalance += totalConveyorReward;

        return (totalBeaconReward, totalConveyorReward);
    }

    ///@notice Function to execute a single Token To Token order.
    ///@param order - The order to be executed.
    ///@param executionPrice - The best priced TokenToTokenExecution price to execute the order on.
    function _executeTokenToTokenOrder(
        OrderBook.Order memory order,
        uint128 maxBeaconReward,
        TokenToTokenExecutionPrice memory executionPrice
    ) internal returns (uint256, uint256) {
        ///@notice Initialize variables to prevent stack too deep.
        uint256 amountInWethToB;
        uint128 conveyorReward;
        uint128 beaconReward;

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice If the tokenIn is not weth.
            if (order.tokenIn != WETH) {
                ///@notice Execute the first swap from tokenIn to weth.
                (
                    amountInWethToB,
                    conveyorReward,
                    beaconReward
                ) = _executeSwapTokenToWethOrder(
                    executionPrice.lpAddressAToWeth,
                    order
                );

                if (amountInWethToB == 0) {
                    revert InsufficientOutputAmount();
                }
            } else {
                ///@notice Transfer the TokenIn to the contract.
                transferTokensToContract(order);

                ///@notice Cache the order quantity.
                uint256 amountIn = order.quantity;

                ///@notice Take out fees from the batch amountIn since token0 is weth.
                uint128 protocolFee = _calculateFee(
                    uint128(amountIn),
                    USDC,
                    WETH
                );

                ///@notice Calculate the conveyorReward and the off-chain logic executor reward.
                (conveyorReward, beaconReward) = ConveyorFeeMath
                    .calculateReward(protocolFee, uint128(amountIn));

                ///@notice Get the amountIn for the Weth to tokenB swap.
                amountInWethToB = amountIn - (beaconReward + conveyorReward);
            }
        }

        ///@notice Swap Weth for tokenB.
        uint256 amountOutInB = swap(
            WETH,
            order.tokenOut,
            executionPrice.lpAddressWethToB,
            order.feeOut,
            amountInWethToB,
            order.amountOutMin,
            order.owner,
            address(this)
        );

        if (amountOutInB == 0) {
            revert InsufficientOutputAmount();
        }

        ///@notice Adjust the beaconReward according to the maxBeaconReward.
        beaconReward = beaconReward < maxBeaconReward
            ? beaconReward
            : maxBeaconReward;

        return (uint256(conveyorReward), uint256(beaconReward));
    }

    ///@notice Transfer the order quantity to the contract.
    ///@param order - The orders tokens to be transferred.
    function transferTokensToContract(OrderBook.Order memory order) internal {
        IERC20(order.tokenIn).safeTransferFrom(
            order.owner,
            address(this),
            order.quantity
        );
    }

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external {
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;

        ///@notice Revert if caller is not the owner.
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        ///@notice Unwrap the the conveyorBalance.
        IWETH(WETH).withdraw(conveyorBalance);

        safeTransferETH(owner, conveyorBalance);
        ///@notice Set the conveyorBalance to 0 prior to transferring the ETH.
        conveyorBalance = 0;

        ///@notice Set the reentrancy status to false after the conveyorBalance has been decremented to prevent reentrancy. 
        reentrancyStatus = false;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }
        owner = newOwner;
    }
}
