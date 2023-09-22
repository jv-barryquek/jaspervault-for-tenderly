pragma solidity ^0.6.0;

import "./ERC20.sol";

contract MyERC20 is ERC20 {
    uint initialSupply = 10000 * 10 ** 18;

    constructor() public ERC20("MyERC20", "MyERC20") {
        _mint(msg.sender, initialSupply);
    }
}
