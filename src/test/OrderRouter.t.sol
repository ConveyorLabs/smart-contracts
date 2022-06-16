// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract OrderRouterTest is DSTest {
    CheatCodes cheatCodes;

    IUniswapV2Router02 uniV2Router;
    IUniswapV2Factory uniV2Factory;

    OrderRouterWrapper orderRouter;

    //Factory and router address's
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _pancakeFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    //pancake, sushi, uni create2 factory initialization bytecode
    bytes32 _pancakeHexDem =
        0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;
    bytes32 _sushiHexDem =
        0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _sushiHexDem, _uniswapV2HexDem];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [true, true, false];

    //Dex[] dexes array of dex structs
    ConveyorLimitOrders.Dex[] public dexesArr;

    function setUp() public {
        orderRouter = new OrderRouterWrapper();

        orderRouter.addDex(_dexFactories, _hexDems, _isUniV2);

        cheatCodes = CheatCodes(HEVM_ADDRESS);
        uniV2Router = IUniswapV2Router02(_uniV2Address);
        uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);
    }

    // function testCalculateMinSpot() public view {
    //     //Test Tokens
    //     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    //     address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;
    //     address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    //     uint256 price1 = calculateMinSpotPrice(weth, usdc,1, 3000);
    //     uint256 price2 = calculateMinSpotPrice(dai, usdc, 1, 3000);
    //     uint256 price3 = calculateMinSpotPrice(weth, dai, 1, 3000);
    //     uint256 price4 = calculateMinSpotPrice(weth, wax, 1, 3000);
    //     uint256 price5 = calculateMinSpotPrice(wbtc, weth, 1, 3000);
    //     console.logString(
    //         "--------------Calculate Minimum Spot Price UniV2, Sushi, UniV3-------------------"
    //     );
    //     console.logString(
    //         "--------------Min Spot Price Output-------------------"
    //     );
    //     console.logString("--------------WETH-USDC-------------------");
    //     console.logUint(price1);
    //     console.logUint(price1);
    //     console.logString("Right shifted");
    //     console.logUint(price1 >> 9);
    //     console.logString("---------USDC-DAI--------------");
    //     console.logUint(price2);
    //     console.logString("Right shifted");
    //     console.logUint(price2 >> 9);
    //     console.logString("----------Dai-WETH-------------");
    //     console.logUint(price3);
    //     console.logString("Right shifted");
    //     console.logUint(price3 >> 9);
    //     console.logString("----------WAX-WETH-------------");
    //     console.logUint(price4);
    //     console.logString("Right shifted");
    //     console.logUint(price4 >> 9);
    //     console.logString("----------WBTC-WETH-------------");
    //     console.logUint(price5);
    //     console.logString("Right shifted");
    //     console.logUint(price5 >> 9);
    // }

    // function testCalculateV3Spot() public view {
    //     //Test Tokens
    //     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    //     // address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;

    //     //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
    //     uint256 price1 = calculateV3SpotPrice(
    //         weth,
    //         usdc,
    //         1000000000000,
    //         3000,
    //         1,
    //         _uniV3FactoryAddress
    //     );

    //     uint256 price2 = calculateV3SpotPrice(
    //         dai,
    //         usdc,
    //         1000000000000,
    //         3000,
    //         1,
    //         _uniV3FactoryAddress
    //     );

    //     uint256 price3 = calculateV3SpotPrice(
    //         weth,
    //         dai,
    //         1,
    //         3000,
    //         1,
    //         _uniV3FactoryAddress
    //     );

    //     //uint256 price4= PriceLibrary.calculateUniV3SpotPrice(wax,weth, 1, 3000,1, _uniV3FactoryAddress);

    //     console.logString("---------V3 Tick Range Price Uni----------");
    //     console.logString("---------USDC-WETH-------------");
    //     console.logUint(price1);
    //     console.logString("---------USDC-DAI--------------");
    //     console.logUint(price2);
    //     console.logString("----------Dai-WETH-------------");
    //     console.logUint(price3);
    //     console.logString("----------WAX-WETH-------------");
    //     //console.logUint(price4);
    // }

    // function testCalculateV2SpotSushi() public view {
    //     //Test tokens
    //     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    //     address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;
    //     //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
    //     uint256 price1 = calculateV2SpotPrice(
    //         weth,
    //         usdc,
    //         _sushiFactoryAddress,
    //         _sushiHexDem
    //     );
    //     uint256 price2 = calculateV2SpotPrice(
    //         dai,
    //         usdc,
    //         _sushiFactoryAddress,
    //         _sushiHexDem
    //     );
    //     uint256 price3 = calculateV2SpotPrice(
    //         weth,
    //         dai,
    //         _sushiFactoryAddress,
    //         _sushiHexDem
    //     );
    //     uint256 price4 = calculateV2SpotPrice(
    //         weth,
    //         wax,
    //         _sushiFactoryAddress,
    //         _sushiHexDem
    //     );
    //     console.logString("---------V2 Spot Price Sushi----------");
    //     console.logString("---------USDC-WETH-------------");
    //     console.logUint(price1);
    //     console.logString("---------USDC-DAI--------------");
    //     console.logUint(price2);
    //     console.logString("----------Dai-USDC-------------");
    //     console.logUint(price3);
    //     console.logString("----------WAX-WETH-------------");
    //     console.logUint(price4);
    // }

    // function testCalculateV2SpotUni() public view {
    //     //Test tokens
    //     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    //     address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;
    //     //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
    //     uint256 price1 = PriceLibrary.calculateV2SpotPrice(
    //         weth,
    //         usdc,
    //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
    //         _uniswapV2HexDem
    //     );
    //     uint256 price2 = PriceLibrary.calculateV2SpotPrice(
    //         dai,
    //         usdc,
    //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
    //         _uniswapV2HexDem
    //     );
    //     uint256 price3 = PriceLibrary.calculateV2SpotPrice(
    //         weth,
    //         dai,
    //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
    //         _uniswapV2HexDem
    //     );
    //     uint256 price4 = PriceLibrary.calculateV2SpotPrice(
    //         weth,
    //         wax,
    //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
    //         _uniswapV2HexDem
    //     );
    //     console.logString("---------V2 Spot Price Uni----------");
    //     console.logString("---------USDC-WETH-------------");
    //     console.logUint(price1);
    //     console.logString("---------USDC-DAI--------------");
    //     console.logUint(price2);
    //     console.logString("----------Dai-USDC-------------");
    //     console.logUint(price3);
    //     console.logString("----------WAX-WETH-------------");
    //     console.logUint(price4);
    // }

    function testGetPoolFee() public {
        address pairAddress = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
        assertEq(500, orderRouter.getV3PoolFee(pairAddress));
    }

    function testUniV2Swap() public {}

    function testUniV3Swap() public {}

    function testGetAllPrices() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
        (
            OrderRouter.SpotReserve[] memory prices,
            address[] memory lps
        ) = orderRouter.getAllPrices(weth, usdc, 1, 300);

        console.logString(
            "-----------------------All Dex Prices--------------------"
        );
        console.logUint(prices[0].res0);
        console.logUint(prices[0].res1);
        console.logUint(prices[0].spotPrice);

        console.logString(
            "-----------------------All lp Addresses--------------------"
        );
        console.log(lps[0]);
        console.log(lps[1]);
        console.log(lps[2]);
        console.logString(
            "-----------------------All lp reserves--------------------"
        );
    }

    //TODO: fuzz this
    function testCalculateFee() public {
        uint128 feePercent1 = orderRouter.calculateFee(100000);
        uint128 feePercent2 = orderRouter.calculateFee(150000);
        uint128 feePercent3 = orderRouter.calculateFee(200000);
        uint128 feePercent4 = orderRouter.calculateFee(50);
        uint128 feePercent5 = orderRouter.calculateFee(250);

        assertEq(feePercent1, 51363403165874997);
        assertEq(feePercent2, 37664201948990181);
        assertEq(feePercent3, 29060577804403466);
        assertEq(feePercent4, 92211856751802878);
        assertEq(feePercent5, 92124386183756525);
    }

    /// TODO: fuzz this
    function testCalculateOrderReward() public {
        //1.8446744073709550
        (uint128 rewardConveyor, uint128 rewardBeacon) = orderRouter
            .calculateReward(18446744073709550, 100000);
        console.logString("Input 1 CalculateReward");
        assertEq(39, rewardConveyor);
        assertEq(59, rewardBeacon);
    }

    function testCalculateMaxBeaconReward() public {}

    //TODO: fuzz this
    function testCalculateAlphaX() public {
        uint128 reserve0SnapShot = 47299249002010446421409070433015781392384000000 >>
                64;
        uint128 reserve1SnapShot = 16441701632611160000000000000000000000000000 >>
                64;
        uint128 reserve0Execution = 47639531368931384884872445040447549603840000000 >>
                64;
        uint128 reserve1Execution = 16324260906687270000000000000000000000000000 >>
                64;

        uint256 alphaX = orderRouter.calculateAlphaX(
            reserve0SnapShot,
            reserve1SnapShot,
            reserve0Execution,
            reserve1Execution
        );

        assertEq(340282366886892426828258718426375055715247042, alphaX);
    }

    function testChangeBase() public {
        //----------Test 1 setup----------------------//
        uint256 reserve0 = 131610640170334000000000000;
        uint8 dec0 = 18;
        uint256 reserve1 = 131610640170334;
        uint8 dec1 = 9;
        (uint256 r0_out, uint256 r1_out) = orderRouter.convertToCommonBase(
            reserve0,
            dec0,
            reserve1,
            dec1
        );

        //----------Test 2 setup-----------------//
        uint256 reserve01 = 131610640170334;
        uint8 dec01 = 6;
        uint256 reserve11 = 47925919677616776812811;
        uint8 dec11 = 18;

        (uint256 r0_out1, uint256 r1_out1) = orderRouter.convertToCommonBase(
            reserve01,
            dec01,
            reserve11,
            dec11
        );

        //Assertion checks
        assertEq(r1_out, 131610640170334000000000); // 9 decimals added
        assertEq(r0_out, 131610640170334000000000000); //No change
        assertEq(r0_out1, 131610640170334000000000000); //12 decimals added
        assertEq(r1_out1, 47925919677616776812811); //No change
    }

    function testAddDex() public {
        // addDex(_factory, _hexDem, isUniV2);
    }
}

