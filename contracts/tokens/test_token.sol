pragma solidity ^0.8.0;

import "openzeppelin-contracts-V4/access/Ownable.sol";
import "openzeppelin-contracts-V4/token/ERC20/extensions/ERC20Capped.sol";
import "openzeppelin-contracts-V4/token/ERC20/extensions/ERC20Burnable.sol";

contract TestToken is ERC20Capped, ERC20Burnable, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 cap,
        address initAccount,
        uint256 initialBalance
    ) ERC20(name, symbol) ERC20Capped(cap) {
        ERC20._mint(initAccount, initialBalance);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function _mint(address account, uint256 amount)
        internal
        override(ERC20, ERC20Capped)
        onlyOwner
    {
        super._mint(account, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
    }
}
