pragma solidity ^0.6.10;

contract GMXVault {
    function getMaxPrice(address _token) external view returns (uint256) {
        return 2;
    }

    function getMinPrice(address _token) external view returns (uint256) {
        return 1;
    }
}
