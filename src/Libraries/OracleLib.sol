//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Srinivas
 * @notice used to check the chainlink Oracle for  stale data 
 * If a price is stale he function will revert and render the DSCEngine unusable - this is by design 
 * We want the DSEEngine to freeze if the  price become stale
 * 
 * 
 * If the network explodes d you have a lot of money loced inthe protocol...
 */


library OracleLib{
    error OracleLibStalePrice();

    uint256 private constant TIME_OUT = 3 hours;
    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns (uint80,int256,uint256,uint256,uint80){
        (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )= priceFeed.latestRoundData();


    uint256 secondsSince = block.timestamp - updatedAt;
    if(secondsSince > TIME_OUT){
        revert OracleLibStalePrice();
        
    }
    return (roundId,answer,startedAt,updatedAt,answeredInRound);





    }

}