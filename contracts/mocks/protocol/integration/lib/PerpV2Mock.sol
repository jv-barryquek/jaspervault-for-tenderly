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
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IClearingHouse } from "../../../../interfaces/external/perp-v2/IClearingHouse.sol";
import { IVault } from "../../../../interfaces/external/perp-v2/IVault.sol";
import { IQuoter } from "../../../../interfaces/external/perp-v2/IQuoter.sol";

import { PerpV2 } from "../../../../protocol/integration/lib/PerpV2.sol";
import { IJasperVault } from "../../../../interfaces/IJasperVault.sol";

/**
 * @title PerpV2Mock
 * @author Set Protocol
 *
 * Mock for PerpV2 Library contract. Used for testing PerpV2 Library contract, as the library
 * contract can't be tested directly using ethers.js
 */
contract PerpV2Mock {

    /* ============ External ============ */

    function testGetDepositCalldata(
        IVault _vault,
        IERC20 _asset,
        uint256 _amountNotional
    )
        public
        pure
        returns (address, uint256, bytes memory)
    {
        return PerpV2.getDepositCalldata(_vault, _asset, _amountNotional);
    }

    function testInvokeDeposit(
        IJasperVault _jasperVault,
        IVault _vault,
        IERC20 _asset,
        uint256 _amountNotional
    )
        external
    {
        return PerpV2.invokeDeposit(_jasperVault, _vault, _asset, _amountNotional);
    }

    function testGetWithdrawCalldata(
        IVault _vault,
        IERC20 _asset,
        uint256 _amountNotional
    )
        public
        pure
        returns (address, uint256, bytes memory)
    {
        return PerpV2.getWithdrawCalldata(_vault, _asset, _amountNotional);
    }

    function testInvokeWithdraw(
        IJasperVault _jasperVault,
        IVault _vault,
        IERC20 _asset,
        uint256 _amountNotional
    )
        external
    {
        return PerpV2.invokeWithdraw(_jasperVault, _vault, _asset, _amountNotional);
    }

    function testGetOpenPositionCalldata(
        IClearingHouse _clearingHouse,
        IClearingHouse.OpenPositionParams memory _params
    )
        public
        pure
        returns (address, uint256, bytes memory)
    {
        return PerpV2.getOpenPositionCalldata(_clearingHouse, _params);
    }

    function testInvokeOpenPosition(
        IJasperVault _jasperVault,
        IClearingHouse _clearingHouse,
        IClearingHouse.OpenPositionParams memory _params
    )
        external
        returns (uint256 deltaBase, uint256 deltaQuote)
    {
        return PerpV2.invokeOpenPosition(_jasperVault, _clearingHouse, _params);
    }

    function testGetSwapCalldata(
        IQuoter _quoter,
        IQuoter.SwapParams memory _params
    )
        public
        pure
        returns (address, uint256, bytes memory)
    {
        return PerpV2.getSwapCalldata(_quoter, _params);
    }

    function testInvokeSwap(
        IJasperVault _jasperVault,
        IQuoter _quoter,
        IQuoter.SwapParams memory _params
    )
        external
        returns (IQuoter.SwapResponse memory)
    {
        return PerpV2.invokeSwap(_jasperVault, _quoter, _params);
    }

    /* ============ Helper Functions ============ */

    function initializeModuleOnSet(IJasperVault _jasperVault) external {
        _jasperVault.initializeModule();
    }
}
