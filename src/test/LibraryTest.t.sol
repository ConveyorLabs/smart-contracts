// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../LibraryTest.sol";
import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

interface CheatCodes {
    function prank(address) external;
    function deal(address who, uint256 amount) external;
}

contract LibraryTest is DSTest {

    ABDKMathPrecision abdkMathTest;
    

    //Initialize cheatcodes
    CheatCodes cheatCodes;
   

    //MAX_UINT for testing
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    
   
    uint256 x_prb = 91200000000000000000; //91.2
    uint256 y_prb = 51200000000000000000; //51.2

    int128 x_abdkPrecision = 50; // >> 64 := 91.2
    int128 y_abdkPrecision = 50; // >> 64 := 51.2

    function setUp() public {
         abdkMathTest = new ABDKMathPrecision();
         
       
    }

    //----------------ABDK Test Results-----------------------
    function testABDKDiv() public {
        int128 out = abdkMathTest.divide(x_abdkPrecision, y_abdkPrecision);
        console.logString("ABDK Div 91.2 / 51.2");
        console.logInt(out);
    }

    function testABDKExp() public {
        int128 out = abdkMathTest.expon(y_abdkPrecision);
        console.logString("ABDK Natural 51.2");
        console.logInt(out);
    } 
  

   
    
    
}