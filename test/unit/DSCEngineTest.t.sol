//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;
import {Test,console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer ;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config ;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 15 ether ;
    // uint256 public constant AMOUNT_DSC = 10000;
    


    function setUp () public {
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,) =config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
       


    }


    //constructor tests
    address[] tokenAddresses;
    address[] priceFeedAddresses;
    function testRevertsIfTokenLengthDoesnotMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressShouldBeSame.selector);
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));


    }


    ///PriceFeed value 
    function testGetUsdValue() public {
        uint256 ethAmount = 1  ;
        uint256 expectedUsd = 2000;
        uint256 actualUsdValue = dsce.getUsdValue(weth,ethAmount);
        console.log(expectedUsd);
        console.log(actualUsdValue);
        assertEq(expectedUsd,actualUsdValue);


    }

    function testGetTokenAmountInUsd() public {
        uint256 usdAmount = 100 ether ;
        uint256 expectedEth = 0.05 ether;

        uint256 actualEther = dsce.getTokenAmountFromUsd(weth,usdAmount);
        assertEq(expectedEth,actualEther);



    }

    //DepositCollateralTests
    function testRevertsIfCollateralZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);


        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();
    }
    function testRevertsIfUnapprovedCollateral() public {
       
        ERC20Mock ranToken = new ERC20Mock("RAN","RAN",USER,AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
      
        dsce.depositCollateral(address(ranToken),AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth,AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
        
    }
    modifier depositedCollateralAndMintedDsc(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth,AMOUNT_COLLATERAL,10000e18);
        _;
    }
    modifier depositedCollateralAndMintedDscMax(){
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce),15 ether);
        dsce.depositCollateralAndMintDsc(weth,15 ether,1000e18);
        _;
    }


    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted ,uint256 collateralValueInUsd ) = dsce.getAccountInformation(USER);
        
        uint256 expectedTotalDscMinted = 0;
        //10* 2000.000000000000000000 =20000 
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);
        
        assertEq(expectedTotalDscMinted,totalDscMinted);
        assertEq(AMOUNT_COLLATERAL,expectedDepositedAmount);


    }
    function testDepositCollateralAndMintDsc() public depositedCollateralAndMintedDsc{
        (uint256 totalDscMinted ,uint256 totalCollateralAmountInUsd ) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 10000e18;
        // console.log(totalDscMinted);
        //20,000.000000000000000000
        // console.log(totalCollateralAmountInUsd);
        uint256 actualCollateralAmount = dsce.getTokenAmountFromUsd(weth,totalCollateralAmountInUsd);
        assertEq(expectedTotalDscMinted,totalDscMinted);
        assertEq(AMOUNT_COLLATERAL,actualCollateralAmount);

    }
    function testBurnsDsc() public depositedCollateralAndMintedDsc{
        uint256 dscToBurn = 1000e18;
        
        vm.startPrank(USER);
        ERC20(dsc).approve(address(dsce), dscToBurn);
        dsce.burnDsc(dscToBurn);
        vm.stopPrank();
        (uint256 totalDscMinted , ) = dsce.getAccountInformation(USER);
        uint256 expectedDscMinted = 9000e18;
        assertEq(expectedDscMinted,totalDscMinted);
    }

    // function testRevertsIfBurnAmountExceedsBalance() public depositedCollateralAndMintedDsc{
    //     uint256 dscToBurn = 10001;
    //     ERC20(dsc).approve(address(dsce), dscToBurn);
    //     vm.expectRevert(DSCEngine.DSCEngine__BurnAmountExceedsBalance.selector);
    //     dsce.burnDsc(dscToBurn);
    // }
    function testToRedeemCollateral() public depositedCollateralAndMintedDscMax{

        uint256 collateralToRedeem = 1 ether;
        vm.startPrank(USER);
        dsce.redeemCollateral(weth,collateralToRedeem);
        vm.stopPrank();
        (uint256 totalDscMinted ,uint256 totalCollateralAmountInUsd ) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 1000e18; 
        uint256 expectedCollateralAmount = 15 ether - collateralToRedeem;
        uint256 expectedCollateralAmountInUsd = dsce.getUsdValue(weth,expectedCollateralAmount);
        assertEq(expectedTotalDscMinted,totalDscMinted);
        assertEq(expectedCollateralAmountInUsd,totalCollateralAmountInUsd);


    }
    function testRevertsIfhealthFactorIsBroken()public depositedCollateralAndMintedDsc{
        uint256 health = dsce.getHealthFactor();
        // uint256 ex  = 1;
        console.log(health);
        uint256 collateralToRedeem = 1 ether;
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth,collateralToRedeem);
        vm.stopPrank();
         

    }
    function testMintDsc() public depositedCollateral{
        uint256 dscToMint = 100e18;

        vm.startPrank(USER);
        dsce.mintDsc(100e18);
        vm.stopPrank();
        (uint256 totalDscMinted , ) = dsce.getAccountInformation(USER);
        assertEq(dscToMint,totalDscMinted);

        
    }
    function testRevertsIfHealthFactorIsOk() public depositedCollateralAndMintedDsc{
        vm.startPrank(USER2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth,USER,10000e18);
        vm.stopPrank();
        
    }
    function testGetAccountCollateralValue() public  depositedCollateral{
        
        uint256 totalCollateralValue = dsce.getAccountCollateralValue(USER);
        uint expectedCollateral = dsce.getUsdValue(weth,AMOUNT_COLLATERAL);
        assertEq(totalCollateralValue,expectedCollateral);


    }
    function testHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 1e18;
        vm.startPrank(USER);
        uint256 actualHealthFactor =  dsce.getHealthFactor();
        vm.stopPrank();
        assertEq(expectedHealthFactor,actualHealthFactor);

    }
        function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

       function testGetDsc() public {
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }
    function testGetPrecision() public {
        uint256 expectedPrecision  = 1e18;
        uint256 actualPrecision = dsce.getPrecision();
        assertEq(expectedPrecision,actualPrecision);
    }


   


}   