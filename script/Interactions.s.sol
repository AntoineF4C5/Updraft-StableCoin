// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SetUp is Script {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    address public weth;
    address public wbtc;
    address public msgsender;

    function _run() public {
        address recentlyDeployed = DevOpsTools.get_most_recent_deployment("DSCEngine", block.chainid);
        engine = DSCEngine(recentlyDeployed);
        dsc = DecentralizedStableCoin(engine.getDscAddress());
        weth = engine.getCollateralToken(0);
        wbtc = engine.getCollateralToken(1);
        vm.startBroadcast();
        (, msgsender,) = vm.readCallers();
        vm.stopBroadcast();
    }

    function getTokenAddressFromName(string memory token) public view returns (address) {
        if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("weth"))) {
            return weth;
        } else if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("wbtc"))) {
            return wbtc;
        } else {
            revert("Invalid token");
        }
    }
}

contract MintWeth is SetUp {
    function run(uint256 amount) public {
        if (block.chainid == 11155111) {
            revert("Cannot mint WETH on Sepolia");
        }
        _run();
        _giveWeth(amount);
    }

    function _giveWeth(uint256 amount) public {
        vm.startBroadcast();
        ERC20Mock(weth).mint(msgsender, amount);
        vm.stopBroadcast();
    }
}

contract GetWethBalance is SetUp {
    function run() public returns (uint256) {
        _run();
        return IERC20(weth).balanceOf(msgsender);
    }
}

contract DepositCollateral is SetUp {
    function run(string memory token, uint256 amount) public {
        _run();
        address tokenCollateralAddress = getTokenAddressFromName(token);
        _depositCollateral(tokenCollateralAddress, amount);
    }

    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public {
        vm.startBroadcast();
        ERC20Mock(tokenCollateralAddress).approve(address(engine), amountCollateral);
        engine.depositCollateral(tokenCollateralAddress, amountCollateral);
        vm.stopBroadcast();
    }
}

contract RedeemCollateral is SetUp {
    function run(string memory token, uint256 amount) public {
        _run();
        address tokenCollateralAddress = getTokenAddressFromName(token);
        _redeemCollateral(tokenCollateralAddress, amount);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public {
        vm.startBroadcast();
        engine.redeemCollateral(tokenCollateralAddress, amountCollateral);
        vm.stopBroadcast();
    }
}

contract GetCollateral is SetUp {
    function run(string memory token) public returns (uint256) {
        _run();
        address tokenCollateralAddress = getTokenAddressFromName(token);
        return engine.getUserCollateral(msgsender, tokenCollateralAddress);
    }
}

contract Mint is SetUp {
    function run(uint256 amount) public {
        _run();
        _mint(amount);
    }

    function _mint(uint256 amount) public {
        vm.startBroadcast();
        engine.mintDsc(amount);
        vm.stopBroadcast();
    }
}

contract GetMintedDsc is SetUp {
    function run() public returns (uint256) {
        _run();
        return engine.getDscMinted(msgsender);
    }
}

contract Burn is SetUp {
    function run(uint256 amount) public {
        _run();
        _burn(amount);
    }

    function _burn(uint256 amount) public {
        vm.startBroadcast();
        dsc.approve(address(engine), amount);
        engine.burnDsc(amount);
        vm.stopBroadcast();
    }
}

contract GetHealthFactor is SetUp {
    function run() public returns (uint256) {
        _run();
        return engine.getHealthFactor(msgsender);
    }
}
