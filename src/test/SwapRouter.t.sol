// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../lib/ConveyorFeeMath.sol";
import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v3/ISwapRouter.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../SwapRouter.sol";
import "./utils/ScriptRunner.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/FullMath.sol";
import "../OrderBook.sol";
import "../LimitOrderExecutor.sol";

//import "../../scripts/logistic_curve.py";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract SwapRouterTest is DSTest {
    //Python fuzz test deployer
    Swap swapHelper;

    CheatCodes cheatCodes;

    IUniswapV2Router02 uniV2Router;
    IUniswapV2Factory uniV2Factory;
    ScriptRunner scriptRunner;

    LimitOrderExecutorWrapper limitOrderExecutor;

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

    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    bool[] _isUniV2 = [true, true, false];
    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //3402823669209385000000000000000000000

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        scriptRunner = new ScriptRunner();

        limitOrderExecutor = new LimitOrderExecutorWrapper(
            WETH,
            USDC,
            _hexDems,
            _dexFactories,
            _isUniV2,
            address(1)
        );

        uniV2Router = IUniswapV2Router02(_uniV2Address);
        uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);

        swapHelper = new Swap(_uniV2Address, WETH);
    }

    //================================================================
    //==================== Misc Helpers ==============================
    //================================================================

    ///@notice Test Lp is not uniV3
    function testLPIsNotUniv3() public {
        address uniV2LPAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        address uniV3LPAddress = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        assert(limitOrderExecutor.lpIsNotUniV3(uniV2LPAddress));
        assert(!limitOrderExecutor.lpIsNotUniV3(uniV3LPAddress));
    }

    //================================================================
    //==================== Price Fetching ============================
    //================================================================

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
            SwapRouter.SpotReserve memory priceWethUsdc,
            address poolAddressWethUsdc
        ) = limitOrderExecutor.calculateV2SpotPrice(
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
        (SwapRouter.SpotReserve memory priceWethKope, ) = limitOrderExecutor
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
        (SwapRouter.SpotReserve memory priceOhmDai, ) = limitOrderExecutor
            .calculateV2SpotPrice(dai, ohm, _sushiFactoryAddress, _sushiHexDem);

        assertEq(priceOhmDai.spotPrice, expectedOhmDai);
    }

    ///@notice Test calculate V3 spot price weth/dai
    function testCalculateV3SpotPrice1() public {
        //Test token address's
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        (
            SwapRouter.SpotReserve memory priceDaiWeth,
            address poolAddressDaiWeth
        ) = limitOrderExecutor.calculateV3SpotPrice(
                dai,
                weth,
                3000,
                _uniV3FactoryAddress
            );

        assertEq(priceDaiWeth.spotPrice, 195219315785396777134689842230198271);
    }

    ///@notice Test calculate V3 spot price usdc/dai
    function testCalculateV3SpotPrice2() public {
        //Test token address's

        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        (SwapRouter.SpotReserve memory priceDaiUsdc, ) = limitOrderExecutor
            .calculateV3SpotPrice(dai, usdc, 3000, _uniV3FactoryAddress);
        assertEq(
            priceDaiUsdc.spotPrice,
            341140785248087661355983754903316070398
        );
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
            SwapRouter.SpotReserve memory price1,
            address poolAddress0
        ) = limitOrderExecutor.calculateV2SpotPrice(
                usdc,
                weth,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        uint256 spotPriceWethUsdc = price1.spotPrice;

        assertEq(spotPriceWethUsdc, expectedWethUsdc);
    }

    ///@notice v2 spot price assertion test
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
            SwapRouter.SpotReserve memory spotPriceDaiUsdc,
            address poolAddress1
        ) = limitOrderExecutor.calculateV2SpotPrice(
                usdc,
                dai,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        assertEq(spotPriceDaiUsdc.spotPrice, expectedDaiUsdc);
    }

    ///@notice v2 spot price assertion test
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
            SwapRouter.SpotReserve memory spotPriceWethWax,
            address poolAddress2
        ) = limitOrderExecutor.calculateV2SpotPrice(
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
            SwapRouter.SpotReserve[] memory pricesWethUsdc,
            address[] memory lps
        ) = limitOrderExecutor.getAllPrices(weth, usdc, 500);

        (
            SwapRouter.SpotReserve[] memory pricesUsdcWeth,
            address[] memory lps1
        ) = limitOrderExecutor.getAllPrices(usdc, weth, 500);

        console.log("weth/usdc");
        console.log(pricesWethUsdc[0].spotPrice);
        console.log(pricesWethUsdc[1].spotPrice);
        console.log(pricesWethUsdc[2].spotPrice);

        console.log("usdc/weth");
        console.log(pricesUsdcWeth[0].spotPrice);
        console.log(pricesUsdcWeth[1].spotPrice);
        console.log(pricesUsdcWeth[2].spotPrice);
    }

    //================================================================
    //==================== Price Simulation ==========================
    //================================================================

    function testCalculateNewExecutionPriceTokenToWeth(uint32 amountIn) public {
        bool run = true;
        if (amountIn < 1000000) {
            run = false;
        }
        if (run) {
            cheatCodes.deal(address(swapHelper), MAX_UINT);

            (
                SwapRouter.SpotReserve[] memory spots,
                address[] memory pools
            ) = limitOrderExecutor.getAllPrices(USDC, WETH, 500);
            uint256 bestPrice = type(uint256).max;
            uint256 bestPriceIndex;
            SwapRouter.TokenToWethExecutionPrice[]
                memory executionPrices = limitOrderExecutor
                    .initializeTokenToWethExecutionPrices(spots, pools);
            {
                for (uint256 i = 0; i < executionPrices.length; ++i) {
                    if (executionPrices[i].price < bestPrice) {
                        bestPrice = executionPrices[i].price;
                        bestPriceIndex = i;
                    }
                }

                ///@notice Create a new mock order
                OrderBook.Order memory order = newMockOrder(
                    USDC,
                    WETH,
                    1,
                    false,
                    true,
                    0,
                    1,
                    amountIn,
                    500,
                    0,
                    0,
                    type(uint32).max
                );

                SwapRouter.TokenToWethExecutionPrice
                    memory newPriceToValidate = limitOrderExecutor
                        ._calculateNewExecutionPriceTokenToWeth(
                            executionPrices,
                            bestPriceIndex,
                            order
                        );

                uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
                    1000000000 ether,
                    USDC
                );

                IERC20(USDC).approve(address(limitOrderExecutor), amountIn);

                limitOrderExecutor._swap(
                    USDC,
                    WETH,
                    0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640,
                    500,
                    amountIn,
                    1,
                    address(this),
                    address(this)
                );

                (SwapRouter.SpotReserve memory newSpot, ) = limitOrderExecutor
                    .calculateV3SpotPrice(
                        USDC,
                        WETH,
                        500,
                        0x1F98431c8aD98523631AE4a59f267346ea31F984
                    );
                uint128 spotToValidate64X = uint128(
                    newPriceToValidate.price >> 64
                );
                uint128 newSpot64X = uint128(newSpot.spotPrice >> 64);
                uint128 divergence = ConveyorMath.div64x64(
                    spotToValidate64X < newSpot64X
                        ? newSpot64X
                        : spotToValidate64X,
                    spotToValidate64X > newSpot64X
                        ? newSpot64X
                        : spotToValidate64X
                ) - (uint128(1) << 64);

                assertLe(divergence, 18446744073709);
            }
        }
    }

    function testCalculateNewExecutionPriceTokenToTokenAToWeth(uint32 amountIn)
        public
    {
        bool run = true;
        if (amountIn < 1000000) {
            run = false;
        }
        if (run) {
            cheatCodes.deal(address(swapHelper), MAX_UINT);
            SwapRouter.TokenToTokenExecutionPrice[] memory executionPrices;
            {
                (
                    SwapRouter.SpotReserve[] memory spotsUsdc,
                    address[] memory poolsUsdc
                ) = limitOrderExecutor.getAllPrices(USDC, WETH, 500);
                (
                    SwapRouter.SpotReserve[] memory spotsWeth,
                    address[] memory poolsWeth
                ) = limitOrderExecutor.getAllPrices(WETH, DAI, 500);
                executionPrices = limitOrderExecutor
                    .initializeTokenToTokenExecutionPrices(
                        USDC,
                        spotsUsdc,
                        poolsUsdc,
                        spotsWeth,
                        poolsWeth
                    );
            }
            uint256 bestPrice = type(uint256).max;
            uint256 bestPriceIndex;

            {
                for (uint256 i = 0; i < executionPrices.length; ++i) {
                    if (executionPrices[i].price < bestPrice) {
                        bestPrice = executionPrices[i].price;
                        bestPriceIndex = i;
                    }
                }

                ///@notice Create a new mock order
                OrderBook.Order memory order = newMockOrder(
                    USDC,
                    WETH,
                    1,
                    false,
                    true,
                    0,
                    1,
                    amountIn,
                    500,
                    0,
                    0,
                    type(uint32).max
                );

                (, uint256 price) = limitOrderExecutor
                    ._calculateNewExecutionPriceTokenToTokenAToWeth(
                        executionPrices,
                        bestPriceIndex,
                        order
                    );

                swapHelper.swapEthForTokenWithUniV2(1000000000 ether, USDC);

                IERC20(USDC).approve(address(limitOrderExecutor), amountIn);

                limitOrderExecutor._swap(
                    USDC,
                    WETH,
                    0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640,
                    500,
                    amountIn,
                    1,
                    address(this),
                    address(this)
                );

                (SwapRouter.SpotReserve memory newSpot, ) = limitOrderExecutor
                    .calculateV3SpotPrice(
                        USDC,
                        WETH,
                        500,
                        0x1F98431c8aD98523631AE4a59f267346ea31F984
                    );
                console.log(price, newSpot.spotPrice);
                uint128 spotToValidate64X = uint128(price >> 64);
                uint128 newSpot64X = uint128(newSpot.spotPrice >> 64);
                uint128 divergence = ConveyorMath.div64x64(
                    spotToValidate64X < newSpot64X
                        ? newSpot64X
                        : spotToValidate64X,
                    spotToValidate64X > newSpot64X
                        ? newSpot64X
                        : spotToValidate64X
                ) - (uint128(1) << 64);

                assertLe(divergence, 18446744073709);
            }
        }
    }

    function testCalculateNewExecutionPriceTokenToTokenWethToB(uint32 amountIn)
        public
    {
        bool run = true;
        if (amountIn < 1000000) {
            run = false;
        }
        if (run) {
            cheatCodes.deal(address(this), MAX_UINT);
            SwapRouter.TokenToTokenExecutionPrice[] memory executionPrices;
            SwapRouter.SpotReserve[] memory spotsUsdc;
            address[] memory poolsUsdc;
            {
                (
                    spotsUsdc,
                    poolsUsdc
                ) = limitOrderExecutor.getAllPrices(USDC, WETH, 500);
                (
                    SwapRouter.SpotReserve[] memory spotsWeth,
                    address[] memory poolsWeth
                ) = limitOrderExecutor.getAllPrices(WETH, DAI, 500);
                executionPrices = limitOrderExecutor
                    .initializeTokenToTokenExecutionPrices(
                        USDC,
                        spotsUsdc,
                        poolsUsdc,
                        spotsWeth,
                        poolsWeth
                    );
            }
            uint256 bestPrice = type(uint256).max;
            uint256 bestPriceIndex;

            {
                for (uint256 i = 0; i < executionPrices.length; ++i) {
                    if (executionPrices[i].price < bestPrice) {
                        bestPrice = executionPrices[i].price;
                        bestPriceIndex = i;
                    }
                }
            }

            {
                
                ///@notice Create a new mock order
                OrderBook.Order memory order = newMockOrder(
                    USDC,
                    DAI,
                    1,
                    false,
                    true,
                    0,
                    1,
                    amountIn,
                    500,
                    0,
                    0,
                    type(uint32).max
                );

                SwapRouter.TokenToTokenExecutionPrice
                    memory executionP = limitOrderExecutor
                        ._calculateNewExecutionPriceTokenToTokenWethToB(
                            executionPrices,
                            bestPriceIndex,
                            spotsUsdc[2].spotPrice,
                            order,
                            false
                        );

                address(WETH).call{
                    value: 500000000000 ether
                }(abi.encodeWithSignature("deposit()"));

                IERC20(WETH).approve(address(limitOrderExecutor), amountIn);

                limitOrderExecutor._swap(
                    WETH,
                    DAI,
                    0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8,
                    3000,
                    amountIn,
                    1,
                    address(this),
                    address(this)
                );

                (SwapRouter.SpotReserve memory newSpot, ) = limitOrderExecutor
                    .calculateV3SpotPrice(
                        WETH,
                        DAI,
                        3000,
                        0x1F98431c8aD98523631AE4a59f267346ea31F984
                    );

                uint128 spotToValidate64X = uint128(executionP.price >> 64);
                uint128 newSpot64X = uint128(newSpot.spotPrice >> 64);
                uint128 divergence = ConveyorMath.div64x64(
                    spotToValidate64X < newSpot64X
                        ? newSpot64X
                        : spotToValidate64X,
                    spotToValidate64X > newSpot64X
                        ? newSpot64X
                        : spotToValidate64X
                ) - (uint128(1) << 64);

                assertLe(divergence, 18446744073709);
            }
        }
    }

    //================================================================================================

    // //=========================================Fee Helper Functions============================================
    ///@notice Test calculate Fee
    function testCalculateFee(uint112 _amount) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (_amount > 0) {
            (SwapRouter.SpotReserve memory price1, ) = limitOrderExecutor
                .calculateV2SpotPrice(
                    weth,
                    usdc,
                    0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                    _uniswapV2HexDem
                );
            uint256 spotPrice = price1.spotPrice;

            ///@notice Calculate the weth amount in usd
            uint256 amountInUsdcDollarValue = uint256(
                ConveyorMath.mul128U(spotPrice, uint256(_amount)) /
                    uint256(10**18)
            );
            console.logUint(amountInUsdcDollarValue);

            ///@notice Pack the args
            string memory path = "scripts/logistic_curve.py";
            string memory args = uint2str(amountInUsdcDollarValue);

            //Expected output in bytes
            bytes memory output = scriptRunner.runPythonScript(path, args);

            uint256 fee = limitOrderExecutor.calculateFee(_amount, usdc, weth);

            uint256 expected = bytesToUint(output);
            //Assert the outputs, provide a small buffer of precision on the python output as this is 64.64 fixed point
            assertEq(fee / 10000, expected / 10000);
        }
    }

    function testFailUniswapV3Callback_UnauthorizedUniswapV3CallbackCaller()
        public
    {
        bytes memory data = abi.encode(
            100,
            true,
            address(this),
            address(this),
            address(this)
        );

        limitOrderExecutor.uniswapV3SwapCallback(0, 0, data);
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

    // ///@notice Test to calculate the Order Reward beacon
    function testCalculateOrderRewardBeacon(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = limitOrderExecutor.calculateFee(
                wethValue,
                usdc,
                weth
            );
            //1.8446744073709550
            (, uint128 rewardBeacon) = ConveyorFeeMath.calculateReward(
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

    // ///@notice Test calculate Conveyor Reward
    function testCalculateOrderRewardConveyor(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = limitOrderExecutor.calculateFee(
                wethValue,
                usdc,
                weth
            );
            //1.8446744073709550
            (uint128 rewardConveyor, ) = ConveyorFeeMath.calculateReward(
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
    ) internal view returns (OrderBook.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            stoploss: false,
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

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);
        address receiver = address(this);
        limitOrderExecutor.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            receiver,
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
        uint256 amountOutMin = 10000;

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);
        address receiver = address(this);
        limitOrderExecutor.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            receiver,
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

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);
        address receiver = address(this);
        limitOrderExecutor.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            receiver,
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

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);
        address receiver = address(this);
        uint256 amountOut = limitOrderExecutor.swapV2(
            tokenIn,
            tokenOut,
            lp,
            amountReceived,
            amountOutMin,
            receiver,
            address(this)
        );
        require(amountOut != 0, "InsufficientOutputAmount");
    }

    //Uniswap V3 SwapRouter Tests
    function testSwapV3_1() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        //get the token in
        cheatCodes.deal(address(this), MAX_UINT);

        (bool depositSuccess, ) = address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        address tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        IERC20(tokenIn).approve(
            address(limitOrderExecutor),
            1000000000000000000
        );

        address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        address _lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        address receiver = address(this);
        limitOrderExecutor.swapV3(
            _lp,
            tokenIn,
            tokenOut,
            500,
            1000000000000000000,
            1,
            receiver,
            address(this)
        );
    }

    //Uniswap V3 SwapRouter Tests
    function testSwapV3_2() public {
        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000 ether,
            tokenIn
        );

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);

        address _lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        address receiver = address(this);

        limitOrderExecutor.swapV3(
            _lp,
            tokenIn,
            tokenOut,
            500,
            amountReceived,
            1,
            receiver,
            address(this)
        );
    }

    function testSwap() public {
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        //get the token in
        uint256 amountReceived = swapHelper.swapEthForTokenWithUniV2(
            1000000000000000,
            tokenIn
        );

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        uint256 amountInMaximum = amountReceived - 1;
        address receiver = address(this);

        limitOrderExecutor._swap(
            tokenIn,
            tokenOut,
            lp,
            500,
            amountReceived,
            amountInMaximum,
            receiver,
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

        IERC20(tokenIn).approve(address(limitOrderExecutor), amountReceived);

        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

        address receiver = address(this);

        uint256 amountOut = limitOrderExecutor._swap(
            tokenIn,
            tokenOut,
            lp,
            300,
            amountReceived,
            1000000000000000,
            receiver,
            address(this)
        );

        require(amountOut != 0, "InsufficientOutputAmount");
    }

    //================================================================================================
}

