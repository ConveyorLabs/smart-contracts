// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v3/ISwapRouter.sol";
import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../OrderRouter.sol";
import "./utils/ScriptRunner.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/FullMath.sol";

// import "../../scripts/logistic_curve.py";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract OrderRouterTest is DSTest {
    //Python fuzz test deployer
    Swap swapHelper;

    CheatCodes cheatCodes;

    IUniswapV2Router02 uniV2Router;
    IUniswapV2Factory uniV2Factory;
    ScriptRunner scriptRunner;
    OrderRouter orderRouterContract;

    OrderRouterWrapper orderRouter;

    //Factory and router address's
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _pancakeFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    //uniV3 swap router
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    //weth
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //pancake, sushi, uni create2 factory initialization bytecode
    bytes32 _sushiHexDem =
        0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    //Dex[] dexes array of dex structs
    bytes32[] _hexDems = [_uniswapV2HexDem, _sushiHexDem, _uniswapV2HexDem];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [true, true, false];
    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //3402823669209385000000000000000000000

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        scriptRunner = new ScriptRunner();

        //Initialize swap router in constructor
        orderRouter = new OrderRouterWrapper(
            _hexDems,
            _dexFactories,
            _isUniV2,
            swapRouter,
            alphaXDivergenceThreshold,
            WETH
        );

        uniV2Router = IUniswapV2Router02(_uniV2Address);
        uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);

        swapHelper = new Swap(_uniV2Address, WETH);
    }

    //==================================Order Router Helper Functions ========================================

    ///@notice Test Lp is not uniV3
    function testLPIsNotUniv3() public {
        address uniV2LPAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        address uniV3LPAddress = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        assert(orderRouter.lpIsNotUniV3(uniV2LPAddress));
        assert(!orderRouter.lpIsNotUniV3(uniV3LPAddress));
    }

    ///@notice Test getTargetAmountIn
    function testGetTargetAmountIn() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address kope = 0x8CC9b5406049D2b66106bb39C5047666E50F06FE;
        address ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

        ///Should be the maximum decimals of the two tokens
        uint112 amountInWethUsdc = orderRouter.getTargetAmountIn(weth, usdc); //18
        uint112 amountInDaiWeth = orderRouter.getTargetAmountIn(weth, dai); //18
        uint112 amountInKopeOhm = orderRouter.getTargetAmountIn(kope, ohm); //18
        uint112 amountInOhmUsdc = orderRouter.getTargetAmountIn(usdc, ohm); //9

        //Assert the values
        assertEq(amountInWethUsdc, 10**18);
        assertEq(amountInDaiWeth, 10**18);
        assertEq(amountInKopeOhm, 10**18);
        assertEq(amountInOhmUsdc, 10**9);
    }

    ///@notice Test convertToCommonBase should convert outputs to common 18 decimals
    function testChangeBase() public {
        //----------Test 1 setup----------------------//
        uint112 reserve0 = 131610640170334000000000000;
        uint8 dec0 = 18;
        uint112 reserve1 = 131610640170334;
        uint8 dec1 = 9;
        (uint256 r0_out, uint256 r1_out) = orderRouter.convertToCommonBase(
            reserve0,
            dec0,
            reserve1,
            dec1
        );

        //----------Test 2 setup-----------------//
        uint112 reserve01 = 131610640170334;
        uint8 dec01 = 6;
        uint112 reserve11 = 47925919677616776812811;
        uint8 dec11 = 18;

        (uint256 r0_out1, uint256 r1_out1) = orderRouter.convertToCommonBase(
            reserve01,
            dec01,
            reserve11,
            dec11
        );

        //Assertion for 18 decimal common base
        assertEq(r1_out, 131610640170334000000000); // 9 decimals added
        assertEq(r0_out, 131610640170334000000000000); //No change
        assertEq(r0_out1, 131610640170334000000000000); //12 decimals added
        assertEq(r1_out1, 47925919677616776812811); //No change
    }

    ///@notice Test getTargetDecimals
    function testGetTargetDecimals() public {
        //Test Tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address kope = 0x8CC9b5406049D2b66106bb39C5047666E50F06FE;
        address ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

        uint8 targetDecimalsWeth = orderRouter.getTargetDecimals(weth);
        uint8 targetDecimalsUsdc = orderRouter.getTargetDecimals(usdc);
        uint8 targetDecimalsDai = orderRouter.getTargetDecimals(dai);
        uint8 targetDecimalsKope = orderRouter.getTargetDecimals(kope);
        uint8 targetDecimalsOhm = orderRouter.getTargetDecimals(ohm);

        assertEq(targetDecimalsWeth, uint8(18));
        assertEq(targetDecimalsUsdc, uint8(6));
        assertEq(targetDecimalsDai, uint8(18));
        assertEq(targetDecimalsKope, uint8(18));
        assertEq(targetDecimalsOhm, uint8(9));
    }

    ///@notice Test sort tokens
    function testSortTokens() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        (address check0FirstToken, address check0SecondToken) = orderRouter
            .sortTokens(weth, usdc);

        assertEq(check0FirstToken, usdc);
        assertEq(check0SecondToken, weth);

        (address check1FirstToken, address check1SecondToken) = orderRouter
            .sortTokens(usdc, weth);

        assertEq(check1FirstToken, usdc);
        assertEq(check1SecondToken, weth);
    }

    //==================================Uni V2/V3 Spot Price Calculation Tests========================================
    receive() external payable {
        // console.log("receive invoked");
    }

    ///@notice Test calculate V2 spot price on sushi
    function testCalculateV2SpotSushiTest1() public {
        //Test token address's
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        //Get Reserve0 & Reserve1 from sushi pool
        (uint112 reserve0Usdc, uint112 reserve1Weth, ) = IUniswapV2Pair(
            0x397FF1542f962076d0BFE58eA045FfA2d347ACa0
        ).getReserves();

        ///@notice Convert usdcReserve to common 18 decimal base
        uint128 reserve0UsdcCommon = reserve0Usdc * 10**12;
        uint256 expectedUsdcWeth = ConveyorMath.div128x128(
            uint256(reserve0UsdcCommon) << 128,
            uint256(reserve1Weth) << 128
        );
        (
            ConveyorLimitOrders.SpotReserve memory priceWethUsdc,
            address poolAddressWethUsdc
        ) = orderRouter.calculateV2SpotPrice(
                weth,
                usdc,
                _sushiFactoryAddress,
                _sushiHexDem
            );

        assertEq(priceWethUsdc.spotPrice, expectedUsdcWeth);
    }

    ///@notice Test calculate v2 spot price sushi weth/kope
    function testCalculateV2SpotSushiTest2() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address kope = 0x8CC9b5406049D2b66106bb39C5047666E50F06FE;

        //Token0 = Kope
        //Get Reserve0 & Reserve1 from sushi pool
        (uint112 reserve0Kope, uint112 reserve1Weth1, ) = IUniswapV2Pair(
            0x06f2e4c2AE526b587982F11117b4689B61034817
        ).getReserves();
        uint256 expectedWethKope = ConveyorMath.div128x128(
            uint256(reserve1Weth1) << 128,
            uint256(reserve0Kope) << 128
        );
        (ConveyorLimitOrders.SpotReserve memory priceWethKope, ) = orderRouter
            .calculateV2SpotPrice(
                kope,
                weth,
                _sushiFactoryAddress,
                _sushiHexDem
            );

        assertEq(priceWethKope.spotPrice, expectedWethKope);
    }

    ///@notice Test calculate v2 spot price sushi dai/ohm
    function testCalculateV2SpotSushiTest3() public {
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

        (uint112 reserve0ohm, uint112 reserve1Dai, ) = IUniswapV2Pair(
            0x055475920a8c93CfFb64d039A8205F7AcC7722d3
        ).getReserves();

        uint128 reserve0OhmCommon = reserve0ohm * 10**9;
        //Divide corresponding reserves for assertion
        uint256 expectedOhmDai = ConveyorMath.div128x128(
            uint256(reserve0OhmCommon) << 128,
            uint256(reserve1Dai) << 128
        );
        (ConveyorLimitOrders.SpotReserve memory priceOhmDai, ) = orderRouter
            .calculateV2SpotPrice(dai, ohm, _sushiFactoryAddress, _sushiHexDem);

        assertEq(priceOhmDai.spotPrice, expectedOhmDai);
    }

    ///@notice Test calculate V3 spot price weth/dai
    function testCalculateV3SpotPrice1() public {
        //Test token address's
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        address poolDaiWeth = IUniswapV3Factory(_uniV3FactoryAddress).getPool(
            weth,
            dai,
            3000
        );
        int24 tickDaiWeth = orderRouter.getTick(poolDaiWeth, 1);
        uint256 expectedDaiWeth = orderRouter.getQuoteAtTick(
            tickDaiWeth,
            1 * 10**18,
            dai,
            weth
        );

        (
            ConveyorLimitOrders.SpotReserve memory priceDaiWeth,
            address poolAddressDaiWeth
        ) = orderRouter.calculateV3SpotPrice(
                dai,
                weth,
                3000,
                _uniV3FactoryAddress
            );

        assertEq(priceDaiWeth.spotPrice, expectedDaiWeth);
        // assertEq(priceWethUsdc.spotPrice, expectedWethUsdc);
    }

    ///@notice Test calculate V3 spot price usdc/dai
    function testCalculateV3SpotPrice2() public {
        //Test token address's

        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address poolDaiUsdc = IUniswapV3Factory(_uniV3FactoryAddress).getPool(
            dai,
            usdc,
            3000
        );
        int24 tickDaiUsdc = orderRouter.getTick(poolDaiUsdc, 1);
        uint256 expectedDaiUsdc = orderRouter.getQuoteAtTick(
            tickDaiUsdc,
            1 * 10**18,
            dai,
            usdc
        );

        (ConveyorLimitOrders.SpotReserve memory priceDaiUsdc, ) = orderRouter
            .calculateV3SpotPrice(dai, usdc, 3000, _uniV3FactoryAddress);

        assertEq(priceDaiUsdc.spotPrice, expectedDaiUsdc);
    }

    ///@notice Test calculate v2 spot price Uni
    function testCalculateV2SpotUni1() public {
        //Test tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;

        (uint112 reserve0Usdc, uint112 reserve1Weth, ) = IUniswapV2Pair(
            0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc
        ).getReserves();
        uint256 reserve0Common = reserve0Usdc * 10**12;
        uint256 expectedWethUsdc = ConveyorMath.div128x128(
            uint256(reserve1Weth) << 128,
            uint256(reserve0Common) << 128
        );

        (
            ConveyorLimitOrders.SpotReserve memory price1,
            address poolAddress0
        ) = orderRouter.calculateV2SpotPrice(
                usdc,
                weth,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        uint256 spotPriceWethUsdc = price1.spotPrice;

        assertEq(spotPriceWethUsdc, expectedWethUsdc);
    }

    function testCalculateV2SpotUni2() public {
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        (uint112 reserve0Dai, uint112 reserve1Usdc, ) = IUniswapV2Pair(
            0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5
        ).getReserves();

        uint256 reserve1UsdcCommon = reserve1Usdc * 10**12;
        uint256 expectedDaiUsdc = ConveyorMath.div128x128(
            uint256(reserve0Dai) << 128,
            uint256(reserve1UsdcCommon) << 128
        );
        (
            ConveyorLimitOrders.SpotReserve memory spotPriceDaiUsdc,
            address poolAddress1
        ) = orderRouter.calculateV2SpotPrice(
                usdc,
                dai,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        assertEq(spotPriceDaiUsdc.spotPrice, expectedDaiUsdc);
    }

    function testCalculateV2SpotUni3() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;

        (uint112 reserve0Wax, uint112 reserve1Weth3, ) = IUniswapV2Pair(
            0x0ee0cb563A52Ae1170Ac34fBb94C50e89aDDE4bD
        ).getReserves();

        uint128 reserve0WaxCommon = reserve0Wax * 10**10;
        uint256 expectedWaxeWeth = ConveyorMath.div128x128(
            uint256(reserve1Weth3) << 128,
            uint256(reserve0WaxCommon) << 128
        );
        (
            ConveyorLimitOrders.SpotReserve memory spotPriceWethWax,
            address poolAddress2
        ) = orderRouter.calculateV2SpotPrice(
                wax,
                weth,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        assertEq(spotPriceWethWax.spotPrice, expectedWaxeWeth);
    }

    function testGetAllPrices2() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        (
            OrderRouter.SpotReserve[] memory pricesWethUsdc,
            address[] memory lps
        ) = orderRouter.getAllPrices(weth, usdc, 3000);

        (
            OrderRouter.SpotReserve[] memory pricesUsdcWeth,
            address[] memory lps1
        ) = orderRouter.getAllPrices(usdc, weth, 3000);

        console.log("weth/usdc");
        console.log(pricesWethUsdc[0].spotPrice);
        console.log(pricesWethUsdc[1].spotPrice);
        console.log(pricesWethUsdc[2].spotPrice);

        console.log("usdc/weth");
        console.log(pricesUsdcWeth[0].spotPrice);
        console.log(pricesUsdcWeth[1].spotPrice);
        console.log(pricesUsdcWeth[2].spotPrice);
    }

    //================================================================================================

    //=========================================Fee Helper Functions============================================
    ///@notice Test calculate Fee
    function testCalculateFee(uint112 _amount) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (_amount > 0) {
            (ConveyorLimitOrders.SpotReserve memory price1, ) = orderRouter
                .calculateV2SpotPrice(
                    weth,
                    usdc,
                    0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                    _uniswapV2HexDem
                );
            uint256 spotPrice = price1.spotPrice;

            ///@notice Calculate the weth amount in usd
            uint256 amountInUsdcDollarValue = uint256(
                ConveyorMath.mul128I(spotPrice, uint256(_amount)) /
                    uint256(10**18)
            );
            console.logUint(amountInUsdcDollarValue);

            ///@notice Pack the args
            string memory path = "scripts/logistic_curve.py";
            string memory args = uint2str(amountInUsdcDollarValue);

            //Expected output in bytes
            bytes memory output = scriptRunner.runPythonScript(path, args);

            uint256 fee = orderRouter.calculateFee(_amount, usdc, weth);

            uint256 expected = bytesToUint(output);
            //Assert the outputs, provide a small buffer of precision on the python output as this is 64.64 fixed point
            assertEq(fee / 10000, expected / 10000);
        }
    }

    ///@notice Helper function to convert bytes to uint
    function bytesToUint(bytes memory b) internal pure returns (uint256) {
        uint256 number;
        for (uint256 i = 0; i < b.length; i++) {
            number =
                number +
                uint256(uint8(b[i])) *
                (2**(8 * (b.length - (i + 1))));
        }
        return number;
    }

    ///@notice Test to calculate the Order Reward beacon
    function testCalculateOrderRewardBeacon(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = orderRouter.calculateFee(wethValue, usdc, weth);
            //1.8446744073709550
            (, uint128 rewardBeacon) = orderRouter.calculateReward(
                fee,
                wethValue
            );

            //Pack the args
            string memory path = "scripts/calculateRewardBeacon.py";
            string[] memory args = new string[](3);
            args[0] = uint2str(fee);
            args[1] = uint2str(wethValue);

            //Python script output, off by a small decimals precision
            bytes memory spotOut = scriptRunner.runPythonScript(path, args);
            uint256 beaconRewardExpected = bytesToUint(spotOut);

            //Assert the values
            assertEq(rewardBeacon / 10**3, beaconRewardExpected / 10**3);
        }
    }

    ///@notice Test calculate Conveyor Reward
    function testCalculateOrderRewardConveyor(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = orderRouter.calculateFee(wethValue, usdc, weth);
            //1.8446744073709550
            (uint128 rewardConveyor, ) = orderRouter.calculateReward(
                fee,
                wethValue
            );

            //Pack the arguments
            string memory path = "scripts/calculateRewardConveyor.py";
            string[] memory args = new string[](3);
            args[0] = uint2str(fee);
            args[1] = uint2str(wethValue);

            //Get the bytes out from the python script
            bytes memory spotOut = scriptRunner.runPythonScript(path, args);
            uint256 conveyorRewardExpected = bytesToUint(spotOut);

            //Assert the outputs with a precision buffer on fuzz
            assertEq(rewardConveyor / 10**3, conveyorRewardExpected / 10**3);
        }
    }

    ///@notice Helper function to convert a uint to a string
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + (j % 10)));
            j /= 10;
        }
        str = string(bstr);
    }

    //15233771
    ///@notice Test calculate Max beacon reward top level function
    function testCalculateMaxBeaconRewardTopLevel() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        (OrderRouter.SpotReserve[] memory pricesUsdcWeth, ) = orderRouter
            .getAllPrices(usdc, weth, 3000);

        //Sell order ==> High price more advantagous
        OrderBook.Order memory order1 = newMockOrder(
            usdc,
            weth,
            1,
            false,
            false,
            0,
            1,
            10000000,
            3000,
            0,
            0,
            0
        );

        OrderBook.Order memory order2 = newMockOrder(
            usdc,
            weth,
            1,
            false,
            false,
            0,
            1,
            10000000,
            3000,
            0,
            0,
            0
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;

        uint128 maxReward = orderRouter.calculateMaxBeaconRewardTop(
            pricesUsdcWeth,
            orderBatch,
            false
        );

        assertLt(maxReward, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        assertEq(maxReward, 3829877604957868988);
    }

    ///@notice Test Calculate Price Divergence from batch min
    function testCalculatePriceDivergenceFromBatchMin() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        OrderBook.Order memory order1 = newMockOrder(
            usdc,
            weth,
            195241231237093697621340806139528790,
            false,
            false,
            0,
            1,
            10000000,
            3000,
            0,
            0,
            0
        );

        OrderBook.Order memory order2 = newMockOrder(
            usdc,
            weth,
            195241231237093697621340806139528790, //<- min
            false,
            false,
            0,
            1,
            10000000,
            3000,
            0,
            0,
            0
        );

        //V2 outlier 128.128
        uint256 v2Outlier = 195241231237093697621340806139528792;

        //Expected target
        uint256 targetSpotExpected = order2.price;

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](2);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        bool buy = false;

        //Get the price divergence and target spot
        (uint256 priceDivergence, uint256 targetSpot) = orderRouter
            .calculatePriceDivergenceFromBatchMin(v2Outlier, orderBatch, buy);

        //Expected the 1-targetSpot/v2Outlier
        uint256 proportionalSpotChangeExpected = ConveyorMath.div128x128(
            targetSpot,
            v2Outlier
        );

        uint256 priceDivergenceExpected = (uint256(1) << 128) -
            proportionalSpotChangeExpected;

        //Assert the values
        assertEq(priceDivergence, priceDivergenceExpected);
        assertEq(targetSpot, targetSpotExpected);
    }

    ///@notice Test to calculate the price divergence between two spot prices
    function testCalculatePriceDivergence(uint128 _v3Spot, uint128 _v2Outlier)
        public
    {
        if (_v3Spot != 0 && _v2Outlier != 0 && _v2Outlier != _v3Spot) {
            //Pack the args for fuzzing
            string memory path = "scripts/calculatePriceDivergence.py";
            string[] memory args = new string[](3);
            uint256 _v3Base128 = ConveyorMath.fromUInt128(_v3Spot);
            uint256 _v2Base128 = ConveyorMath.fromUInt128(_v2Outlier);
            args[0] = uint2str(_v3Base128);
            args[1] = uint2str(_v2Base128);

            //run the script and get the expected divergence
            bytes memory priceDivergenceExpected = scriptRunner.runPythonScript(
                path,
                args
            );

            uint256 priceDivergenceExpectedInt = bytesToUint(
                priceDivergenceExpected
            );

            //Get the price divergence from the contract
            uint256 priceDivergence = orderRouter.calculatePriceDivergence(
                _v2Base128,
                _v2Base128
            );
            //Assert the outputs
            assertEq(priceDivergence, priceDivergenceExpectedInt);
        }
    }

    function testCalculateMaxBeaconReward(
        uint64 _alphaX,
        uint128 _reserve0,
        uint128 _reserve1,
        uint128 _fee
    ) public {
        bool run = false;

        //Conditional checks to help with precision of the output and test setup
        if (
            _alphaX > 0 &&
            _alphaX % 10 == 0 &&
            _reserve0 > 100 &&
            _reserve1 > 100 &&
            _alphaX < _reserve0 &&
            uint128(553402322211286500) <= _fee &&
            _fee <= uint128(922337203685477600)
        ) {
            run = true;
        }

        if (run == true) {
            uint128 k = _reserve0 * _reserve1;
            unchecked {
                //Set execution reserve to alphaX + reserve0
                uint128 reserve0Execution = _alphaX + _reserve0;
                if (reserve0Execution <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                    //Reserve1 execution
                    uint128 reserve1Execution = k / reserve0Execution;
                    //Snapshot spot price
                    uint256 snapShotSpotPrice = uint256(
                        ConveyorMath.divUI(_reserve1, _reserve0) << 64
                    );
                    //Get the max beacon reward
                    uint128 maxBeaconReward = orderRouter
                        .__calculateMaxBeaconReward(
                            snapShotSpotPrice,
                            reserve0Execution,
                            reserve1Execution,
                            _fee
                        );
                    //Expected == uni v2 fee * alphaX
                    uint128 expected = ConveyorMath.mul64x64(
                        _fee,
                        uint128(_alphaX) << 64
                    );

                    //Assert the outputs
                    assertEq(maxBeaconReward, expected);
                }
            }
        }
    }

    ///@notice Test Calculate AlphaX
    function testCalculateAlphaX(
        uint32 _alphaX,
        uint112 _reserve0,
        uint112 _reserve1
    ) public {
        bool run = false;
        ///Conditions to mimic an execution environment
        if (
            _alphaX > 1500 &&
            _alphaX % 10 == 0 &&
            _reserve0 > 10000000000000000000 &&
            _reserve1 > 100000000000000000010 &&
            _reserve0 != _reserve1 &&
            _alphaX < _reserve0
        ) {
            run = true;
        }

        if (run == true) {
            unchecked {
                ///@notice Reserve0SnapShot = reserve0-alphaX
                uint128 reserve0Snapshot = _reserve0 - _alphaX;
                if (0 < reserve0Snapshot) {
                    //Reserve 1 snapshot = k/(reserve0Snapshot)
                    uint128 reserve1Snapshot = uint128(
                        FullMath.mulDivRoundingUp(
                            uint256(_reserve0),
                            uint256(_reserve1),
                            reserve0Snapshot
                        )
                    );

                    //Snapshot spot price == reserve1Snapshot/reserve0Snapshot
                    uint128 snapShotSpotPrice = ConveyorMath.divUI(
                        uint256(reserve1Snapshot),
                        uint256(reserve0Snapshot)
                    );

                    //Execution spot price == reserve1/reserve0
                    uint128 executionSpotPrice = ConveyorMath.divUI(
                        uint256(_reserve1),
                        uint256(_reserve0)
                    );

                    //Delta == executionSpot/snapShotSpot
                    uint256 delta_temp = ConveyorMath.div128x128(
                        uint256(executionSpotPrice) << 64,
                        uint256(snapShotSpotPrice) << 64
                    );

                    //Delta = delta_temp -1
                    uint256 delta = uint256(
                        ConveyorMath.abs(
                            (int256(delta_temp) - (int256(1) << 128))
                        )
                    );

                    //Get alphaX value from contract on delta
                    uint256 alphaX = orderRouter.calculateAlphaX(
                        delta,
                        uint128(_reserve0),
                        uint128(_reserve1)
                    );

                    ///This assertion will sometimes fail becaus of 1 decimal precision errors, I believe this has to do with the reserve1Snapshot derivation in the test
                    assertEq(uint256(alphaX) / 100, uint256(_alphaX) / 100);
                }
            }
        }
    }

    //================================================================
    //======================= Helper functions =======================
    //================================================================

    function newMockOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        bool buy,
        bool taxed,
        uint16 taxIn,
        uint112 amountOutMin,
        uint112 quantity,
        uint16 feeIn,
        uint16 feeOut,
        uint32 lastRefreshTimestamp,
        uint32 expirationTimestamp
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            buy: buy,
            taxed: taxed,
            lastRefreshTimestamp: lastRefreshTimestamp,
            expirationTimestamp: expirationTimestamp,
            feeIn: feeIn,
            feeOut: feeOut,
            taxIn: taxIn,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    //================================================================================================

    //==================================Admin Function Tests===========================================
    function testAddDex() public {
        orderRouter.addDex(_uniV2FactoryAddress, _uniswapV2HexDem, true);
    }

    function testFailAddDex_MsgSenderIsNotOwner() public {
        cheatCodes.prank(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        orderRouter.addDex(_uniV2FactoryAddress, _uniswapV2HexDem, true);
    }

    //================================================================================================

    //==================================Swap Tests===========================================

    //Uniswap V2 Swap Tests
    function testSwapV2_1() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address lp = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        uint256 amountOutMin = amountReceived - 1;

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);
        address reciever = address(this);
        orderRouter.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            reciever,
            address(this)
        );
    }

    function testSwapV2_2() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address lp = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;
        ///TODO: Take a look at the amountOutMin here
        uint256 amountOutMin = 10000;

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);
        address reciever = address(this);
        orderRouter.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            reciever,
            address(this)
        );
    }

    function testSwapV2_3() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address lp = 0xa2107FA5B38d9bbd2C461D6EDf11B11A50F6b974;

        uint256 amountOutMin = 10000;

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);
        address reciever = address(this);
        orderRouter.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            reciever,
            address(this)
        );
    }

    function testFailSwapV2_InsufficientOutputAmount() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000,
            tokenIn
        );

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address lp = 0xa2107FA5B38d9bbd2C461D6EDf11B11A50F6b974;

        uint256 amountOutMin = 10000000000000000;

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);
        address reciever = address(this);
        uint256 amountOut = orderRouter.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            reciever,
            address(this)
        );
        require(amountOut != 0, "InsufficientOutputAmount");
    }

    //Uniswap V3 SwapRouter Tests
    function testSwapV3_1() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint24 fee = 500;

        uint256 amountOut = 1;
        uint256 amountInMaximum = amountReceived - 1;
        address reciever = address(this);
        orderRouter.swapV3(
            tokenIn,
            tokenOut,
            fee,
            amountInMaximum,
            amountOut,
            reciever,
            address(this)
        );
    }

    function testSwapV3_2() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint24 fee = 500;

        uint256 amountOut = 1;
        uint256 amountInMaximum = amountReceived - 1;
        address reciever = address(this);
        orderRouter.swapV3(
            tokenIn,
            tokenOut,
            fee,
            amountInMaximum,
            amountOut,
            reciever,
            address(this)
        );
    }

    function testSwapV3_3() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint24 fee = 500;

        uint256 amountOut = 1;
        uint256 amountInMaximum = amountReceived - 1;
        address reciever = address(this);
        orderRouter.swapV3(
            tokenIn,
            tokenOut,
            fee,
            amountInMaximum,
            amountOut,
            reciever,
            address(this)
        );
    }

    function testFailSwapV3_InsufficientOutputAmount() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint24 fee = 500;

        uint256 amountOut = amountReceived;
        uint256 amountInMaximum = amountReceived - 1;
        address reciever = address(this);
        uint256 amountOutSwap = orderRouter.swapV3(
            tokenIn,
            tokenOut,
            fee,
            amountInMaximum,
            amountOut,
            reciever,
            address(this)
        );

        require(amountOutSwap != 0, "InsufficientOutputAmount");
    }

    function testSwap() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        uint256 amountInMaximum = amountReceived - 1;
        address reciever = address(this);

        orderRouter.swap(
            tokenIn,
            tokenOut,
            lp,
            3000,
            amountReceived,
            amountInMaximum,
            reciever,
            address(this)
        );
    }

    function testFailSwap_InsufficientOutputAmount() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        uint256 amountInMaximum = amountReceived;
        address reciever = address(this);

        uint256 amountOut = orderRouter.swap(
            tokenIn,
            tokenOut,
            lp,
            300,
            amountReceived,
            amountInMaximum,
            reciever,
            address(this)
        );

        require(amountOut != 0, "InsufficientOutputAmount");
    }

    ///@notice Swap Token to Token on best Dex tests
    function testSwapTokenToTokenOnBestDex() public {
        cheatCodes.deal(address(this), 500000000000 ether);
        address tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        require(depositSuccess, "failure when depositing ether into weth");

        
        address tokenOut = 0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44;

        IERC20(tokenIn).approve(address(orderRouter), 200000000000000000);

        address reciever = address(this);
        
        //Test the swap
        uint256 amountOut = orderRouter.swapTokenToTokenOnBestDex(
            tokenIn,
            tokenOut,
            200000000000000000,
            2142082942848619299,
            5000,
            reciever,
            address(this)
        );

        console.log("Amount out Keeper", amountOut);
        
    }

    ///@notice Test swap Token To eth on best dex
    function testSwapTokenToEthOnBestDex() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            10000000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(orderRouter), amountReceived);

        //Execute the swap
        orderRouter.swapTokenToETHOnBestDex(tokenIn, amountReceived, 1, 3000);
        console.logUint(address(this).balance);
    }

    // receive() external payable {}

    ///@notice Test swap Eth to token on best dex
    function testSwapEthToTokenOnBestDex() public {
        cheatCodes.deal(address(this), MAX_UINT);

        //Token usdc
        address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        //Execute the swap
        (bool depositSuccess, ) = address(orderRouter).call{
            value: 1000000000000000000
        }(
            abi.encodeWithSignature(
                "swapETHToTokenOnBestDex(address,uint256,uint256,uint24)",
                tokenOut,
                1000000000000000000,
                10000,
                500
            )
        );
    }

    //================================================================================================
}

