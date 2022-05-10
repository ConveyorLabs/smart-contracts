// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.13;


import './Uniswap/TickMath.sol';
import './Uniswap/FullMath.sol';
import './Uniswap/OracleLibrary.sol';
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";
import "../interfaces/UniswapV2/IUniswapV2Factory.sol";
import "../interfaces/UniswapV3/IUniswapV3Factory.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
import '../../src/ConveyorLimitOrders.sol';
import "../interfaces/ERC20.sol";
import "../../src/test/utils/Console.sol";

/// @title PriceLibrary library
/// @notice Provides functions to get price data across multiple dex's
library PriceLibrary {
    

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param _factory bytes32 contract factory address
    /// @param _initBytecode bytes32 initialization bytecode for dex pair 
    /// @return spotPrice uint112 current reserve calculated spot price on dex pair
    function calculateV2PriceSingle (address token0, address token1, address _factory, bytes32 _initBytecode) internal view returns (uint256 spotPrice) {
        require(token0 != token1, "Invalid Token Pair, IDENTICAL Address's");
        (address tok0, address tok1) = sortTokens(token0, token1);
        //Return Uniswap V2 Pair address
        address pairAddress = address(uint160(uint(keccak256(abi.encodePacked(
            hex'ff',
            _factory,
            keccak256(abi.encodePacked(tok0, tok1)),
            _initBytecode
            )))));

        
        require(pairAddress != address(0), "Invalid token pair");
        if(!(IUniswapV2Factory(_factory).getPair(tok0, tok1)==pairAddress)){
            console.logString("Factory Address");
            console.log(IUniswapV2Factory(_factory).getPair(tok0, tok1));
            return 0;
        }
        
        
        //Set reserve0, reserve1 to current LP reserves
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress).getReserves();
      

        //Get target decimals for token0 & token1
        uint8 token0Decimals = getTargetDecimals(tok0);
        uint8 token1Decimals = getTargetDecimals(tok1);

        //Set common based reserve values
        (uint256 commonReserve0, uint256 commonReserve1) = convertToCommonBase(reserve0, token0Decimals, reserve1, token1Decimals);
        
        
        // Left shift commonReserve0 9 digits i.e. commonReserve0 = commonReserve0 * 2 ** 9
        spotPrice = ((commonReserve0 << 9)/commonReserve1);
        
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return amountOut spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateUniV3SpotPrice(address token0, address token1, uint112 amountIn, uint24 FEE, uint32 tickSecond, address _factory) internal view returns (uint256 amountOut) {
        
        //tickSeconds array defines our tick interval of observation over the lp
        uint32[] memory tickSeconds = new uint32[](2);
        //int32 version of tickSecond padding in tick range
        int32 tickSecondInt = int32(tickSecond);
        //Populate tickSeconds array current block to tickSecond behind current block for tick range
        tickSeconds[0] = tickSecond;
        tickSeconds[1] = 0;

        //Pool address for token pair
        address pool = IUniswapV3Factory(_factory).getPool(
            token0,
            token1,
            FEE
        );
        
        if(pool==address(0)){
            return 0;
        }
         //Start observation over lp in prespecified tick range
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            tickSeconds
        );

        //Spot price of tickSeconds ago - spot price of current block
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / (tickSecondInt));

         //so if tickCumulativeDelta < 0 and division has remainder, then rounddown    
        if (
            tickCumulativesDelta < 0 && (tickCumulativesDelta % tickSecondInt != 0)
        ) {
            tick--;
        }
        //amountOut = tick range spot over specified tick interval
        amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            amountIn,
            token0,
            token1
        );
        
    }
    /// @notice Helper function to get Mean spot price over multiple LP spot prices
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param dexes address[] array of dex factory address's to target in mean spot price calculation
    /// @param tickSecond uint32 tick seconds to calculate v3 price average over
    /// @param FEE LP token pair fee
    /// @return meanSpotPrice uint112 mean spot price over all dex's specified in input parameters
    function calculateMeanLPSpot (address token0, address token1, ConveyorLimitOrders.Dex[] memory dexes, uint32 tickSecond, uint24 FEE) internal view returns (uint256) {
        //Initialize meanSpotPrice to 0
        uint256 meanSpotPrice=0;
        uint8 incrementor = 0;
        //Target base amount in value
        uint112 amountIn = getTargetAmountIn(token0, token1);

        //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to meanSpotPrice
        for (uint256 i =0; i<dexes.length; ++i){
            if(dexes[i].isUniV2){
                //Right shift spot price 9 decimals and add to meanSpotPrice
                    uint256 spotPrice = calculateV2PriceSingle(token0, token1, dexes[i].factoryAddress, dexes[i].initBytecode);
                    meanSpotPrice += spotPrice;

                    incrementor+= (spotPrice==0) ? 0 : 1;
                
                
            }else{
                    uint256 spotPrice = calculateUniV3SpotPrice(token0,token1, amountIn, FEE, tickSecond, dexes[i].factoryAddress);
                    meanSpotPrice += (spotPrice << 9);
                    incrementor+= (spotPrice==0) ? 0 : 1;
           
            }
            
        }

        return meanSpotPrice / incrementor;
    }

    /// @notice Helper to get amountIn amount for token pair
    function getTargetAmountIn(address token0, address token1) internal view returns (uint112 amountIn) {
        //Get target decimals for token0, token1
        uint8 token0Target = getTargetDecimals(token0);
        uint8 token1Target = getTargetDecimals(token1);
        
        //target decimal := the difference in decimal targets between tokens
        uint8 targetDec = (token0Target<token1Target) ? (token1Target - token0Target) : (token0Target - token1Target);
        
        //Set amountIn to correct target decimals
        amountIn = uint112(10**(targetDec));
    }

    /// @notice Helper function to change the base decimal value of token0 & token1 to the same target decimal value
    /// target decimal value for both token decimals to match will be max(token0Decimals, token1Decimals)
    /// @param reserve0 uint256 token1 value
    /// @param token0Decimals Decimals of token0
    /// @param reserve1 uint256 token2 value
    /// @param token1Decimals Decimals of token1
    function convertToCommonBase(uint256 reserve0, uint8 token0Decimals, uint256 reserve1, uint8 token1Decimals) internal pure returns (uint256, uint256){

        /// @dev Conditionally change the decimal to target := max(decimal0, decimal1)
        /// return tuple of modified reserve values in matching decimals
        if(token0Decimals>token1Decimals){
            return (reserve0, reserve1*(10**(token0Decimals-token1Decimals)));
        }else{
            return(reserve0*(10**(token1Decimals-token0Decimals)), reserve1);
        }

    }

    /// @notice Helper function to get target decimals of ERC20 token
    /// @param token address of token to get target decimals
    /// @return targetDecimals uint8 target decimals of token
    function getTargetDecimals (address token) internal view returns (uint8 targetDecimals) {
        return ERC20(token).decimals();
    }

    /// @notice Helper function to return sorted token addresses
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }


    /// @notice Helper function to get Min spot price over multiple LP spot prices
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param dexes address[] array of dex factory address's to target in mean spot price calculation
    /// @param tickSecond uint32 tick seconds to calculate v3 price average over
    /// @param FEE LP token pair fee
    /// @return meanSpotPrice uint112 mean spot price over all dex's specified in input parameters
    function calculateMinLPSpotPrice(address token0, address token1, ConveyorLimitOrders.Dex[] memory dexes, uint32 tickSecond, uint24 FEE) internal view returns (uint256) {
        //Initialize meanSpotPrice to 0
        uint256 minSpotPrice=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
       
        //Target base amount in value
        uint112 amountIn = getTargetAmountIn(token0, token1);

        //Iterate through Dex's in dexes check if isUniV2 and accumulate spot price to minSpotPrice
        for (uint256 i =0; i<dexes.length; ++i){
            if(dexes[i].isUniV2){
                //Right shift spot price 9 decimals and add to meanSpotPrice
                    uint256 spotPrice = calculateV2PriceSingle(token0, token1, dexes[i].factoryAddress, dexes[i].initBytecode);
                    minSpotPrice = (spotPrice < minSpotPrice && spotPrice !=0) ? spotPrice : minSpotPrice;

                
            }else{
                    uint256 spotPrice = calculateUniV3SpotPrice(token0,token1, amountIn, FEE, tickSecond, dexes[i].factoryAddress);
                    minSpotPrice = ((spotPrice << 9) < minSpotPrice && spotPrice !=0) ? spotPrice : minSpotPrice;
                    
           
            }
            
        }
        
        assert(minSpotPrice !=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        return minSpotPrice;
    }

}