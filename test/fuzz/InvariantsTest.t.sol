// SPDX-License-Identifier: SEE LICENSE IN LICENSE

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    Handler handler;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc) = config.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 totalWethStored = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcStored = IERC20(wbtc).balanceOf(address(engine));

        uint256 totalWethValue = engine.getValue(weth, totalWethStored);
        uint256 totalWbtcValue = engine.getValue(wbtc, totalWbtcStored);

        console.log("totalWethValue: ", totalWethValue);
        console.log("totalWbtcValue: ", totalWbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("Times mint is called : ", handler.timesMintIsCalled());
        assert(totalWethValue + totalWbtcValue >= totalSupply);
    }
}