//wrapper around OrderRouter to expose internal functions for testing
contract OrderRouterWrapper is OrderRouter {
    function calculateFee(uint128 amountIn) public returns (uint128 Out64x64) {
        return _calculateFee(amountIn);
    }

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return _getV3PoolFee(pairAddress);
    }

    function calculateReward(uint128 percentFee, uint128 wethValue)
        public
        pure
        returns (uint128 conveyorReward, uint128 beaconReward)
    {
        return _calculateReward(percentFee, wethValue);
    }

    function calculateMaxBeaconReward(
        uint128 reserve0SnapShot,
        uint128 reserve1SnapShot,
        uint128 reserve0,
        uint128 reserve1,
        uint128 fee
    ) public pure returns (uint128) {
        return
            _calculateMaxBeaconReward(
                reserve0SnapShot,
                reserve1SnapShot,
                reserve0,
                reserve1,
                fee
            );
    }

    function calculateAlphaX(
        uint128 reserve0SnapShot,
        uint128 reserve1SnapShot,
        uint128 reserve0Execution,
        uint128 reserve1Execution
    ) public pure returns (uint256) {
        return
            _calculateAlphaX(
                reserve0SnapShot,
                reserve1SnapShot,
                reserve0Execution,
                reserve1Execution
            );
    }

    function swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) public returns (uint256) {
        return _swapV2(_tokenIn, _tokenOut, _lp, _amountIn, _amountOutMin);
    }

    function swapV3(
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        address _lp,
        uint256 _amountOut,
        uint256 _amountInMaximum
    ) public returns (uint256) {
        return
            _swapV3(
                _tokenIn,
                _tokenOut,
                _fee,
                _lp,
                _amountOut,
                _amountInMaximum
            );
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
        uint112 amountIn,
        uint24 FEE,
        uint32 tickSecond,
        address _factory
    ) public view returns (SpotReserve memory, address) {
        return
            _calculateV3SpotPrice(
                token0,
                token1,
                amountIn,
                FEE,
                tickSecond,
                _factory
            );
    }

    /// @notice Helper to get all lps and prices across multiple dexes
    /// @param token0 address of token0
    /// @param token1 address of token1
    /// @param tickSecond tick second range on univ3
    /// @param FEE uniV3 fee
    function getAllPrices(
        address token0,
        address token1,
        uint32 tickSecond,
        uint24 FEE
    ) public view returns (SpotReserve[] memory prices, address[] memory lps) {
        return _getAllPrices(token0, token1, tickSecond, FEE);
    }

    /// @notice Helper to get amountIn amount for token pair
    function getTargetAmountIn(address token0, address token1)
        public
        view
        returns (uint112 amountIn)
    {
        return _getTargetAmountIn(token0, token1);
    }

    function convertToCommonBase(
        uint256 reserve0,
        uint8 token0Decimals,
        uint256 reserve1,
        uint8 token1Decimals
    ) public pure returns (uint256, uint256) {
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
}
