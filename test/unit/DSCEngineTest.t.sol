// SPDX-License-Identifier: SEE LICENSE IN LICENSE

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");
    uint256 constant AMOUNT_COLLATERAL = 10e18;
    uint256 constant STARTING_BALANCE = 100e18;
    uint256 constant MINT_AMOUNT = 10e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    address[] public tokens;
    address[] public priceFeeds;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokens.push(weth);

        priceFeeds.push(wethUsdPriceFeed);
        priceFeeds.push(wbtcUsdPriceFeed);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedArrraysLengthMismatch.selector);
        new DSCEngine(tokens, priceFeeds, address(dsc));
        vm.stopPrank();
    }

    function testWritesArraysWithTokenAndPriceFeedAddresses() public {
        tokens.push(weth);
        tokens.push(wbtc);
        priceFeeds.push(wethUsdPriceFeed);
        priceFeeds.push(wbtcUsdPriceFeed);
        vm.startPrank(USER);
        new DSCEngine(tokens, priceFeeds, address(dsc));
        vm.stopPrank();

        // First index
        address expectedToken = tokens[0];
        address expectedPriceFeed = priceFeeds[0];
        address actualToken = engine.getCollateralToken(0);
        address actualPriceFeed = engine.getPriceFeedFromToken(actualToken);
        assertEq(expectedToken, actualToken);
        assertEq(expectedPriceFeed, actualPriceFeed);

        // Second index
        expectedToken = tokens[1];
        expectedPriceFeed = priceFeeds[1];
        actualToken = engine.getCollateralToken(1);
        actualPriceFeed = engine.getPriceFeedFromToken(actualToken);
        assertEq(expectedToken, actualToken);
        assertEq(expectedPriceFeed, actualPriceFeed);
    }

    function testSetsDscToCorrectAddress() public {
        tokens.push(weth);
        priceFeeds.push(wethUsdPriceFeed);
        vm.startPrank(USER);
        DSCEngine newEngine = new DSCEngine(tokens, priceFeeds, address(dsc));
        vm.stopPrank();

        address expectedDsc = address(dsc);
        address actualDsc = newEngine.getDscAddress();
        assertEq(expectedDsc, actualDsc);
    }

    /*//////////////////////////////////////////////////////////////
                                GETVALUE
    //////////////////////////////////////////////////////////////*/
    function testGetValue() public view {
        uint256 ethAmount = 15e18;
        // expected value : 15e18 * 2000$ = 30 000e18
        uint256 expectedEthValue = 30000e18;
        uint256 ethValue = engine.getValue(weth, ethAmount);
        assertEq(ethValue, expectedEthValue);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTOKENAMOUNTFROMUSD
    //////////////////////////////////////////////////////////////*/
    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100e18;
        // expected value : 100 / 2000 = 0.05 eth
        uint256 expectedEthAmount = 0.05e18;
        uint256 ethAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(ethAmount, expectedEthAmount);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSITCOLLATERAL
    //////////////////////////////////////////////////////////////*/
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfInvalidTokenAddress() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositUpdatesCollateralBalance() public {
        uint256 initalCollateralBalance = engine.getUserCollateral(USER, weth);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 finalCollateralBalance = engine.getUserCollateral(USER, weth);
        assertEq(initalCollateralBalance + AMOUNT_COLLATERAL, finalCollateralBalance);
    }

    function testTransferFundsFromUserToEngine() public {
        uint256 initialUserBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 initialEngineBalance = ERC20Mock(weth).balanceOf(address(engine));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 finalEngineBalance = ERC20Mock(weth).balanceOf(address(engine));
        assertEq(initialUserBalance - AMOUNT_COLLATERAL, finalUserBalance);
        assertEq(initialEngineBalance + AMOUNT_COLLATERAL, finalEngineBalance);
    }

    function testRevertsIfInsufficientUserBalance() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), STARTING_BALANCE + 1);
        vm.expectRevert();
        engine.depositCollateral(weth, STARTING_BALANCE + 1);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank;
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 totalCollateralInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedTotalCollateralInUsd = engine.getValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(totalCollateralInUsd, expectedTotalCollateralInUsd);
    }

    /*//////////////////////////////////////////////////////////////
                                MINTDSC
    //////////////////////////////////////////////////////////////*/
    function testMintDscRevertsIfDscAmountZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDscUpdatesDscBalance() public depositCollateral {
        uint256 initialDscBalance = engine.getDscMinted(USER);
        vm.startPrank(USER);
        engine.mintDsc(MINT_AMOUNT);
        vm.stopPrank();
        uint256 finalDscBalance = engine.getDscMinted(USER);
        assertEq(finalDscBalance, initialDscBalance + MINT_AMOUNT);
    }

    function testRevertsIfHealthFactorBreaks() public depositCollateral {
        uint256 collateralValueUsd = engine.getAccountCollateralValue(USER);
        // breaks if mintedAmount > collateral / 2
        uint256 mintAmountAboveThreshold = collateralValueUsd / 2 + 1;
        vm.startPrank(USER);
        vm.expectRevert(); // I don't remmeber the exact writing for errors with params
        engine.mintDsc(mintAmountAboveThreshold);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURNDSC
    //////////////////////////////////////////////////////////////*/
    function testBurnDscUpdatesDscBalance() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDsc(MINT_AMOUNT);
        uint256 initialDscBalance = engine.getDscMinted(USER);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT);
        engine.burnDsc(MINT_AMOUNT);
        vm.stopPrank();
        uint256 finalDscBalance = engine.getDscMinted(USER);
        assertEq(finalDscBalance, initialDscBalance - MINT_AMOUNT);
    }

    function testBurnDscRevertsIfDscAmountZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfInsufficientDscBalance() public depositCollateral {
        vm.startPrank(USER);
        engine.mintDsc(MINT_AMOUNT);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT + 1);
        vm.expectRevert();
        engine.burnDsc(MINT_AMOUNT + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEMCOLLATERAL
    //////////////////////////////////////////////////////////////*/
    function testRedeemUpdatesCollateralBalance() public depositCollateral {
        uint256 initialCollateralBalance = engine.getUserCollateral(USER, weth);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 finalCollateralBalance = engine.getUserCollateral(USER, weth);
        assertEq(initialCollateralBalance - AMOUNT_COLLATERAL, finalCollateralBalance);
    }

    function testRedeemGivesCollateralToUser() public depositCollateral {
        uint256 initialUserBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 initialEngineBalance = ERC20Mock(weth).balanceOf(address(engine));
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 finalUserBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 finalEngineBalance = ERC20Mock(weth).balanceOf(address(engine));
        assertEq(initialUserBalance + AMOUNT_COLLATERAL, finalUserBalance);
        assertEq(initialEngineBalance - AMOUNT_COLLATERAL, finalEngineBalance);
    }

    /*//////////////////////////////////////////////////////////////
                      DEPOSITCOLLATERALANDMINTDSC
    //////////////////////////////////////////////////////////////*/
    function testDepositAndMintRevertsIfInvalidCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ranToken.approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateralAndMintDsc(address(ranToken), AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testDepositAndMintDepositsCollateral() public {
        uint256 initialCollateralBalance = engine.getUserCollateral(USER, weth);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        uint256 finalCollateralBalance = engine.getUserCollateral(USER, weth);
        assertEq(initialCollateralBalance + AMOUNT_COLLATERAL, finalCollateralBalance);
    }

    function testDepositAndMintMintsDsc() public {
        uint256 initialDscBalance = engine.getDscMinted(USER);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        uint256 finalDscBalance = engine.getDscMinted(USER);
        assertEq(initialDscBalance + MINT_AMOUNT, finalDscBalance);
    }

    /*//////////////////////////////////////////////////////////////
                         REDEEMCOLLATERALFORDSC
    //////////////////////////////////////////////////////////////*/
    function testRedeemCollateralForDscRevertsIfInvalidCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        ranToken.approve(address(engine), AMOUNT_COLLATERAL);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.redeemCollateralForDsc(address(ranToken), AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               LIQUIDATE
    //////////////////////////////////////////////////////////////*/
    modifier userDepositAndMintMaximumDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 collateralValueUsd = engine.getValue(address(weth), AMOUNT_COLLATERAL);
        // breaks if mintedAmount > collateral / 2
        uint256 maxMintPossible = collateralValueUsd / 2;
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, maxMintPossible);
        vm.stopPrank;
        _;
    }

    modifier lowerCollateralValue() {
        (, int256 initialAnswer,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        int256 newAnswer = initialAnswer * 3 / 4;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newAnswer);
        _;
    }

    function testLiquidateRevertsIfUserIsHealthy() public userDepositAndMintMaximumDsc {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__UserHealthFactorOk.selector);
        engine.liquidate(address(weth), USER, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testLiquidateUpdatesBalancesAndSendsCollateral()
        public
        userDepositAndMintMaximumDsc
        lowerCollateralValue
    {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        uint256 initialUserCollateral = engine.getUserCollateral(USER, weth);
        uint256 initialLiquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 initialUserDscMinted = engine.getDscMinted(USER);
        uint256 initialLiquidatorDscBalance = ERC20Mock(address(dsc)).balanceOf(LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT);
        engine.liquidate(address(weth), USER, MINT_AMOUNT);
        vm.stopPrank();
        uint256 finalUserCollateral = engine.getUserCollateral(USER, weth);
        uint256 finalLiquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 finalUserDscMinted = engine.getDscMinted(USER);
        uint256 finalLiquidatorDscBalance = ERC20Mock(address(dsc)).balanceOf(LIQUIDATOR);

        assert(finalUserCollateral < initialUserCollateral);
        assert(finalLiquidatorWethBalance > initialLiquidatorWethBalance);
        assertEq(finalUserDscMinted, initialUserDscMinted - MINT_AMOUNT);
        assertEq(finalLiquidatorDscBalance, initialLiquidatorDscBalance - MINT_AMOUNT);
    }

    function testLiquidateRevertsIfLiquidatorDoesNotHaveEnoughDsc()
        public
        userDepositAndMintMaximumDsc
        lowerCollateralValue
    {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(address(dsc)).approve(address(engine), MINT_AMOUNT);
        vm.expectRevert();
        engine.liquidate(address(weth), USER, MINT_AMOUNT);
        vm.stopPrank();
    }
}
