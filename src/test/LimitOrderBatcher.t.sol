// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../OrderBook.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderBatcher.sol";
import "../TokenToTokenLimitOrderExecution.sol";
import "../TokenToWethLimitOrderExecution.sol";
import "../TaxedTokenToTokenExecution.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract LimitOrderBatcherTest is DSTest {
    //Initialize limit-v0 contract for testing
    LimitOrderRouter limitOrderRouter;
    ExecutionWrapper limitOrderBatcher;
    //Initialize execution contracts
    TokenToTokenExecution tokenToTokenExecution;
    TaxedTokenToTokenExecution taxedTokenExecution;
    TokenToWethExecution tokenToWethExecution;

    OrderRouter orderRouter;
    //Initialize OrderBook
    OrderBook orderBook;

    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address TAXED_TOKEN = 0xE7eaec9Bca79d537539C00C58Ae93117fB7280b9; //
    address TAXED_TOKEN_1 = 0xe0a189C975e4928222978A74517442239a0b86ff; //
    address TAXED_TOKEN_2 = 0xd99793A840cB0606456916d1CF5eA199ED93Bf97; //6% tax CHAOS token 27
    address TAXED_TOKEN_3 = 0xcFEB09C3c5F0f78aD72166D55f9e6E9A60e96eEC;
    
    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    // bytes32 _sushiHexDem =
    //     hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [
        _uniswapV2HexDem,
        // _sushiHexDem,
        bytes32(0)
    ];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        // _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [
        true,
        //  true,
        false
    ];

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //0.00001
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        limitOrderBatcher = new ExecutionWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
        );
        
    }

    receive() external payable {}

    //================================================================
    //======================= Order Simulation Unit Tests ============
    //================================================================
    function testFindBestTokenToTokenExecutionPrice() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;

        OrderRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000000,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        OrderRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice1 = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000001,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        OrderRouter.TokenToTokenExecutionPrice[]
            memory executionPrices = new OrderRouter.TokenToTokenExecutionPrice[](
                2
            );
        executionPrices[0] = tokenToTokenExecutionPrice;
        executionPrices[1] = tokenToTokenExecutionPrice1;

        uint256 bestPriceIndexBuy = limitOrderBatcher
            .findBestTokenToTokenExecutionPrice(executionPrices, true);
        uint256 bestPriceIndexSell = limitOrderBatcher
            .findBestTokenToTokenExecutionPrice(executionPrices, false);

        assertEq(bestPriceIndexBuy, 0);
        assertEq(bestPriceIndexSell, 1);
    }

    ///@notice Simulate AToBPrice Change V2 reserve tests
    function testSimulateAToBPriceChangeV2ReserveOutputs(uint112 _amountIn)
        public
    {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (, uint128 reserveA, uint128 reserveB, ) = limitOrderBatcher
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateNewReserves.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory outputReserveB = scriptRunner.runPythonScript(
                    path,
                    args
                );
                uint256 expectedReserveB = bytesToUint(outputReserveB);

                uint256 expectedReserveA = reserveAIn + _amountIn;

                assertEq(reserveA, expectedReserveA);

                //Adjust precision as python script has lower precision than ConveyorMath library
                assertEq(reserveB / 10**9, expectedReserveB / 10**9);
            }
        }
    }

    ///@notice Simulate AToB price change v2 spot price test
    function testSimulateAToBPriceChangeV2SpotPrice(uint112 _amountIn) public {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (uint256 spotPrice, , , ) = limitOrderBatcher
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateSpotPriceChange.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory spotOut = scriptRunner.runPythonScript(path, args);
                uint256 spotPriceExpected = bytesToUint(spotOut);
                //Adjust precision since python script is lower precision, 128.128 >>75 still leaves 53 bits of precision decimals and 128 bits of precision integers
                assertEq(spotPrice >> 75, spotPriceExpected >> 75);
            }
        }
    }

    //Block # 15233771
    // function testSimulateAToBPriceChangeV3() public {
    //     address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    //     uint128 alphaX = 5000000000000000000000;

    //     (uint256 spotPrice, , , uint128 amountOut) = limitOrderRouter
    //         .simulateAToBPriceChange(alphaX, 0, 0, poolAddress, true);

    //     assertEq(spotPrice, 179570008050006124574493135473737728);
    //     assertEq(amountOut, 2630889035305553500);
    // }

    //Block # 15233771
    //Test simulate weth to b price change V3 test

    // function testSimulateWethToBPriceChangeV3() public {
    //     uint8[] memory decimals = new uint8[](2);
    //     decimals[0] = 18;
    //     decimals[1] = 18;
    //     //Weth/Uni
    //     OrderRouter.TokenToTokenExecutionPrice
    //         memory tokenToTokenExecutionPrice = OrderRouter
    //             .TokenToTokenExecutionPrice({
    //                 aToWethReserve0: 0,
    //                 aToWethReserve1: 0,
    //                 wethToBReserve0: 0,
    //                 wethToBReserve1: 0,
    //                 price: 0,
    //                 lpAddressAToWeth: address(0),
    //                 lpAddressWethToB: 0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801
    //             });

    //     (uint256 newSpotPriceB, , ) = limitOrderRouter
    //         .simulateWethToBPriceChange(
    //             5000000000000000000000,
    //             tokenToTokenExecutionPrice
    //         );
    //     assertEq(38416481291436668068511433527512398823424, newSpotPriceB);
    // }

    //Block # 15233771

    ///@notice Simulate AToWeth Price change V3 test

    // function testSimulateAToWethPriceChangeV3() public {
    //     uint8[] memory decimals = new uint8[](2);
    //     decimals[0] = 18;
    //     decimals[1] = 18;
    //     //Weth/Uni
    //     OrderRouter.TokenToTokenExecutionPrice
    //         memory tokenToTokenExecutionPrice = OrderRouter
    //             .TokenToTokenExecutionPrice({
    //                 aToWethReserve0: 0,
    //                 aToWethReserve1: 0,
    //                 wethToBReserve0: 0,
    //                 wethToBReserve1: 0,
    //                 price: 0,
    //                 lpAddressAToWeth: 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8,
    //                 lpAddressWethToB: address(0)
    //             });

    //     (uint256 newSpotPriceA, , , uint128 amountOut) = limitOrderRouter
    //         .simulateAToWethPriceChange(
    //             5000000000000000000000,
    //             tokenToTokenExecutionPrice
    //         );

    //     assertEq(newSpotPriceA, 179260530996058765835863903453577216);
    //     assertEq(amountOut, 2626349041956157673);

    // }

    //Block # 15233771
    ///@notice Simulate WethToB price change v2 test
    function testSimulateWethToBPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        OrderRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceB, , ) = limitOrderBatcher
            .simulateWethToBPriceChange(
                5000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceB, 63714967732803596813954797656252367241216);
    }

    //Block # 15233771
    ///@notice Simulate AToWeth price change V2 test
    function testSimulateAToWethPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        OrderRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = OrderRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceA, , , uint128 amountOut) = limitOrderBatcher
            .simulateAToWethPriceChange(
                50000000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceA, 192714735056741134836410079523110912);
        assertEq(amountOut, 28408586008574759898);
    }

    ///@notice Helper function to convert string to int for ffi tests
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

    ///@notice Helper to convert bytes to uint for ffi tests
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

    function placeMockOrder(OrderBook.Order memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        OrderBook.Order[]
            memory orderGroup = new OrderBook.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeOrder(orderGroup);

        orderId = orderIds[0];
    }

    function placeMultipleMockOrder(
        OrderBook.Order[] memory orderGroup
    ) internal returns (bytes32[] memory) {
        //place order
        bytes32[] memory orderIds = orderBook.placeOrder(orderGroup);

        return orderIds;
    }

    function depositGasCreditsForMockOrders(uint256 _amount) public {
        (bool depositSuccess, ) = address(limitOrderRouter).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    function placeNewMockTokenToWethBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000001, //5001 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000002, //5002 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1000000000000000000,
            5000000000000000000003, //5003 DAI
            3000,
            3000,
            0,
            MAX_U32
        );
        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, TAXED_TOKEN);

        OrderBook.Order memory order1 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order4 = newMockOrder(
            TAXED_TOKEN,
            WETH,
            1,
            false,
            true,
            4000,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](4);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_InvalidBatchOrdering()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000003, //5003 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        bytes32[] memory mockOrderOrderIds = placeMultipleMockOrder(orderBatch);
        //place incongruent token order
        bytes32 mockOrderId = placeMockOrder(order3);

        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = mockOrderOrderIds[0];
        orderIds[1] = mockOrderOrderIds[1];
        orderIds[2] = mockOrderId;

        return orderIds;
    }

    function newMockTokenToWethBatch_IncongruentTokenIn()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, UNI);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTaxedTokenInBatch()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            true,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentTokenOut()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            USDC,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToWethBatch_IncongruentBuySellStatus()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            1,
            true,
            false,
            0,
            1,
            5000000000000000000001, //5001 DAI
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000002, //5002 DAI
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }

    function placeNewMockWethToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order3 = newMockOrder(
            WETH,
            DAI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 WETH
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockWethToTaxedBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000000, //2,000,000
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order memory order1 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000001, //2,000,001
            3000,
            0,
            0,
            MAX_U32
        );
        OrderBook.Order memory order2 = newMockOrder(
            WETH,
            TAXED_TOKEN,
            1,
            false,
            true,
            0,
            1,
            20000000000000002, //2,000,002
            3000,
            0,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTokenToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(10000 ether, USDC);

        OrderBook.Order memory order1 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order3 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order4 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 USDC
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order5 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order6 = newMockOrder(
            USDC,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](6);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        orderBatch[4] = order5;
        orderBatch[5] = order6;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTaxedToTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order1 = newMockOrder(
            TAXED_TOKEN,
            DAI,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,001
            3000,
            3000,
            0,
            MAX_U32
        );

        //    OrderBook.Order memory order2 = newMockOrder(
        //         TAXED_TOKEN_3,
        //         DAI,
        //         1,
        //         false,
        //         true,
        //         9000,
        //         1,
        //         2000000000000000000000000, //2,000,002
        //         3000,
        //         3000,
        //         0,
        //         MAX_U32
        //     );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](2);
        orderBatch[0] = order;
        orderBatch[1] = order1;
        // orderBatch[2] = order2;

        return placeMultipleMockOrder(orderBatch);
    }

    function placeNewMockTaxedToTaxedTokenBatch()
        internal
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order = newMockOrder(
            TAXED_TOKEN,
            TAXED_TOKEN_1,
            1,
            false,
            true,
            9000,
            1,
            2000000000000000000000, //2,000,000
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](1);
        orderBatch[0] = order;

        return placeMultipleMockOrder(orderBatch);
    }

    function newMockTokenToTokenBatch()
        internal
        returns (OrderBook.Order[] memory)
    {
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);

        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            UNI,
            1,
            false,
            false,
            0,
            1,
            5000000000000000000000, //5000 DAI
            3000,
            3000,
            0,
            MAX_U32
        );

        OrderBook.Order[]
            memory orderBatch = new OrderBook.Order[](3);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;

        return orderBatch;
    }
}



contract ExecutionWrapper is LimitOrderBatcher {
    constructor(
        address _weth,
        address _quoterAddress
    )
        LimitOrderBatcher(
            _weth,
            _quoterAddress
        )
    {}


    function simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB,
        address pool,
        bool isTokenToWeth
    )
        public
        returns (
            uint256,
            uint128,
            uint128,
            uint128
        )
    {
        return
            _simulateAToBPriceChange(
                alphaX,
                reserveA,
                reserveB,
                pool,
                isTokenToWeth
            );
    }

    function simulateAToWethPriceChange(
        uint128 alphaX,
        OrderRouter.TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        )
    {
        return _simulateAToWethPriceChange(alphaX, executionPrice);
    }

    function findBestTokenToTokenExecutionPrice(
         OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices,
        bool buyOrder
    ) public returns (uint256 bestPriceIndex) {
        return _findBestTokenToTokenExecutionPrice(executionPrices, buyOrder);
    }

    function simulateWethToBPriceChange(
        uint128 alphaX,
         OrderRouter.TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        )
    {
        return _simulateWethToBPriceChange(alphaX, executionPrice);
    }
}