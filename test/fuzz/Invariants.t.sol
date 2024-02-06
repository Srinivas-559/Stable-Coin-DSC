//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";



contract Invariants is StdInvariant,Test{
    DeployDSC deployer ;
    DSCEngine dsce;
    HelperConfig config ;
    DecentralizedStableCoin dsc;
    Handler handler ;
    address weth;
    address wbtc;    

    function setUp () external {
        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (,,weth,wbtc,)= config.activeNetworkConfig();
        handler = new Handler(dsce,dsc);
        targetContract(address(handler));
    }
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {

        //get the value of all the collateral in the protocol 
        //compare it to the all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 wethValue = dsce.getUsdValue(weth,totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc,totalWbtcDeposited);
        

        assert(wethValue+wbtcValue >= totalSupply);
        console.log("totalSupply",totalSupply);
        console.log("totalWethDeposited",totalWethDeposited);
        console.log("totalWbtcDeposited",totalWbtcDeposited);

    }
    function invariant_gettersShouldNotRevert() public view {
        dsce.getLiquidationBonus();
        dsce.getPrecision();


    }



  
}