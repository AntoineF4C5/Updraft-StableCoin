// SPDX-License-Identifier: SEE LICENSE IN LICENSE

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    MockV3Aggregator wethPriceFeed;
    MockV3Aggregator wbtcPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled = 0;
    address[] public usersWithCollateral;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        weth = ERC20Mock(engine.getCollateralToken(0));
        wbtc = ERC20Mock(engine.getCollateralToken(1));

        wethPriceFeed = MockV3Aggregator(engine.getPriceFeedFromToken(address(weth)));
        wbtcPriceFeed = MockV3Aggregator(engine.getPriceFeedFromToken(address(wbtc)));
    }

    // this breaks the invariant (not resistant to high price fluctuations)
    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     MockV3Aggregator priceFeed = getPriceFeedFromSeed(collateralSeed);
    //     priceFeed.updateAnswer(newPriceInt);
    // }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amount);
        collateralToken.approve(address(engine), amount);

        engine.depositCollateral(address(collateralToken), amount);
        vm.stopPrank();
        usersWithCollateral.push(msg.sender); // might have duplicates, we dont care
    }

    function mintDsc(uint256 addressSeed, uint256 amount) public {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];
        (uint256 totalDscMinted, uint256 totalCollateralValueUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = int256(totalCollateralValueUsd) / 2 - int256(totalDscMinted);
        if ((maxDscToMint <= 0)) {
            return;
        }
        amount = bound(amount, 1, uint256(maxDscToMint));
        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 collateralDeposited = engine.getUserCollateral(msg.sender, address(collateralToken));
        uint256 collateralValueUsd = engine.getValue(address(collateralToken), collateralDeposited);
        uint256 dscMinted = engine.getDscMinted(msg.sender);
        if (collateralValueUsd <= dscMinted * 2) {
            return;
        }
        uint256 maxValueToRedeem = collateralValueUsd - dscMinted * 2;
        uint256 maxCollateralToRedeem = engine.getTokenAmountFromUsd(address(collateralToken), maxValueToRedeem);
        if (maxCollateralToRedeem == 0) {
            return;
        }
        amount = bound(amount, 1, maxCollateralToRedeem);

        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateralToken), amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function getPriceFeedFromSeed(uint256 seed) private view returns (MockV3Aggregator) {
        if (seed % 2 == 0) {
            return wethPriceFeed;
        } else {
            return wbtcPriceFeed;
        }
    }
}
