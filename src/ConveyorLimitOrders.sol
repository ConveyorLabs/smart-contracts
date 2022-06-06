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

    //----------------------State Variables------------------------------------//

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
    //     STOP, -
    //     TAKE_PROFIT +
    // }
    //
    //

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] calldata orders) external onlyEOA {
        /// @dev The lpAddress's passed in from the helpers have strict ordering solely dependent on "dexes" structure
        /// Even if the dex does not provide a pairing for the token pair in the batch it will still be a part of the structure
        /// With [0,0] reserve sizes and pool address := address(0)
        /// @dev Require all orders in the calldata are organized in order of quantity
        /// This will simplify computational complexity on chain
        {
            for(uint256 j=0; j<orders.length-1;j++){
                require(orders[j].quantity <= orders[j+1].quantity, "Invalid Batch Ordering");
            }
        }

        //Initialize boolean variable dependent on OrderType of batch 
        bool high;

        //Scope logic to make stack leaner
        {
            //Determine high bool from batched OrderType
            if(orders[0].orderType == OrderType.BUY || orders[0].orderType == OrderType.TAKE_PROFIT){
                high = true;
            }else {
                high = false;
            }
        }

        //Retrive Array of SpotReserve structs as well as lpPairAddress's, strict indexing is assumed between both structures
        //SpotReserve[] indicates the spot price and reserves across the first pairing in the two hop router
        (SpotReserve[] memory spotReserveFirst, address[] memory lpPairAddressFirst) = _getAllPrices(orders[0].tokenIn, WETH, 300, 1);

        //Retrive Array of SpotReserve structs as well as lpPairAddress's, strict indexing is assumed between both structures
        //SpotReserve[] indicates the spot price and reserves across the second pairing in the two hop router
        (SpotReserve[] memory spotReserveSecond, address[] memory lpPairAddressSecond) = _getAllPrices(WETH, orders[0].tokenOut, 300, 1);
        
        //Initialize lpReserves and populate with spotReserve indexed reserve values to pass into optimizeBatchLPOrder
        uint128[][] memory lpReservesFirst = new uint128[][](spotReserveFirst.length);

        //Initialize batchSize array to index orderBatches[n]
        uint256[] memory batchSizeFirst = new uint256[](spotReserveFirst.length);

        //Initialize lpReserves and populate with spotReserve indexed reserve values to pass into optimizeBatchLPOrder
        uint128[][] memory lpReservesSecond = new uint128[][](spotReserveSecond.length);

        //Initialize batchSize array to index orderBatches[n]
        uint256[] memory batchSizeSecond = new uint256[](spotReserveSecond.length);

        {
            for(uint256 k =0; k<spotReserveFirst.length; ++k){
                batchSizeFirst[k]=0;
                (lpReservesFirst[k][0], lpReservesFirst[k][1])=(uint128(spotReserveFirst[k].res0),uint128(spotReserveFirst[k].res1));
            }

            for(uint256 k =0; k<spotReserveSecond.length; ++k){
                batchSizeSecond[k]=0;
                (lpReservesSecond[k][0], lpReservesSecond[k][1])=(uint128(spotReserveSecond[k].res0),uint128(spotReserveSecond[k].res1));
            }
        }

        //Simulated pairAddress and spotPrice Order of entire order batch
        (address[][] memory pairAddressOrder, uint256[][] memory simulatedSpotPrices) = _optimizeBatchLPOrder(orders, lpReservesFirst, lpReservesSecond, lpPairAddressFirst, lpPairAddressSecond, high);
        
    
        //Initialize structure to hold order batches per lp
        Order[][] memory orderBatches = new Order[][](pairAddressOrder.length);
        

        {
            //iterate through orders and try to fill order
            for (uint256 i = 0; i < orders.length; ++i) {

                //Pass in single order
                Order memory order = orders[i];

                //Check if order can execute at simulated price and add to orderBatches on the respective lp
                if(orderCanExecute(order, simulatedSpotPrices)){
                    for(uint256 j=0; j<lpPairAddressFirst.length; ++j){
                        if(pairAddressOrder[i][0]==lpPairAddressFirst[j]){
                            //Batch size is used here to be accumulating index of 2nd order orderBatches array
                            //To know how many orders there are per batch
                            orderBatchesFirst[j][batchSize[j]]= order;
                            ++batchSize[j];
                        }
                    }

                    for(uint256 j=0; j<lpPairAddressSecond.length; ++j){
                        if(pairAddressOrderSecond[i]==lpPairAddressSecond[j]){
                            //Batch size is used here to be accumulating index of 2nd order orderBatches array
                            //To know how many orders there are per batch
                            orderBatchesSecond[j][batchSizeSecond[j]]= order;
                            ++batchSizeSecond[j];
                        }
                    }
                }
    
            }
        }

        //Pass each batch into private execution function
        for(uint256 index = 0; index<orderBatches.length;++index){
            if(batchSizeFirst[index]>0){
                _executeOrder(orderBatches[index], index, lpPairAddress[index], 300);
            }
        }
    }

    /// @notice private order execution function, assumes all orders passed to it will execute
    /// @param orders orders to be executed through swap
    /// @param dexIndex index of dex in dexes arr
    /// @param pairAddress lp pair address to execute the order batch on
    /// @param FEE lp spot trading fee
    /// @return bool indicating whether all orders were successfully executed in the batch
    function _executeOrder(Order[] memory orders, uint256 dexIndex, address pairAddress, uint24 FEE) private returns (bool) {
        if(dexes[dexIndex].isUniV2){
            for(uint256 i=0;i<orders.length;++i){

                uint128 amountOutWeth=uint128(_swapV2(orders[i].tokenIn, WETH, pairAddress, orders[i].quantity, orders[i].amountOutMin));
                uint128 _userFee = _calculateFee(amountOutWeth);

                (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(_userFee, amountOutWeth);
                

            }
        }else{
            for(uint256 i=0; i< orders.length;++i){

                uint128 amountOutWeth=uint128(_swapV3(orders[i].tokenIn, WETH, FEE, pairAddress, orders[i].amountOutMin, orders[i].quantity));
                uint128 _userFee = _calculateFee(amountOutWeth);

                (uint128 conveyorReward, uint128 beaconReward) = _calculateReward(_userFee, amountOutWeth);


            }
        }
    }

    /// @notice helper function to determine the most spot price advantagous trade route for lp ordering of the batch
    /// @notice Should be called prior to batch execution time to generate the final lp ordering on execution
    /// @param orders all of the verifiably executable orders in the batch filtered prior to passing as parameter
    /// @param reserveSizesFirst nested array of uint256 reserve0,reserv1 for each lp on first hop
    /// @param reserveSizesSecond nested array of uint256 reserve0, reserve1 for each lp on second hop
    /// @param pairAddressFirst address[] ordered by [uniswapV2, Sushiswap, UniswapV3] for first hop
    /// @param pairAddressSecond address[] ordered by [uniswapV2, Sushiswap, UniswapV3] for second hop
    // /// @return optimalOrder array of pair addresses of size orders.length corresponding to the indexed pair address to use for each order
    function _optimizeBatchLPOrder(
        Order[] memory orders,
        uint128[][] memory reserveSizesFirst,
        uint128[][] memory reserveSizesSecond,
        address[] memory pairAddressFirst,
        address[] memory pairAddressSecond,
        bool high
    ) public pure returns (address[][] memory, uint256[][] memory) {
        //continually mock the execution of each order and find the most advantagios spot price after each simulated execution
        // aggregate address[] optimallyOrderedPair to be an order's array of the optimal pair address to perform execution on for the respective indexed order in orders
        // Note order.length == optimallyOrderedPair.length
        uint256[] memory tempSpotsFirst = new uint256[](reserveSizesFirst.length);
        uint256[] memory tempSpotsSecond = new uint256[](reserveSizesSecond.length);
        address[][] memory orderedPairs = new address[](orders.length);

        uint128[][] memory tempReservesFirst = new uint128[][](reserveSizesFirst.length);
        uint128[][] memory tempReservesSecond = new uint128[][](reserveSizesSecond.length);

        uint256[][] memory simulatedSpotPrices = new uint256[](orders.length);

        uint256 targetSpotFirst = (!high)
            ? 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            : 0;
        
        uint256 targetSpotSecond = (!high)
            ? 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            : 0;

        //Scope everything where possible 
        {
            // Fill tempSpots array
            for (uint256 j = 0; j < tempSpotsFirst.length; j++) {
                        
                        tempSpotsFirst[j] = (pairAddressFirst[j]==address(0)) ? 0 : uint256(
                            ConveyorMath.divUI(
                                reserveSizesFirst[j][0],
                                reserveSizesFirst[j][1]
                            )
                        );
                        tempSpotsSecond[j] = (pairAddressSecond[j]==address(0)) ? 0 : uint256(
                            ConveyorMath.divUI(
                                reserveSizesSecond[j][0],
                                reserveSizesSecond[j][1]
                            )
                        );
                        tempReservesFirst[j] = reserveSizesFirst[j];
                        tempReservesSecond[j] = reserveSizesSecond[j];
            }
        }

        for (uint256 i = 0; i < orders.length; i++) {

            uint256 indexFirst;
            uint256 indexSecond;

            for (uint256 k = 0; k < tempSpotsFirst.length; k++) {
                if(!(tempSpotsFirst[k]==0)){
                    if (!high) {
                        if (tempSpotsFirst[k] < targetSpotFirst) {
                            indexFirst = k;
                            targetSpotFirst = tempSpotsFirst[k];
                        }
                    } else {
                        if (tempSpotsFirst[k] > targetSpotFirst) {
                            indexFirst = k;
                            targetSpotFirst = tempSpotsFirst[k];
                        }
                    }
                }

                if(!(tempSpotsSecond[k]==0)){
                    if (!high) {
                        if (tempSpotsSecond[k] < targetSpotSecond) {
                            indexSecond = k;
                            targetSpotSecond = tempSpotsSecond[k];
                        }
                    } else {
                        if (tempSpotsSecond[k] > targetSpotSecond) {
                            indexSecond = k;
                            targetSpotSecond = tempSpotsSecond[k];
                        }
                    }
                }
            }

            Order memory order = orders[i];

            //console.logAddress(orderedPairs[i]);
            if (i != orders.length - 1) {
                (tempSpotsFirst[indexFirst], tempReservesFirst[indexFirst]) = simulatePriceChange(
                    uint128(order.quantity),
                    tempReservesFirst[indexFirst]
                );
                (tempSpotsSecond[indexSecond], tempReservesSecond[indexSecond]) = simulatePriceChange(
                    uint128(order.quantity*tempSpotsFirst[indexFirst]),
                    tempReservesSecond[indexSecond]
                );
            }
            simulatedSpotPrices[i][0]= targetSpotFirst;
            simulatedSpotPrices[i][1]= targetSpotSecond;
            orderedPairs[i][0] = pairAddressFirst[indexFirst];
            orderedPairs[i][1] = pairAddressSecond[indexSecond];
        }

        return (orderedPairs, simulatedSpotPrices);
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
    /// @param order Order order.price to be checked against realtime lp spot price for execution
    /// @param lpSpotPrice realtime best lpSpotPrice found for the order
    /// @return bool indicator whether order can be executed or not
    function orderCanExecute(Order memory order, uint256 lpSpotPrice)
        internal
        pure
        returns (bool)
        {
            if (
                order.orderType == OrderType.BUY
            ) 
            {
                return lpSpotPrice <= order.price;
           } 
            else if (
                order.orderType == OrderType.SELL
            ) 
            {
                return lpSpotPrice >= order.price;
            } 
            else if (order.orderType == OrderType.STOP) {
                return lpSpotPrice <= order.price;
            } 
            else if (order.orderType == OrderType.TAKE_PROFIT){
                return lpSpotPrice >= order.price;
            }
            return false;
        }

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
