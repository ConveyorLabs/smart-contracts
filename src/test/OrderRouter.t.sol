// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

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
    //Python fuzz test deployer

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
    bytes32 _sushiHexDem =
        0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //Dex[] dexes array of dex structs
    ConveyorLimitOrders.Dex public uniswapV2;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        orderRouter = new OrderRouterWrapper();
        uniswapV2.factoryAddress = _uniV2FactoryAddress;

        orderRouter.addDex(_uniV2FactoryAddress, _uniswapV2HexDem, true);
        orderRouter.addDex(_sushiFactoryAddress, _sushiHexDem, true);
        ///@notice
        orderRouter.addDex(_uniV3FactoryAddress, 0x00, false);

        uniV2Router = IUniswapV2Router02(_uniV2Address);
        uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);
    }

    function testCalculateV2SpotUni() public {
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
                weth,
                usdc,
                0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
                _uniswapV2HexDem
            );

        ///Note: Just commented out to prevent stack too deep
        ///Todo: Seperate these into their own test functions
        // (uint112 reserve0Dai, uint112 reserve1Usdc, ) = IUniswapV2Pair(
        //     0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5
        // ).getReserves();

        // uint256 reserve1UsdcCommon = reserve1Usdc * 10**12;
        // uint256 expectedDaiUsdc = ConveyorMath.div128x128(
        //     uint256(reserve0Dai) << 128,
        //     uint256(reserve1UsdcCommon) << 128
        // );
        // (
        //     ConveyorLimitOrders.SpotReserve memory price2,
        //     address poolAddress1
        // ) = orderRouter.calculateV2SpotPrice(
        //         dai,
        //         usdc,
        //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
        //         _uniswapV2HexDem
        //     );

        // (uint112 reserve0Wax, uint112 reserve1Weth3, ) = IUniswapV2Pair(
        //     0x0ee0cb563A52Ae1170Ac34fBb94C50e89aDDE4bD
        // ).getReserves();

        // uint128 reserve0WaxCommon = reserve0Wax * 10**10;
        // uint256 expectedWaxeWeth = ConveyorMath.div128x128(
        //     uint256(reserve1Weth3) << 128,
        //     uint256(reserve0WaxCommon) << 128
        // );
        // (
        //     ConveyorLimitOrders.SpotReserve memory price3,
        //     address poolAddress2
        // ) = orderRouter.calculateV2SpotPrice(
        //         weth,
        //         wax,
        //         0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
        //         _uniswapV2HexDem
        //     );

        uint256 spotPriceWethUsdc = price1.spotPrice;
        // uint256 spotPriceDaiUsdc = price2.spotPrice;
        // uint256 spotPriceWethWax = price3.spotPrice;

        // assertEq(spotPriceWethWax, expectedWaxeWeth);
        assertEq(spotPriceWethUsdc, expectedWethUsdc);
        // assertEq(spotPriceDaiUsdc, expectedDaiUsdc);
    }

    function testCalculateV2SpotSushi() public {
        //Test token address's
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address kope = 0x8CC9b5406049D2b66106bb39C5047666E50F06FE;
        address ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

        //Get Reserve0 & Reserve1 from sushi pool
        (uint112 reserve0Usdc, uint112 reserve1Weth, ) = IUniswapV2Pair(
            0x397FF1542f962076d0BFE58eA045FfA2d347ACa0
        ).getReserves();

        uint128 reserve0UsdcCommon = reserve0Usdc * 10**12;
        uint256 expectedUsdcWeth = ConveyorMath.div128x128(
            uint256(reserve1Weth) << 128,
            uint256(reserve0UsdcCommon) << 128
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
        ///Note: Keep these just commented out to prevent stack too deep
        ///Todo: Seperate these into their own tests
        //Token0 = Kope
        //Get Reserve0 & Reserve1 from sushi pool
        // (uint112 reserve0Kope, uint112 reserve1Weth1, ) = IUniswapV2Pair(
        //     0x06f2e4c2AE526b587982F11117b4689B61034817
        // ).getReserves();
        // uint256 expectedWethKope = ConveyorMath.div128x128(
        //     uint256(reserve1Weth1) << 128,
        //     uint256(reserve0Kope) << 128
        // );
        // (
        //     ConveyorLimitOrders.SpotReserve memory priceWethKope,
        //     address poolAddressWethKope
        // ) = orderRouter.calculateV2SpotPrice(
        //         weth,
        //         kope,
        //         _sushiFactoryAddress,
        //         _sushiHexDem
        //     );

        //Get Reserve0 & Reserve1 from sushi pool
        //Note: Token0 Ohm
        // (uint112 reserve0ohm, uint112 reserve1Dai, ) = IUniswapV2Pair(
        //     0x055475920a8c93CfFb64d039A8205F7AcC7722d3
        // ).getReserves();

        // uint128 reserve0OhmCommon = reserve0ohm * 10**9;
        // //Divide corresponding reserves for assertion
        // uint256 expectedOhmDai = ConveyorMath.div128x128(
        //     uint256(reserve0OhmCommon) << 128,
        //     uint256(reserve1Dai) << 128
        // );
        // (
        //     ConveyorLimitOrders.SpotReserve memory priceOhmDai,
        //     address poolAddressOhmDai
        // ) = orderRouter.calculateV2SpotPrice(
        //         ohm,
        //         dai,
        //         _sushiFactoryAddress,
        //         _sushiHexDem
        //     );

        //Spot Price assertions
        // assertEq(priceOhmDai.spotPrice, expectedOhmDai);
        //assertEq(priceWethKope.spotPrice, expectedWethKope);
        assertEq(priceWethUsdc.spotPrice, expectedUsdcWeth);
    }

    function testCalculateV3SpotPrice() public {
        //Test token address's
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

        //Pool address for token pair
        address poolUsdcWeth = IUniswapV3Factory(_uniV3FactoryAddress).getPool(usdc, weth, 100);

        int24 tickUsdcWeth  = orderRouter.getTick(poolUsdcWeth, 1);

        uint256 expectedWethUsdc = orderRouter.getQuoteAtTick(tickUsdcWeth, 1*10**6, usdc, weth);
    
        (
            ConveyorLimitOrders.SpotReserve memory priceWethUsdc,
            address poolAddressWethUsdc
        ) = orderRouter.calculateV3SpotPrice(
                usdc,
                weth,
                 1*10**6,
                 100,
                 1,
                _uniV3FactoryAddress
            );
        
        address poolDaiWeth = IUniswapV3Factory(_uniV3FactoryAddress).getPool(dai, weth, 100);
        int24 tickDaiWeth = orderRouter.getTick(poolDaiWeth, 1);
        uint256 expectedDaiWeth = orderRouter.getQuoteAtTick(tickDaiWeth, 1*10**18, dai, weth);

        (
            ConveyorLimitOrders.SpotReserve memory priceDaiWeth,
            address poolAddressDaiWeth
        ) = orderRouter.calculateV3SpotPrice(
                dai,
                weth,
                 1*10**18,
                 100,
                 1,
                _uniV3FactoryAddress
            );

        ///Note: Just commented out to prevent stack too deep
        ///Todo: Seperate these into their own functions to prevent stack too deep
        // address poolDaiUsdc = IUniswapV3Factory(_uniV3FactoryAddress).getPool(dai, usdc, 100);
        // int24 tickDaiUsdc = orderRouter.getTick(poolDaiUsdc, 1);
        // uint256 expectedDaiUsdc = orderRouter.getQuoteAtTick(tickDaiUsdc, 1*10**18, dai, weth);

        // (
        //     ConveyorLimitOrders.SpotReserve memory priceDaiUsdc,
        //     address poolAddressDaiUsdc
        // ) = orderRouter.calculateV3SpotPrice(
        //         dai,
        //         usdc,
        //          1*10**18,
        //          100,
        //          1,
        //         _uniV3FactoryAddress
        //     );

        // assertEq(priceDaiUsdc.spotPrice, expectedDaiUsdc);
        assertEq(priceDaiWeth.spotPrice, expectedDaiWeth);
        assertEq(priceWethUsdc.spotPrice, expectedWethUsdc);
    }

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
        orderRouter.addDex(_uniV2FactoryAddress, _uniswapV2HexDem, true);
    }

    function testFailAddDex_MsgSenderIsNotOwner() public {
        cheatCodes.prank(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        orderRouter.addDex(_uniV2FactoryAddress, _uniswapV2HexDem, true);
    }

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