//wrapper around SwapRouter to expose internal functions for testing
contract LimitOrderExecutorWrapper is LimitOrderExecutor {
    constructor(
        address _weth,
        address _usdc,
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _gasOracle
    )
        LimitOrderExecutor(
            _weth,
            _usdc,
            _deploymentByteCodes,
            _dexFactories,
            _isUniV2,
            _gasOracle
        )
    {}

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return getV3PoolFee(pairAddress);
    }

    function _calculateNewExecutionPriceTokenToTokenAToWeth(
        TokenToTokenExecutionPrice[] memory executionPrices,
        uint256 bestPriceIndex,
        OrderBook.Order memory order
    ) public view returns (TokenToTokenExecutionPrice memory, uint256) {
        return
            calculateNewExecutionPriceTokenToTokenAToWeth(
                executionPrices,
                bestPriceIndex,
                order
            );
    }

    function _calculateNewExecutionPriceTokenToTokenWethToB(
        TokenToTokenExecutionPrice[] memory executionPrices,
        uint256 bestPriceIndex,
        uint256 spotPriceAToWeth,
        OrderBook.Order memory order,
        bool wethIsToken0
    ) public view returns (TokenToTokenExecutionPrice memory) {
        return
            calculateNewExecutionPriceTokenToTokenWethToB(
                executionPrices,
                bestPriceIndex,
                spotPriceAToWeth,
                order,
                wethIsToken0
            );
    }

    function _calculateNewExecutionPriceTokenToWeth(
        TokenToWethExecutionPrice[] memory executionPrices,
        uint256 bestPriceIndex,
        OrderBook.Order memory order
    ) public view returns (TokenToWethExecutionPrice memory) {
        return
            calculateNewExecutionPriceTokenToWeth(
                executionPrices,
                bestPriceIndex,
                order
            );
    }

    function lpIsNotUniV3(address lp) public returns (bool) {
        return _lpIsNotUniV3(lp);
    }

    // receive() external payable {}

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
        address _lp,
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
                _lp,
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }

    function getAllPrices(
        address token0,
        address token1,
        uint24 FEE
    ) public view returns (SpotReserve[] memory prices, address[] memory lps) {
        return _getAllPrices(token0, token1, FEE);
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

    function calculateFee(
        uint128 amountIn,
        address usdc,
        address weth
    ) public view returns (uint128) {
        return _calculateFee(amountIn, usdc, weth);
    }

    function initializeTokenToWethExecutionPrices(
        SwapRouter.SpotReserve[] memory spotReserveAToWeth,
        address[] memory lpAddressesAToWeth
    ) public view returns (SwapRouter.TokenToWethExecutionPrice[] memory) {
        return
            _initializeTokenToWethExecutionPrices(
                spotReserveAToWeth,
                lpAddressesAToWeth
            );
    }

    function initializeTokenToTokenExecutionPrices(
        address tokenIn,
        SpotReserve[] memory spotReserveAToWeth,
        address[] memory lpAddressesAToWeth,
        SpotReserve[] memory spotReserveWethToB,
        address[] memory lpAddressWethToB
    ) public view returns (TokenToTokenExecutionPrice[] memory) {
        return
            _initializeTokenToTokenExecutionPrices(
                tokenIn,
                spotReserveAToWeth,
                lpAddressesAToWeth,
                spotReserveWethToB,
                lpAddressWethToB
            );
    }

    function _swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256 amountReceived) {
        return
            swap(
                _tokenIn,
                _tokenOut,
                _lp,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }
}
