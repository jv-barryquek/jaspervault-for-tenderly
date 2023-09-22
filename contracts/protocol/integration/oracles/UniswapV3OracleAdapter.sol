//SPDX-License-Identifier: MIT
pragma solidity 0.6.10;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

interface IERC20 {
    function decimals() external view returns (uint256);
}

library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}


contract UniswapV3OracleAdapter {
    using SafeMath for uint256;
    address public  token0;
    address public  token1;
    address public immutable pool;

    uint256 public immutable token0BaseUnit;
    uint256 public immutable token1BaseUnit; 

    uint256 public PRICE_MULTIPLIER = 1e12;
    uint32  public secondsAgo;

   constructor(address _pool,uint32 _secondsAgo) public{
       require(_pool != address(0), "pool doesn't exist");   
       require(_secondsAgo>0, "secondsAgo  has to be greater than 0");   
       pool=_pool;       
       secondsAgo=_secondsAgo;
       token0=IUniswapV3Pool(_pool).token0();
       token1=IUniswapV3Pool(_pool).token1();
        uint256 token0Decimals = IERC20(token0).decimals();
        require(token0Decimals<=18,"decimals has to less than or equal to 18");
        require(token0Decimals>=0,"decimals has to be greater than or equal to 0");
        token0BaseUnit = 10 ** token0Decimals;
        uint256 token1Decimals = IERC20(token1).decimals();
        token1BaseUnit= 10 ** token1Decimals;
        require(token1Decimals<=18,"decimals has to less than or equal to 18");
        require(token1Decimals>=0,"decimals has to be greater than or equal to 0");
        uint256 pow=18-token1Decimals;
        PRICE_MULTIPLIER=10**pow;

   }

    function read() external view returns (uint256) {
        address tokenIn=token0;
        uint128 amountIn=uint128(token0BaseUnit);
        address tokenOut=token1;
        (int24 tick,)=OracleLibrary.consult(pool,secondsAgo);
        uint256 amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            amountIn,
            tokenIn,
            tokenOut
        ); 
        return amountOut.mul(PRICE_MULTIPLIER);
    }
}
