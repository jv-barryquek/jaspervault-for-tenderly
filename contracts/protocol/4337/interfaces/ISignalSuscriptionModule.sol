// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;


interface ISignalSuscriptionModule {
    function followers(address _setToken) external returns(address[] memory);
    function isFollowMethod(address _setToken) external returns(bool);
    function allowed_Copytrading(address _setToken) external returns(bool);
    function Signal_provider(address _setToken) external returns(address);
    function isFollowing(address _setToken) external returns(bool);
    function setFollowMethod(address _setToken,bool _status) external;
    function warnLine() external returns(uint256);
    function unsubscribeLine() external returns(uint256);
    function subscribe(address _setToken, address target) external;
    function unsubscribe(address _setToken, address target) external;
}

