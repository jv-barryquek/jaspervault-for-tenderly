pragma solidity ^0.6.10;

import "../IGMXRouter.sol";

contract GMXRouter is IGMXRouter {
    function approvePlugin(address) external override {}

    function approvedPlugins(
        address,
        address
    ) external view override returns (bool) {
        return true;
    }

    function PluginTransferFrom(
        address token,
        address from,
        address receiver,
        uint256 amount
    ) public {
        //        IERC20(token).transferFrom(from, receiver, amount);
    }

    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external override {}

    function swapTokensToETH(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external override {}

    function swapETHToTokens(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) external payable override {}
}