//wrapper around OrderRouter to expose internal functions for testing
contract OrderRouterWrapper is OrderRouter {
    constructor(
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _swapRouter,
        uint256 _alphaXDivergenceThreshold,
        address _weth
    )
        OrderRouter(
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _swapRouter,
            _alphaXDivergenceThreshold,
            _weth
        )
    {}

    function calculateMaxBeaconRewardTop(
        SpotReserve[] memory spotReserves,
        OrderBook.Order[] memory orders,
        bool wethIsToken0
    ) public returns (uint128) {
        return calculateMaxBeaconReward(spotReserves, orders, wethIsToken0);
    }

    function calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) public returns (uint128 Out64x64) {
        return _calculateFee(amountIn, usdc, weth);
    }

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return getV3PoolFee(pairAddress);
    }

    function calculateReward(uint128 percentFee, uint128 wethValue)
        public
        returns (uint128 conveyorReward, uint128 beaconReward)
    {
        return _calculateReward(percentFee, wethValue);
    }

    function __calculateMaxBeaconReward(
        uint256 delta,
        uint128 reserve0,
        uint128 reserve1,
        uint128 fee
    ) public returns (uint128) {
        return _calculateMaxBeaconReward(delta, reserve0, reserve1, fee);
    }

    function calculatePriceDivergence(uint256 v3Spot, uint256 v2Outlier)
        public
        returns (uint256)
    {
        return _calculatePriceDivergence(v3Spot, v2Outlier);
    }

    function calculateAlphaX(
        uint256 delta,
        uint128 reserve0Execution,
        uint128 reserve1Execution
    ) public returns (uint256) {
        return _calculateAlphaX(delta, reserve0Execution, reserve1Execution);
    }

    function lpIsNotUniV3(address lp) public returns (bool) {
        return _lpIsNotUniV3(lp);
    }

    receive() external payable {}

    function swap(
        address tokenIn,
        address tokenOut,
        address lpAddress,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin,
        address reciever,
        address sender
    ) public returns (uint256 amountOut) {
        return
            _swap(
                tokenIn,
                tokenOut,
                lpAddress,
                fee,
                amountIn,
                amountOutMin,
                reciever,
                sender
            );
    }

    function swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256) {
        return
            _swapV2(
                _tokenIn,
                _tokenOut,
                _lp,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }

    function swapV3(
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256) {
        return
            _swapV3(
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }

    function calculatePriceDivergenceFromBatchMin(
        uint256 v2Outlier,
        OrderBook.Order[] memory orders,
        bool buy
    ) public pure returns (uint256, uint256) {
        return _calculatePriceDivergenceFromBatchMin(v2Outlier, orders, buy);
    }

    function calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) public view returns (SpotReserve memory spRes, address poolAddress) {
        return _calculateV2SpotPrice(token0, token1, _factory, _initBytecode);
    }

    function calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 FEE,
        address _factory
    ) public returns (SpotReserve memory, address) {
        return _calculateV3SpotPrice(token0, token1, FEE, _factory);
    }

    /// @notice Helper to get all lps and prices across multiple dexes
    /// @param token0 address of token0
    /// @param token1 address of token1
    /// @param FEE uniV3 fee
    function getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    ) public returns (SpotReserve[] memory prices, address[] memory lps) {
        return _getAllPrices(token0, token1, FEE);
    }

    /// @notice Helper to get amountIn amount for token pair
    function getTargetAmountIn(address token0, address token1)
        public
        view
        returns (uint112 amountIn)
    {
        return _getGreatestTokenDecimalsAmountIn(token0, token1);
    }

    function convertToCommonBase(
        uint112 reserve0,
        uint8 token0Decimals,
        uint112 reserve1,
        uint8 token1Decimals
    ) public view returns (uint128, uint128) {
        return
            _convertToCommonBase(
                reserve0,
                token0Decimals,
                reserve1,
                token1Decimals
            );
    }

    function getTargetDecimals(address token)
        public
        view
        returns (uint8 targetDecimals)
    {
        return _getTargetDecimals(token);
    }

    function sortTokens(address tokenA, address tokenB)
        public
        returns (address token0, address token1)
    {
        return _sortTokens(tokenA, tokenB);
    }

    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) public returns (uint256 quoteAmount) {
        return _getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
    }

    function getTick(address pool, uint32 tickSecond)
        public
        view
        returns (int24 tick)
    {
        return _getTick(pool, tickSecond);
    }
}
