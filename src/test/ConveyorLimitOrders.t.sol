// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../../lib/libraries/PriceLibrary.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract ConveyorLimitOrdersTest is DSTest {
    //Instantiate limit-v0 contract for testing
    ConveyorLimitOrders conveyorLimitOrders;

    //Initialize cheatcodes
    CheatCodes cheatCodes;
    IUniswapV2Router02 _uniV2Router;
    IUniswapV2Factory _uniV2Factory;

    //MAX_UINT for testing
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    //Native token address WETH
    address _wnatoAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
        conveyorLimitOrders = new ConveyorLimitOrders();
        conveyorLimitOrders.addDex(_dexFactories, _hexDems, _isUniV2);
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        _uniV2Router = IUniswapV2Router02(_uniV2Address);
        _uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);

        console.log("here");
    }

    receive() external payable {}

    function testPlaceOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);

        //swap 20 ether for the swap token
        swapEthForToken(20 ether, swapToken);

        ConveyorLimitOrders.Order memory order = newOrder(
            swapToken,
            245000000000000000000,
            5
        );

        placeMockOrder(order);
    }

    function testUpdateOrder() public {
        //swap 20 ether for the swap token
        swapEthForToken(20 ether, swapToken);

        //create a new order
        ConveyorLimitOrders.Order memory order = newOrder(
            swapToken,
            245000000000000000000,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //create a new order to replace the old order
        ConveyorLimitOrders.Order memory updatedOrder = newOrder(
            swapToken,
            245000000000000000000,
            5
        );
        updatedOrder.orderId = orderId;

        //submit the updated order
        conveyorLimitOrders.updateOrder(updatedOrder);
    }

    function testCancelOrder() public {
        //swap 20 ether for the swap token
        swapEthForToken(20 ether, 0x514910771AF9Ca656af840dff83E8264EcF986CA);

        //create a new order
        ConveyorLimitOrders.Order memory order = newOrder(
            swapToken,
            245000000000000000000,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //submit the updated order
        conveyorLimitOrders.cancelOrder(orderId);
    }

    function testCancelAllOrders() public {}

    function testExecuteOrder() public {}

    function testChangeBase() public {
        //----------Test 1 setup----------------------//
        uint256 reserve0 = 131610640170334000000000000;
        uint8 dec0 = 18;
        uint256 reserve1 = 131610640170334;
        uint8 dec1 = 9;
        (uint256 r0_out, uint256 r1_out) = PriceLibrary.convertToCommonBase(
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
        (uint256 r0_out1, uint256 r1_out1) = PriceLibrary.convertToCommonBase(
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

    function testCalculateMinSpot() public view {
        //Test Tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;
        address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

        uint256 price1 = conveyorLimitOrders.calculateMinPairSpotPrice(
            weth,
            usdc
        );
        uint256 price2 = conveyorLimitOrders.calculateMinPairSpotPrice(
            dai,
            usdc
        );
        uint256 price3 = conveyorLimitOrders.calculateMinPairSpotPrice(
            weth,
            dai
        );
        uint256 price4 = conveyorLimitOrders.calculateMinPairSpotPrice(
            weth,
            wax
        );
        uint256 price5 = conveyorLimitOrders.calculateMinPairSpotPrice(
            wbtc,
            weth
        );
        console.logString(
            "--------------Calculate Minimum Spot Price UniV2, Sushi, UniV3-------------------"
        );
        console.logString(
            "--------------Min Spot Price Output-------------------"
        );
        console.logString("--------------WETH-USDC-------------------");
        console.logUint(price1);
        console.logUint(price1);
        console.logString("Right shifted");
        console.logUint(price1 >> 9);
        console.logString("---------USDC-DAI--------------");
        console.logUint(price2);
        console.logString("Right shifted");
        console.logUint(price2 >> 9);
        console.logString("----------Dai-WETH-------------");
        console.logUint(price3);
        console.logString("Right shifted");
        console.logUint(price3 >> 9);
        console.logString("----------WAX-WETH-------------");
        console.logUint(price4);
        console.logString("Right shifted");
        console.logUint(price4 >> 9);
        console.logString("----------WBTC-WETH-------------");
        console.logUint(price5);
        console.logString("Right shifted");
        console.logUint(price5 >> 9);
    }

    function testCalculateMeanSpot() public view {
        //Test Tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;

        uint256 price1 = conveyorLimitOrders.calculateMeanPairSpotPrice(
            weth,
            usdc
        );
        uint256 price2 = conveyorLimitOrders.calculateMeanPairSpotPrice(
            dai,
            usdc
        );
        uint256 price3 = conveyorLimitOrders.calculateMeanPairSpotPrice(
            weth,
            dai
        );
        uint256 price4 = conveyorLimitOrders.calculateMeanPairSpotPrice(
            weth,
            wax
        );
        console.logString(
            "--------------Calculate Mean Spot Price UniV2, Sushi, UniV3-------------------"
        );
        console.logString("--------------Mean Price Out-------------------");
        console.logString("--------------WETH-USDC-------------------");
        console.logUint(price1);
        console.logString("Right shifted");
        console.logUint(price1 >> 9);
        console.logString("---------USDC-DAI--------------");
        console.logUint(price2);
        console.logString("Right shifted");
        console.logUint(price2 >> 9);
        console.logString("----------Dai-USDC-------------");
        console.logUint(price3);
        console.logString("Right shifted");
        console.logUint(price3 >> 9);
        console.logString("----------WAX-WETH-------------");
        console.logUint(price4);
        console.logUint(price4 >> 9);
    }

    function testCalculateV3Spot() public view {
        //Test Tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;

        //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
        uint256 price1 = PriceLibrary.calculateV3SpotPrice(
            weth,
            usdc,
            1000000000000,
            3000,
            _uniV3FactoryAddress
        );
        uint256 price2 = PriceLibrary.calculateV3SpotPrice(
            dai,
            usdc,
            1000000000000,
            3000,
            _uniV3FactoryAddress
        );
        uint256 price3 = PriceLibrary.calculateV3SpotPrice(
            weth,
            dai,
            1,
            3000,
            _uniV3FactoryAddress
        );
        //uint256 price4= PriceLibrary.calculateUniV3SpotPrice(wax,weth, 1, 3000,1, _uniV3FactoryAddress);

        console.logString("---------V3 Tick Range Price Uni----------");
        console.logString("---------USDC-WETH-------------");
        console.logUint(price1);
        console.logString("---------USDC-DAI--------------");
        console.logUint(price2);
        console.logString("----------Dai-WETH-------------");
        console.logUint(price3);
        console.logString("----------WAX-WETH-------------");
        //console.logUint(price4);
    }

    function testCalculateV2SpotSushi() public view {
        //Test tokens
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address wax = 0x7a2Bc711E19ba6aff6cE8246C546E8c4B4944DFD;
        //uint256 priceUSDC= PriceLibrary.calculateUniV3SpotPrice(dai, usdc, 1000000000000, 3000,1, _uniV3FactoryAddress);
        uint256 price1 = PriceLibrary.calculateV2SpotPrice(
            weth,
            usdc,
            _sushiFactoryAddress,
            _sushiHexDem
        );
        uint256 price2 = PriceLibrary.calculateV2SpotPrice(
            dai,
            usdc,
            _sushiFactoryAddress,
            _sushiHexDem
        );
        uint256 price3 = PriceLibrary.calculateV2SpotPrice(
            weth,
            dai,
            _sushiFactoryAddress,
            _sushiHexDem
        );
        uint256 price4 = PriceLibrary.calculateV2SpotPrice(
            weth,
            wax,
            _sushiFactoryAddress,
            _sushiHexDem
        );
        console.logString("---------V2 Spot Price Sushi----------");
        console.logString("---------USDC-WETH-------------");
        console.logUint(price1);
        console.logString("---------USDC-DAI--------------");
        console.logUint(price2);
        console.logString("----------Dai-USDC-------------");
        console.logUint(price3);
        console.logString("----------WAX-WETH-------------");
        console.logUint(price4);
    }

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

    //Test calculateFee()
    function testCalculateOrderFee() public {
        uint128 feePercent1 = conveyorLimitOrders.calculateFee(100000);
        uint128 feePercent2 = conveyorLimitOrders.calculateFee(150000);
        uint128 feePercent3 = conveyorLimitOrders.calculateFee(200000);
        uint128 feePercent4 = conveyorLimitOrders.calculateFee(50);
        uint128 feePercent5 = conveyorLimitOrders.calculateFee(250);

        assertEq(feePercent1, 51363403165874997);
        assertEq(feePercent2, 37664201948990181);
        assertEq(feePercent3, 29060577804403466);
        assertEq(feePercent4, 92211856751802878);
        assertEq(feePercent5, 92124386183756525);
    }

    /// Todo
    function testCalculateOrderReward() public { //1.8446744073709550
        (uint128 rewardConveyor, uint128 rewardBeacon) =conveyorLimitOrders.calculateReward(18446744073709550, 100000);
        console.logString("Input 1 CalculateReward");
        assertEq(39, rewardConveyor);
        assertEq(59, rewardBeacon);
    }

    function testCalculateAlphaX() public {
        uint128 reserve0SnapShot = 47299249002010446421409070433015781392384000000>>64;
        uint128 reserve1SnapShot = 16441701632611160000000000000000000000000000>>64;
        uint128 reserve0Execution =47639531368931384884872445040447549603840000000>>64;
        uint128 reserve1Execution =16324260906687270000000000000000000000000000>>64;

        uint256 alphaX = conveyorLimitOrders.calculateAlphaX(reserve0SnapShot, reserve1SnapShot, reserve0Execution, reserve1Execution);
        console.logString("----------------AlphaX-----------------");
        console.logUint(alphaX);
    }

    function testCalculateMaxBeaconReward() public {
        uint128 reserve0SnapShot = 47299249002010446421409070433015781392384000000>>64;
        uint128 reserve1SnapShot = 16441701632611160000000000000000000000000000>>64;
        uint128 reserve0Execution =47639531368931384884872445040447549603840000000>>64;
        uint128 reserve1Execution =16324260906687270000000000000000000000000000>>64;

        uint256 maxReward = conveyorLimitOrders.calculateMaxBeaconReward(reserve0SnapShot, reserve1SnapShot, reserve0Execution, reserve1Execution, 55340232221128660);
        console.logString("----------------Max Reward-----------------");
        assertEq(55340232215591741967352, maxReward);
    }

    //-----------------------------Gas Optimization Tests----------------------------

    //-----------------------------Helper Functions----------------------------

    function swapEthForToken(uint256 amount, address _swapToken) internal {
        cheatCodes.deal(address(this), amount);

        //set the path
        address[] memory path = new address[](2);
        path[0] = _wnatoAddress;
        path[1] = _swapToken;

        // swap eth for tokens
        _uniV2Router.swapExactETHForTokens{value: amount}(
            1,
            path,
            address(this),
            (2**256 - 1)
        );
    }

    function newOrder(
        address token,
        uint256 price,
        uint256 quantity
    ) internal pure returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            token: token,
            orderId: bytes32(0),
            orderType: OrderBook.OrderType.SELL,
            price: price,
            quantity: quantity
        });
    }

    function placeMockOrder(ConveyorLimitOrders.Order memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        ConveyorLimitOrders.Order[]
            memory orderGroup = new ConveyorLimitOrders.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = conveyorLimitOrders.placeOrder(orderGroup);

        orderId = orderIds[0];
    }
}
