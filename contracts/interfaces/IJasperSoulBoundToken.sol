pragma solidity ^0.8.7;

interface IJasperSoulBoundToken {
    function safeMint(address to) external;

    function burn(uint256 tokenId) external;

    function admin() external returns (address);
}
