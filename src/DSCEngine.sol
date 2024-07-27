// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Antoine Douchet
 * This system is designed to maintain the DecentralizedStableCoin at its peg of 1 USD.
 * It is similar to DAI, if it had no governance and was only backed by wETH and wBTC
 *
 * @notice This contract is the core system of the DSC system, it handles the logic for minting and burning DSC tokens, depositing and withdrawing collateral
 * @notice This contract is based on the MakerDao DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedArrraysLengthMismatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__UserHealthFactorIsTooLow(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__UserHealthFactorOk();
    error DSCEngine__UserHealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                             STATEVARIABLES
    //////////////////////////////////////////////////////////////*/

    address[] private s_collateralTokens;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_dscMinted;

    DecentralizedStableCoin private i_dsc;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMAL_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant DEFAULT_HEALTH_FACTOR = 1000e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier tokenAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndPriceFeedArrraysLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * In one step, deposits the user's selected collateral and mints wanted amount of Decentralized StableCoin
     * @param tokenCollateralAddress the address of the token to be deposited as collateral
     * @param amountCollateral the amount of the token to be deposited as collateral
     * @param amountDscToMint the amount of Decentralized StableCoin to be minted
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     *
     * @param tokenCollateralAddress address of the token to be deposited as collateral
     * @param amountCollateral amount of the token to be deposited as collateral
     * @notice the token must be part of the allowed list of tokens
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        tokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress the address of the token to be redeemed
     * @param amountCollateral the amount of the token to be redeemed
     * @param amountDscToBurn the amount of Decentralized StableCoin to be burned
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        tokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountDscToMint amount of Decentralized StableCoin to be minted
     * @notice the amount of DSC to be minted must be lower than the threshold based on value of the collateral deposited
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender); // just in case
    }

    /**
     * Liquidates an undercollateralized user by burning DSC to improve their health factor, and recovering their collateral
     * @param tokenCollateralAddress the token to recover from the undercollateralized user
     * @param user the undercollateralized user to be liquidated
     * @param debtToCover the amount of DSC to be burnt to improve the user's health factor
     * @notice the user's health factor must be lower than MINIMAL_HEALTH_FACTOR for the liquidation to be possible
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        tokenAllowed(tokenCollateralAddress)
        nonReentrant
    {
        uint256 userInitialHealthFactor = _healthFactor(user);
        if (userInitialHealthFactor >= MINIMAL_HEALTH_FACTOR) {
            revert DSCEngine__UserHealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        uint256 bonusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);
        _burnDsc(user, msg.sender, debtToCover);
        uint256 userFinalHealthFactor = _healthFactor(user);
        if (userFinalHealthFactor <= userInitialHealthFactor) {
            revert DSCEngine__UserHealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _burnDsc(address onBehalfOf, address from, uint256 amount) private {
        s_dscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(from, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     *
     * @param user the user to check the health factor of
     * @notice returns how close to liquidation the user is, if the health factor is below 1, the user can be liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return DEFAULT_HEALTH_FACTOR;
        }
        uint256 totalCollateralAdjustedToThreshold =
            totalCollateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return totalCollateralAdjustedToThreshold * PRECISION / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMAL_HEALTH_FACTOR) {
            revert DSCEngine__UserHealthFactorIsTooLow(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalValue) {
        totalValue = 0; // seems to not be necessary
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValue += getValue(token, amount);
        }
        return totalValue;
    }

    function getValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation(address user) public view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getCollateralToken(uint256 index) public view returns (address) {
        return s_collateralTokens[index];
    }

    function getPriceFeedFromToken(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getUserCollateral(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getDscMinted(address user) public view returns (uint256) {
        return s_dscMinted[user];
    }

    function getDscAddress() public view returns (address) {
        return address(i_dsc);
    }
}
