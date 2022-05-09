// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.13;


import './Uniswap/TickMath.sol';
import './Uniswap/FullMath.sol';
import './Uniswap/OracleLibrary.sol';
import "../interfaces/UniswapV2/IUniswapV2Pair.sol";
import "../interfaces/UniswapV3/IUniswapV3Factory.sol";
import "../interfaces/UniswapV3/IUniswapV3Pool.sol";
/// @title LPMath library
/// @notice Provides functions to get price data across multiple dex's
library LPMathLibrary {
    
    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @param _factory bytes32 contract factory address
    /// @param _initBytecode bytes32 initialization bytecode for dex pair 
    /// @return spotPrice uint112 current reserve calculated spot price on dex pair
    function calculateV2PriceSingle (address token0, address token1, address _factory, bytes32 _initBytecode) internal pure returns (uint112 spotPrice) {
       
        //Return Uniswap V2 Pair address
        address pairAddress = address(uint160(uint(keccak256(abi.encodePacked(
            hex'ff',
            _factory,
            keccak256(abi.encodePacked(token0, token1)),
            _initBytecode
            )))));

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress).getReserves();

        spotPrice = reserve0/reserve1;
        
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return amountOut spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateUniV3SpotPrice(address token0, address token1, uint128 amountIn, uint24 FEE, uint32 tickSecond, address _factory) external returns (uint256 amountOut) {
        //Uniswap V3 Factory
        address factory = _factory;
       
        //tickSeconds array defines our tick interval of observation over the lp
        uint32[] memory tickSeconds = new uint32[](2);
        //int32 version of tickSecond padding in tick range
        int32 tickSecondInt = int32(tickSecond);
        //Populate tickSeconds array current block to tickSecond behind current block for tick range
        tickSeconds[0] = tickSecond;
        tickSeconds[1] = 0;

        //Pool address for token pair
        address pool = IUniswapV3Factory(factory).getPool(
            token0,
            token1,
            FEE
        );
        

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
    /// @param _factoryAddressV2 address[] array of dex factory address's to target in mean spot price calculation
    /// @param _initBytecode bytes32[] initialization bytecodes for dex pair 
    /// @return meanSpotPrice uint112 mean spot price over all dex's specified in input parameters
    function calculateMeanLPSpot (address token0, address token1, address[] calldata _factoryAddressV2, bytes32[] calldata _initBytecodesV2, address _uniV3Factory) internal pure returns (uint112 meanSpotPrice) {

    }

    /// @notice Helper function to change the base decimal value of token0 & token1 to the same target decimal value
    /// target decimal value for both token decimals to match will be max(token0Decimals, token1Decimals)
    /// @param reserve0 uint256 token1 value
    /// @param token0Decimals Decimals of token0
    /// @param reserve1 uint256 token2 value
    /// @param token1Decimals Decimals of token1
    function convertToCommonBase(uint256 reserve0, uint8 token0Decimals, uint256 reserve1, uint8 token1Decimals) external returns (uint256, uint256){

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
    /// @return uint8 target decimals of token
    function getTargetDecimals (address token) internal pure returns (uint8 targetDecimals) {

    }

   

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return initDexBytecodes bytes32[] hex initialization bytecodes for each dex
    /// initDexBytecodes = [UniswapV2, Sushiswap, Pancakeswap]
    // function deriveInitDexHash () public pure returns (bytes32[] initDexBytecodes) {
    //     bytes32[][] memory initDexBytecodes = new bytes32[](3);
    //     bytes memory bytecodeUniswap = type(UniswapV2Pair).creationCode;
    //     bytes memory bytecodeSushiswap = type(SushiswapV2Pair).creationCode;
    //     initDexBytecodes[0]=keccak256(abi.encodePacked(bytecodeUniswap));
    //     initDexBytecodes[1]=keccak256(abi.encodePacked(bytecodeUniswap));
    //     return initDexBytecodes;
    // }


}