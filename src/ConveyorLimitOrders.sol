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


    //----------------------Constants------------------------------------//
    address eth = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;

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

    /// @notice deposit gas credits publicly callable function
    /// @param ethAmount amount of Eth to deposit into user's gas credit balance
    /// @return bool boolean indicator whether deposit was successfully transferred into user's gas credit balance
    function depositCredits(uint256 ethAmount) payable public returns (bool) {
        //Require that deposit amount is strictly == ethAmount
        require(msg.value == ethAmount, "Deposit amount misnatch");
        //Check if sender balance can cover eth deposit
        if(IERC20(eth).balanceOf(msg.sender)<ethAmount){
            return false;
        }

        //Add amount deposited to creditBalance of the user
        creditBalance[msg.sender]+=msg.value;

        //Emit credit deposit event for beacon
        emit GasCreditEvent(true, msg.sender, ethAmount); 

        //return bool success
        return true;
    }
}
