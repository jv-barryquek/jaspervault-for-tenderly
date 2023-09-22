pragma solidity ^0.8.6;

import "openzeppelin-contracts-V4/token/ERC20/IERC20.sol";
import "openzeppelin-contracts-V4/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-V4/utils/math/SafeMath.sol";
import "openzeppelin-contracts-V4/utils/Address.sol";
import "openzeppelin-contracts-V4/access/Ownable.sol";
import {ERC721} from "./erc721.sol";
import {JasperAsset} from "./asset_nft.sol";

contract SendTestToken is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20[] public tokens;

    uint256[] public tokens_amount;
    JasperAsset public nft;

    constructor(
        IERC20[] memory _tokens,
        uint256[] memory _tokens_amount,
        JasperAsset _nft
    ) {
        tokens = _tokens;
        tokens_amount = _tokens_amount;
        nft = _nft;
    }

    function give_me_money(uint256 _tokenId, string calldata _uri) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].approve(address(this), tokens_amount[i]);
            tokens[i].safeTransferFrom(
                address(this),
                address(msg.sender),
                tokens_amount[i]
            );
        }
        nft.mint(msg.sender, _tokenId, _uri);
    }

    function add_token(IERC20 newtoken, uint256 amount) public onlyOwner {
        tokens.push(newtoken);
        tokens_amount.push(amount);
    }
}
