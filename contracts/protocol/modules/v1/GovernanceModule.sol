/*
    Copyright 2020 Set Labs Inc.

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

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IController } from "../../../interfaces/IController.sol";
import { IGovernanceAdapter } from "../../../interfaces/IGovernanceAdapter.sol";
import { Invoke } from "../../lib/Invoke.sol";
import { IJasperVault } from "../../../interfaces/IJasperVault.sol";
import { ModuleBase } from "../../lib/ModuleBase.sol";


/**
 * @title GovernanceModule
 * @author Set Protocol
 *
 * A smart contract module that enables participating in governance of component tokens held in the JasperVault.
 * Examples of intended protocols include Compound, Uniswap, and Maker governance.
 */
contract GovernanceModule is ModuleBase, ReentrancyGuard {
    using Invoke for IJasperVault;

    /* ============ Events ============ */
    event ProposalVoted(
        IJasperVault indexed _jasperVault,
        IGovernanceAdapter indexed _governanceAdapter,
        uint256 indexed _proposalId,
        bool _support
    );

    event VoteDelegated(
        IJasperVault indexed _jasperVault,
        IGovernanceAdapter indexed _governanceAdapter,
        address _delegatee
    );

    event ProposalCreated(
        IJasperVault indexed _jasperVault,
        IGovernanceAdapter indexed _governanceAdapter,
        bytes _proposalData
    );

    event RegistrationSubmitted(
        IJasperVault indexed _jasperVault,
        IGovernanceAdapter indexed _governanceAdapter
    );

    event RegistrationRevoked(
        IJasperVault indexed _jasperVault,
        IGovernanceAdapter indexed _governanceAdapter
    );

    /* ============ Constructor ============ */

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * SET MANAGER ONLY. Delegate voting power to an Ethereum address. Note: for some governance adapters, delegating to self is
     * equivalent to registering and delegating to zero address is revoking right to vote.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _delegatee                Address of delegatee
     */
    function delegate(
        IJasperVault _jasperVault,
        string memory _governanceName,
        address _delegatee
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getDelegateCalldata(_delegatee);

        _jasperVault.invoke(targetExchange, callValue, methodData);

        emit VoteDelegated(_jasperVault, governanceAdapter, _delegatee);
    }

    /**
     * SET MANAGER ONLY. Create a new proposal for a specified governance protocol.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _proposalData             Byte data of proposal to pass into governance adapter
     */
    function propose(
        IJasperVault _jasperVault,
        string memory _governanceName,
        bytes memory _proposalData
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getProposeCalldata(_proposalData);

        _jasperVault.invoke(targetExchange, callValue, methodData);

        emit ProposalCreated(_jasperVault, governanceAdapter, _proposalData);
    }

    /**
     * SET MANAGER ONLY. Register for voting for the JasperVault
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     */
    function register(
        IJasperVault _jasperVault,
        string memory _governanceName
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getRegisterCalldata(address(_jasperVault));

        _jasperVault.invoke(targetExchange, callValue, methodData);

        emit RegistrationSubmitted(_jasperVault, governanceAdapter);
    }

    /**
     * SET MANAGER ONLY. Revoke voting for the JasperVault
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     */
    function revoke(
        IJasperVault _jasperVault,
        string memory _governanceName
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getRevokeCalldata();

        _jasperVault.invoke(targetExchange, callValue, methodData);

        emit RegistrationRevoked(_jasperVault, governanceAdapter);
    }

    /**
     * SET MANAGER ONLY. Cast vote for a specific governance token held in the JasperVault. Manager specifies whether to vote for or against
     * a given proposal
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _governanceName           Human readable name of integration (e.g. COMPOUND) stored in the IntegrationRegistry
     * @param _proposalId               ID of the proposal to vote on
     * @param _support                  Boolean indicating whether to support proposal
     * @param _data                     Arbitrary bytes to be used to construct vote call data
     */
    function vote(
        IJasperVault _jasperVault,
        string memory _governanceName,
        uint256 _proposalId,
        bool _support,
        bytes memory _data
    )
        external
        nonReentrant
        onlyManagerAndValidSet(_jasperVault)
    {
        IGovernanceAdapter governanceAdapter = IGovernanceAdapter(getAndValidateAdapter(_governanceName));

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = governanceAdapter.getVoteCalldata(
            _proposalId,
            _support,
            _data
        );

        _jasperVault.invoke(targetExchange, callValue, methodData);

        emit ProposalVoted(_jasperVault, governanceAdapter, _proposalId, _support);
    }

    /**
     * Initializes this module to the JasperVault. Only callable by the JasperVault's manager.
     *
     * @param _jasperVault             Instance of the JasperVault to issue
     */
    function initialize(IJasperVault _jasperVault) external onlySetManager(_jasperVault, msg.sender) onlyValidAndPendingSet(_jasperVault) {
        _jasperVault.initializeModule();
    }

    /**
     * Removes this module from the JasperVault, via call by the JasperVault.
     */
    function removeModule() external override {}
}
