// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./Libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Srinivas G
 * This system is designed to be as minimal as possible ,nd have th tokens maintain a
 * 1 token==1 peg
 * This stable coin has  properties :
 * Exogenous Collateral
 * Dollar Pegged
 * Algorithmically stable      *
 * It is similar to DAI ,If DAI Has no governance and it is only backed by WETH ,WBTC
 * Our DSC system  should always be overcollateralized .At no point should all the collateral <= all the DSC's minted in the system .
 * @notice This contract is the core of the DSC system and This contract is responsible for minting and redeeming && also for depositing and withdrawing collateral
 *
 * @notice  This contract is very loosely Based on the MakerDAO Dss(DAI) system .
 *
 */

contract DSCEngine is ReentrancyGuard {
    //Erros
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressShouldBeSame();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //Types
    using OracleLib for AggregatorV3Interface;

    //State variables

    uint256 private constant ADDTIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overvollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //10 percent bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
    //events

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    //modifiers
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //USD PriceFeeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressShouldBeSame();
        }
        //
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //External Functions

    /**
     *
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The total amount of the collateral being deposited
     * @param amountDscToMint The total amount of DSC that you wnat to mint
     * @notice This function will deposit collateral and mint dsc in one transaction
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
     * @notice follows checks effects patterns
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposite
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
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
     * @param tokenCollateralAddress The Address of the collateral token to be redeemed
     * @param amountCollateral The amount of collateral to be redeemed
     * @param amountDscToBurn The amount of Dsc to be burned
     * @notice This function burns the dsc and redeems the collateral in one transaction
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);

        //redeem collateral checks the health factor , so we need not to check it again ..
    }

    //inorder to redeem you collateral ,Your health factor must be over one

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _reedemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amountDscToMint the amount of Decentralized stable coin to mint
     * @notice They must have more value than the threshold collateral
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //This system only works if it is always overcollateralized

    /**
     *
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor and his health factor should be less than minimum health factor
     * @param debtToCover The amount of Dsc you want to burn  to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice you will get a liquidation bonus for taking the users funds
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external nonReentrant {
        //need to check the health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //we want to burn the dsc and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 collateralToBeRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
        _reedemCollateral(user, msg.sender, collateral, collateralToBeRedeemed);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor <= endingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    

    ///Private and Internal functions–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

    /**
     * @dev These are low level internal functions , Donot call this this function , unless a function is calling
     * it is checking for health factor is being broken
     *
     */

    function _burnDsc(uint256 amount, address OnBehalfOf, address dscFrom) private {
        s_DSCMinted[OnBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _reedemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * Returns how close to Liquidation the user is ..
     * If the user gets below he gets liquidated
     */

    /**
     *
     * This function returns :
     * 1.Total Amount of Dsc minted by the account user
     * 2.Total value of the user's collateral in USD
     */

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * returns how close to liquidation a user is
     * If a user goes below 1 ,then he will be liquidated
     *
     */

    function _healthFactor(address user) private view returns (uint256) {
        //we need total dsc minted
        //total collateral value

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //  return (collateralValueInUsd/totalDscMinted);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }


    function _revertIfHealthFactorIsBroken(address user) internal view {
        //checking health factor
        //revert if they dont have
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
        function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //Public Functions–––––––––––––––––––––––––––––––––––––----–-–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––


    //This function returns the amount of token in usd; --1 eth <- 2000.000000000000000000
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDTIONAL_FEED_PRECISION);
    }

    //This function returns the total value of collateral in USD
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getUsdValue(token, amount);
        }
        return totalCollateralValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //pricefeed returns avlue with 8 decimals
        //to turn it to 18 we will be multiplying it with the 10 decimals

        return ((uint256(price) * ADDTIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
     function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
      function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDTIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }
}
