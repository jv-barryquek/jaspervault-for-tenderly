/*
    Copyright 2021 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import {ISavingsDai} from "../../../interfaces/external/spark/ISavingsDai.sol";

/**
 * @title SDAIWrapV2Adapter
 * @author JasperVault
 *
 * @notice Wrap adapter for Spark that returns data for wraps/unwraps of DAI tokens for sDAI tokens
 */
contract SDAIWrapV2Adapter {
    // ! note: I've removed the `_onlyValidTokenPair` modifier which is in some other WrapV2Adapters (e.g. AaveV3, Spark) here. If we want to restrict the wrapping to only DAI to sDAI, we could pass in the token contract addresses at construction and set them as state variables. However, that might make our adapter inflexible e.g., if the token contract addresses change in the case of an upgrade. Whether or not to implement this should be discussed.

    /* ========== State Variables ========= */

    // Address of the sDAI token contract where you can wrap DAI for sDAI
    ISavingsDai public sDaiTokenContract;

    /* ============ Constructor ============ */

    constructor(ISavingsDai _sDaiContract) public {
        sDaiTokenContract = _sDaiContract;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Generates the calldata to wrap an underlying asset into a wrappedToken.
     *
     * @param _underlyingUnits      Total quantity of underlying units to wrap
     * @param _to                   Address to send the wrapped tokens to
     *
     * @return address              Target contract address
     * @return uint256              Total quantity of underlying units (if underlying is ETH)
     * @return bytes                Wrap calldata
     */
    function getWrapCallData(
        address /*  _underlyingToken */,
        address /*  _wrappedToken */,
        uint256 _underlyingUnits,
        address _to,
        bytes memory _wrapData
    ) external view returns (address, uint256, bytes memory) {
        uint256 coinType = abi.decode(_wrapData, (uint256));
        // see comments in IJasperVault.sol's ComponentPosition and ExternalPosition structs to understand what the coinType is
        require(coinType == 4, "wrappedToken is not sToken");
        bytes memory callData = abi.encodeWithSignature(
            "deposit(uint256,address)",
            _underlyingUnits,
            _to,
            0
        );

        return (address(sDaiTokenContract), 0, callData);
    }

    /**
     * Generates the calldata to unwrap a wrapped asset into its underlying.
     *
     * @param _wrappedTokenUnits    Total quantity of wrapped token units to unwrap
     * @param _to                   Address to send the unwrapped tokens to
     *
     * @return address              Target contract address
     * @return uint256              Total quantity of wrapped token units to unwrap. This will always be 0 for unwrapping
     * @return bytes                Unwrap calldata
     */
    function getUnwrapCallData(
        address /*  _underlyingToken */,
        address /*  _wrappedToken */,
        uint256 _wrappedTokenUnits,
        address _to,
        bytes memory _unwrapData
    ) external view returns (address, uint256, bytes memory) {
        uint256 coinType = abi.decode(_unwrapData, (uint256));
        // see comments in IJasperVault.sol's ComponentPosition and ExternalPosition structs to understand what the coinType is
        require(coinType == 4, "wrappedToken is not sToken");
        bytes memory callData = abi.encodeWithSignature(
            "withdraw(uint256,address,address)",
            _wrappedTokenUnits,
            _to,
            _to
        );

        return (address(sDaiTokenContract), 0, callData);
    }

    /**
     * Returns the address to approve source tokens for wrapping.
     *
     * @return address        Address of the contract to approve tokens to
     */
    function getSpenderAddress(
        address /* _underlyingToken */,
        address /* _wrappedToken */
    ) external view returns (address) {
        return address(sDaiTokenContract);
    }
}
