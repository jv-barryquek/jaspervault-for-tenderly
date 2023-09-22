import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract GMXPositionRouter {
    function createIncreasePosition(
        address[] memory _path,
        address,
        uint256 _amountIn,
        uint256,
        uint256,
        bool,
        uint256,
        uint256,
        bytes32,
        address
    ) public payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.number));

    }

    function createDecreasePosition(
        address[] memory,
        address,
        uint256,
        uint256,
        uint256,
        bool,
        uint256,
        uint256,
        bytes32,
        address
    ) public payable returns (bytes32) {
        return keccak256(abi.encodePacked(block.number));
    }
}
