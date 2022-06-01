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
    //     STOP, +
    //     TAKE_PROFIT +
    // }
    //
    //


    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] calldata orders) external onlyEOA {
        
        /// @dev Require all orders in the calldata are organized in order of quantity
        /// This will simplify computational complexity on chain 
        //(uint256 realTimeSpotPrice, address uniV2PairAddress) = calculateMeanSpotPrice(order.tokenIn, order.tokenOut, 1,300);  


        //iterate through orders and try to fill order
        for (uint256 i = 0; i < orders.length; ++i) {
            //Pass in single order
            Order memory order = orders[i];
            // @todo get lp spot price for uniswap v3
            // Store realtime lp spot price for token pair in 
            
            // @note to self MSG.SENDER beacon
            // bool canExeute = orderCanExecute(order,realTimeSpotPrice);
            // Grab order ExecutionPrice

            uint256 orderExecutionPrice = order.price;

            //get the lp execution price lpExecutionPrice = calculateMeanSpotPrice(address order.tokenIn, address tokenOut,uint32 1,uint24 300);
           
            //check if order executionPrice of the lp 
            //if it is execute the order i.e swap the tokenIn to the tokenOut token through the respective lp router
            
            // if(order.price <
            //check the execution price of the order

            //check the price of the lp

            //note: can either loop through and execute or aggregate and execute

            //loop through orders and see which ones hit the execution price

            //if execution price hit
            //add the order to executableOrders, update total

            //aggregate the value of all of the orders

            //_executeOrder();
        }

        //at the end reward beacon and reward conveyor 
        // call maxBeaconReward() check if maxBeaconReward >= beacon reward

    }


 
    /// @notice helper function to determine the most spot price advantagous trade route for lp ordering of the batch
    /// @notice Should be called prior to batch execution time to generate the final lp ordering on execution
    /// @param orders all of the verifiably executable orders in the batch filtered prior to passing as parameter
    /// @param reserveSizes nested array of uint256 reserve0,reserv1 for each lp 
    /// @param pairAddress address[] ordered by [uniswapV2, Sushiswap, UniswapV3]
    // /// @return optimalOrder array of pair addresses of size orders.length corresponding to the indexed pair address to use for each order
    function optimizeBatchLPOrder(Order[] memory orders, uint128[][] calldata reserveSizes, address[] memory pairAddress, bool high) external pure returns (address[] memory) {
        //continually mock the execution of each order and find the most advantagios spot price after each simulated execution
        // aggregate address[] optimallyOrderedPair to be an order's array of the optimal pair address to perform execution on for the respective indexed order in orders
        // Note order.length == optimallyOrderedPair.length
      
        uint256[] memory tempSpots = new uint256[](reserveSizes.length); 
        address[] memory orderedPairs = new address[](orders.length);
        uint128[][] memory tempReserves= new uint128[][](reserveSizes.length);
        uint256 targetSpot = (!high) ? 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff : 0;
        for(uint256 i = 0; i< orders.length; i++){
            uint256 index;
            
            if(i==0){
                for(uint256 j =0; j< tempSpots.length;j++){
                    
                    tempSpots[j]=uint256(ConveyorMath.divUI(reserveSizes[j][0], reserveSizes[j][1]));
                    tempReserves[j]= reserveSizes[j];
                }
            }
            
            for(uint256 k = 0; k< tempSpots.length;k++){
                if(!high){
                    if(tempSpots[k]<targetSpot){
                        index = k;
                        targetSpot = tempSpots[k];
                    }

                }else {
                    if(tempSpots[k]>targetSpot){
                        index = k;
                        targetSpot = tempSpots[k];
                    }
                }
                  
            }
            
            Order memory order = orders[i];
            //console.logAddress(orderedPairs[i]);
            if(i != orders.length-1){
                (tempSpots[index], tempReserves[index]) = simulatePriceChange(uint128(order.quantity), tempReserves[index]);
            }
        
            orderedPairs[i]=pairAddress[index];
            
        }


        return orderedPairs;

    }

    /// @notice Helper function to determine the spot price change to the lp after introduction alphaX amount into the reserve pool
    /// @param alphaX uint256 amount to be added to reserve_x to get out token_y
    /// @param reserves current lp reserves for tokenIn and tokenOut
    /// @return unsigned The amount of proportional spot price change in the pool after adding alphaX to the tokenIn reserves
     function simulatePriceChange(uint128 alphaX, uint128[] memory reserves) internal pure returns (uint256, uint128[] memory) {
        uint128[] memory newReserves = new uint128[](2);

        unchecked {
            uint128 numerator = reserves[0]+alphaX;
            uint256 k = uint256(reserves[0]*reserves[1]);
            
            uint128 denominator = ConveyorMath.divUI(k, uint256(reserves[0]+alphaX)); 
        
            uint256 spotPrice = uint256(ConveyorMath.div128x128(uint256(numerator)<<128,uint256(denominator)<<64));
            
            require(spotPrice<=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, "overflow");
            newReserves[0]= numerator;
            newReserves[1] = denominator;
            return (uint256(spotPrice), newReserves);
        }
     }


    // /// @notice Helper function to determine if order can execute based on the spot price of the lp, the determinig factor is the order.orderType
    // /// @param order Order order.price to be checked against realtime lp spot price for execution
    // /// @param lpSpotPrice realtime best lpSpotPrice found for the order
    // /// @return bool indicator whether order can be executed or not
    // function orderCanExecute(Order calldata order, uint256 lpSpotPrice) internal returns (bool) {
    //         /// Should be a very quick boolean check against the two values

    // }

    // / @notice private order execution function, assumes all orders passed to it will execute
    // / @param orders orders to be executed through swap
    // / @param optimallyOrderedPair optimally ordered execution route for all orders in orders
    // / Note orders.length :== optimallyOrderedPair.length
    // / @return bool indicating whether all orders were successfully executed in the batch
    // function _executeOrder(Order calldata orders, address[] memory optimallyOrderedPair) private returns (bool) {

    // }

    // /// @notice Helper to check if user has minGasCredits for order execution
    // /// @param order order to be checked for minimum gas credits
    // /// @return bool indicating whether the user has the min gas credits for order
    // function hasMinCreditsForOrder(Order calldata order) internal pure returns (bool) {

    // }


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
