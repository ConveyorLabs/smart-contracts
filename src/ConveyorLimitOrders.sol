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

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] memory orders) external onlyEOA {
        //iterate through orders and try to fill order
        for (uint256 i = 0; i < orders.length; ++i) {
            Order memory order = orders[i];
            //check the execution price of the order

            //check the price of the lp

            //note: can either loop through and execute or aggregate and execute

            //loop through orders and see which ones hit the execution price

            //if execution price hit
            //add the order to executableOrders, update total

            //aggregate the value of all of the orders
        }
    }

   

    // /// @notice helper function to determine the most spot price advantagous trade route for lp ordering of the batch
    // /// @notice Should be called prior to batch execution time to generate the final lp ordering on execution
    // /// @param orders all of the verifiably executable orders in the batch filtered prior to passing as parameter
    // /// @param reserveSizes nested array of uint256 reserve0,reserv1 for each lp 
    // /// @param pairAddress address[] ordered by [uniswapV2, Sushiswap, UniswapV3]
    // /// @return optimalOrder array of pair addresses of size orders.length corresponding to the indexed pair address to use for each order
    // function optimizeBatchLPOrder(Order[] memory orders, uint256[][] calldata reserveSizes, address[] memory pairAddress) internal view returns (address[] memory optimallyOrderedPair) {
    //     //continually mock the execution of each order and find the most advantagios spot price after each simulated execution
    //     // aggregate address[] optimallyOrderedPair to be an order's array of the optimal pair address to perform execution on for the respective indexed order in orders
    //     // Note order.length == optimallyOrderedPair.length


    // }

    /// @notice Helper function to determine the spot price change to the lp after introduction alphaX amount into the reserve pool
    /// @param alphaX uint256 amount to be added to reserve_x to get out token_y
    /// @param reserves current lp reserves for tokenIn and tokenOut
    /// @return spotPrice the amount of proportional spot price change in the pool after adding alphaX to the tokenIn reserves
    function simulatePriceChange(uint256 alphaX, uint256[] memory reserves) external pure returns (uint256) {
        
       
            // uint256 numerator = 1;
            // require(false, "Lfjappfa");

            // assembly {
            //     mstore(0x00, numerator)
            //     revert(0x00, 0x20)
            // }

            // uint256 k = uint256(ConveyorMath.mul64x64(uint128(reserves[0])<<64, uint128(reserves[1])<<64))<<64;
            // console.logString("k");
            // // assembly {
            // //     mstore(0x00, k)
            // //     revert(0x00, 0x20)
            // // }
            // uint256 denPartial = ConveyorMath.div128x128(k, uint128(reserves[0]+alphaX)<<64); 
            // uint256 denominator = uint256(ConveyorMath.mul64x64(uint128(denPartial>>64), uint128(reserves[0])<<64))<<64;
            // uint256 spotPrice = uint256(ConveyorMath.div128x128(numerator,denominator))<<64;
            // require(spotPrice<=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            return uint256(1);
        
            

            
        
        
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
