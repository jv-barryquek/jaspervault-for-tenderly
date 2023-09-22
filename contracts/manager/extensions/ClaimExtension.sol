/*
    Copyright 2022 Set Labs Inc.

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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

import { IAirdropModule } from "../../interfaces/IAirdropModule.sol";
import { IClaimAdapter } from "@setprotocol/set-protocol-v2/contracts/interfaces/IClaimAdapter.sol";
import { IClaimModule } from "../../interfaces/IClaimModule.sol";
import { IIntegrationRegistry } from "@setprotocol/set-protocol-v2/contracts/interfaces/IIntegrationRegistry.sol";
import { IJasperVault } from "../../interfaces/IJasperVault.sol";
import { PreciseUnitMath } from "@setprotocol/set-protocol-v2/contracts/lib/PreciseUnitMath.sol";

import { BaseGlobalExtension } from "../lib/BaseGlobalExtension.sol";
import { IDelegatedManager } from "../interfaces/IDelegatedManager.sol";
import { IManagerCore } from "../interfaces/IManagerCore.sol";

/**
 * @title ClaimExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager owner the ability to perform administrative tasks on the AirdropModule
 * and the ClaimModule and the DelegatedManager operator(s) the ability to
 * - absorb tokens sent to the JasperVault into the token's positions
 * - claim tokens from external protocols given to a Set as part of participating in incentivized activities of other protocols
 *     and absorb them into the JasperVault's positions in a single transaction
 */
contract ClaimExtension is BaseGlobalExtension {
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ Events ============ */

    event ClaimExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );

    event FeesDistributed(
        address _jasperVault,                         // Address of JasperVault which generated the airdrop fees
        address _token,                            // Address of the token to distribute
        address indexed _ownerFeeRecipient,        // Address which receives the owner's take of the fees
        address indexed _methodologist,            // Address of methodologist
        uint256 _ownerTake,                        // Amount of _token distributed to owner
        uint256 _methodologistTake                 // Amount of _token distributed to methodologist
    );

    /* ============ Modifiers ============ */

    /**
     * Throws if useAssetAllowList is true and one of the assets is not on the asset allow list
     */
    modifier onlyAllowedAssets(IJasperVault _jasperVault, address[] memory _assets) {
        _validateAllowedAssets(_jasperVault, _assets);
        _;
    }

    /**
     * Throws if anyoneAbsorb on the AirdropModule is false and caller is not the operator
     */
    modifier onlyValidAbsorbCaller(IJasperVault _jasperVault) {
        require(_isValidAbsorbCaller(_jasperVault), "Must be valid AirdropModule absorb caller");
        _;
    }

    /**
     * Throws if caller is not the operator and either anyoneAbsorb on the AirdropModule or anyoneClaim on the ClaimModule is false
     */
    modifier onlyValidClaimAndAbsorbCaller(IJasperVault _jasperVault) {
        require(_isValidClaimAndAbsorbCaller(_jasperVault), "Must be valid AirdropModule absorb and ClaimModule claim caller");
        _;
    }

    /* ============ State Variables ============ */

    // Instance of AirdropModule
    IAirdropModule public immutable airdropModule;

    // Instance of ClaimModule
    IClaimModule public immutable claimModule;

    // Instance of IntegrationRegistry
    IIntegrationRegistry public immutable integrationRegistry;

    /* ============ Constructor ============ */

    /**
     * Instantiate with ManagerCore, AirdropModule, ClaimModule, and Controller addresses.
     *
     * @param _managerCore              Address of ManagerCore contract
     * @param _airdropModule            Address of AirdropModule contract
     * @param _claimModule              Address of ClaimModule contract
     * @param _integrationRegistry      Address of IntegrationRegistry contract
     */
    constructor(
        IManagerCore _managerCore,
        IAirdropModule _airdropModule,
        IClaimModule _claimModule,
        IIntegrationRegistry _integrationRegistry
    )
        public
        BaseGlobalExtension(_managerCore)
    {
        airdropModule = _airdropModule;
        claimModule = _claimModule;
        integrationRegistry = _integrationRegistry;
    }

    /* ============ External Functions ============ */

    /**
     * ANYONE CALLABLE: Distributes airdrop fees accrued to the DelegatedManager. Calculates fees for
     * owner and methodologist, and sends to owner fee recipient and methodologist respectively.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _token                    Address of token to distribute
     */
    function distributeFees(
        IJasperVault _jasperVault,
        IERC20 _token
    )
        public
    {
        IDelegatedManager delegatedManager = _manager(_jasperVault);

        uint256 totalFees = _token.balanceOf(address(delegatedManager));

        address methodologist = delegatedManager.methodologist();
        address ownerFeeRecipient = delegatedManager.ownerFeeRecipient();

        uint256 ownerTake = totalFees.preciseMul(delegatedManager.ownerFeeSplit());
        uint256 methodologistTake = totalFees.sub(ownerTake);

        if (ownerTake > 0) {
            delegatedManager.transferTokens(address(_token), ownerFeeRecipient, ownerTake);
        }

        if (methodologistTake > 0) {
            delegatedManager.transferTokens(address(_token), methodologist, methodologistTake);
        }

        emit FeesDistributed(
            address(_jasperVault),
            address(_token),
            ownerFeeRecipient,
            methodologist,
            ownerTake,
            methodologistTake
        );
    }

    /**
     * ONLY OWNER: Initializes AirdropModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the AirdropModule for
     * @param _airdropSettings      Struct of airdrop setting for Set including accepted airdrops, feeRecipient,
     *                              airdropFee, and indicating if anyone can call an absorb
     */
    function initializeAirdropModule(
        IDelegatedManager _delegatedManager,
        IAirdropModule.AirdropSettings memory _airdropSettings
    )
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        _initializeAirdropModule(_delegatedManager.jasperVault(), _delegatedManager, _airdropSettings);
    }

    /**
     * ONLY OWNER: Initializes ClaimModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the ClaimModule for
     * @param _anyoneClaim          Boolean indicating if anyone can claim or just manager
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in rewardPools
     */
    function initializeClaimModule(
        IDelegatedManager _delegatedManager,
        bool _anyoneClaim,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        _initializeClaimModule(_delegatedManager.jasperVault(), _delegatedManager, _anyoneClaim, _rewardPools, _integrationNames);
    }

    /**
     * ONLY OWNER: Initializes ClaimExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(IDelegatedManager _delegatedManager) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit ClaimExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY OWNER: Initializes ClaimExtension to the DelegatedManager and AirdropModule and ClaimModule to the JasperVault
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     * @param _airdropSettings      Struct of airdrop setting for Set including accepted airdrops, feeRecipient,
     *                              airdropFee, and indicating if anyone can call an absorb
     * @param _anyoneClaim          Boolean indicating if anyone can claim or just manager
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in rewardPools
     */
    function initializeModulesAndExtension(
        IDelegatedManager _delegatedManager,
        IAirdropModule.AirdropSettings memory _airdropSettings,
        bool _anyoneClaim,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeAirdropModule(_delegatedManager.jasperVault(), _delegatedManager, _airdropSettings);
        _initializeClaimModule(_delegatedManager.jasperVault(), _delegatedManager, _anyoneClaim, _rewardPools, _integrationNames);

        emit ClaimExtensionInitialized(address(jasperVault), address(_delegatedManager));
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the ClaimExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    /**
     * ONLY VALID ABSORB CALLER: Absorb passed tokens into respective positions. If airdropFee defined, send portion to feeRecipient
     * and portion to protocol feeRecipient address. Callable only by operator unless set anyoneAbsorb is true on the AirdropModule.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _tokens                   Array of tokens to absorb
     */
    function batchAbsorb(
        IJasperVault _jasperVault,
        address[] memory _tokens
    )
        external
        onlyValidAbsorbCaller(_jasperVault)
        onlyAllowedAssets(_jasperVault, _tokens)
    {
        _batchAbsorb(_jasperVault, _tokens);
    }

    /**
     * ONLY VALID ABSORB CALLER: Absorb specified token into position. If airdropFee defined, send portion to feeRecipient and portion to
     * protocol feeRecipient address. Callable only by operator unless anyoneAbsorb is true on the AirdropModule.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _token                    Address of token to absorb
     */
    function absorb(
        IJasperVault _jasperVault,
        IERC20 _token
    )
        external
        onlyValidAbsorbCaller(_jasperVault)
        onlyAllowedAsset(_jasperVault, address(_token))
    {
        _absorb(_jasperVault, _token);
    }

    /**
     * ONLY OWNER: Adds new tokens to be added to positions when absorb is called.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _airdrop                  Component to add to airdrop list
     */
    function addAirdrop(
        IJasperVault _jasperVault,
        IERC20 _airdrop
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.addAirdrop.selector,
            _jasperVault,
            _airdrop
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * ONLY OWNER: Removes tokens from list to be absorbed.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _airdrop                  Component to remove from airdrop list
     */
    function removeAirdrop(
        IJasperVault _jasperVault,
        IERC20 _airdrop
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.removeAirdrop.selector,
            _jasperVault,
            _airdrop
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * ONLY OWNER: Update whether manager allows other addresses to call absorb.
     *
     * @param _jasperVault                 Address of JasperVault
     */
    function updateAnyoneAbsorb(
        IJasperVault _jasperVault,
        bool _anyoneAbsorb
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.updateAnyoneAbsorb.selector,
            _jasperVault,
            _anyoneAbsorb
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * ONLY OWNER: Update address AirdropModule manager fees are sent to.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _newFeeRecipient      Address of new fee recipient
     */
    function updateAirdropFeeRecipient(
        IJasperVault _jasperVault,
        address _newFeeRecipient
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.updateFeeRecipient.selector,
            _jasperVault,
            _newFeeRecipient
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * ONLY OWNER: Update airdrop fee percentage.
     *
     * @param _jasperVault         Address of JasperVault
     * @param _newFee           Percentage, in preciseUnits, of new airdrop fee (1e16 = 1%)
     */
    function updateAirdropFee(
        IJasperVault _jasperVault,
        uint256 _newFee
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.updateAirdropFee.selector,
            _jasperVault,
            _newFee
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * ONLY VALID CLAIM AND ABSORB CALLER: Claim the rewards available on the rewardPool for the specified claim integration and absorb
     * the reward token into position. If airdropFee defined, send portion to feeRecipient and portion to protocol feeRecipient address.
     * Callable only by operator unless anyoneAbsorb on the AirdropModule and anyoneClaim on the ClaimModule are true.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _rewardPool               Address of the rewardPool that identifies the contract governing claims
     * @param _integrationName          ID of claim module integration (mapping on integration registry)
     */
    function claimAndAbsorb(
        IJasperVault _jasperVault,
        address _rewardPool,
        string calldata _integrationName
    )
        external
        onlyValidClaimAndAbsorbCaller(_jasperVault)
    {
        IERC20 rewardsToken = _getAndValidateRewardsToken(_jasperVault, _rewardPool, _integrationName);

        _claim(_jasperVault, _rewardPool, _integrationName);

        _absorb(_jasperVault, rewardsToken);
    }

    /**
     * ONLY VALID CLAIM AND ABSORB CALLER: Claims rewards on all the passed rewardPool/claim integration pairs and absorb the reward tokens
     * into positions. If airdropFee defined, send portion of each reward token to feeRecipient and a portion to protocol feeRecipient address.
     * Callable only by operator unless anyoneAbsorb on the AirdropModule and anyoneClaim on the ClaimModule are true.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in rewardPools
     */
    function batchClaimAndAbsorb(
        IJasperVault _jasperVault,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        external
        onlyValidClaimAndAbsorbCaller(_jasperVault)
    {
        address[] storage rewardsTokens;
        uint256 numPools = _rewardPools.length;
        for (uint256 i = 0; i < numPools; i++) {
            IERC20 token = _getAndValidateRewardsToken(_jasperVault, _rewardPools[i], _integrationNames[i]);
            rewardsTokens.push(address(token));
        }

        _batchClaim(_jasperVault, _rewardPools, _integrationNames);

        _batchAbsorb(_jasperVault, rewardsTokens);
    }

    /**
     * ONLY OWNER: Update whether manager allows other addresses to call claim.
     *
     * @param _jasperVault             Address of JasperVault
     */
    function updateAnyoneClaim(
        IJasperVault _jasperVault,
        bool _anyoneClaim
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.updateAnyoneClaim.selector,
            _jasperVault,
            _anyoneClaim
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * ONLY OWNER: Adds a new claim integration for an existent rewardPool. If rewardPool doesn't have existing
     * claims then rewardPool is added to rewardPoolList. The claim integration is associated to an adapter that
     * provides the functionality to claim the rewards for a specific token.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPool           Address of the rewardPool that identifies the contract governing claims
     * @param _integrationName      ID of claim module integration (mapping on integration registry)
     */
    function addClaim(
        IJasperVault _jasperVault,
        address _rewardPool,
        string calldata _integrationName
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.addClaim.selector,
            _jasperVault,
            _rewardPool,
            _integrationName
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * ONLY OWNER: Adds a new rewardPool to the list to perform claims for the JasperVault indicating the list of
     * claim integrations. Each claim integration is associated to an adapter that provides the functionality to claim
     * the rewards for a specific token.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same
     *                                  index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index
     *                                  in rewardPools
     */
    function batchAddClaim(
        IJasperVault _jasperVault,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.batchAddClaim.selector,
            _jasperVault,
            _rewardPools,
            _integrationNames
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * ONLY OWNER: Removes a claim integration from an existent rewardPool. If no claim remains for reward pool then
     * reward pool is removed from rewardPoolList.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPool           Address of the rewardPool that identifies the contract governing claims
     * @param _integrationName      ID of claim module integration (mapping on integration registry)
     */
    function removeClaim(
        IJasperVault _jasperVault,
        address _rewardPool,
        string calldata _integrationName
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.removeClaim.selector,
            _jasperVault,
            _rewardPool,
            _integrationName
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * ONLY OWNER: Batch removes claims from JasperVault's settings.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index
     *                                  integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in
     *                                  rewardPools
     */
    function batchRemoveClaim(
        IJasperVault _jasperVault,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.batchRemoveClaim.selector,
            _jasperVault,
            _rewardPools,
            _integrationNames
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }


    /* ============ Internal Functions ============ */

    /**
     * Internal function to initialize AirdropModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the AirdropModule for
     * @param _airdropSettings      Struct of airdrop setting for Set including accepted airdrops, feeRecipient,
     *                              airdropFee, and indicating if anyone can call an absorb
     */
    function _initializeAirdropModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager,
        IAirdropModule.AirdropSettings memory _airdropSettings
    )
        internal
    {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.initialize.selector,
            _jasperVault,
            _airdropSettings
        );
        _invokeManager(_delegatedManager, address(airdropModule), callData);
    }

    /**
     * Internal function to initialize ClaimModule on the JasperVault associated with the DelegatedManager.
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     * @param _delegatedManager     Instance of the DelegatedManager to initialize the ClaimModule for
     * @param _anyoneClaim          Boolean indicating if anyone can claim or just manager
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in rewardPools
     */
    function _initializeClaimModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager,
        bool _anyoneClaim,
        address[] calldata _rewardPools,
        string[] calldata _integrationNames
    )
        internal
    {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.initialize.selector,
            _jasperVault,
            _anyoneClaim,
            _rewardPools,
            _integrationNames
        );
        _invokeManager(_delegatedManager, address(claimModule), callData);
    }

    /**
     * Must have all assets on asset allow list or useAssetAllowlist to be false
     */
    function _validateAllowedAssets(IJasperVault _jasperVault, address[] memory _assets) internal view {
        IDelegatedManager manager = _manager(_jasperVault);
        if (manager.useAssetAllowlist()) {
            uint256 assetsLength = _assets.length;
            for (uint i = 0; i < assetsLength; i++) {
                require(manager.assetAllowlist(_assets[i]), "Must be allowed asset");
            }
        }
    }

    /**
     * AirdropModule anyoneAbsorb setting must be true or must be operator
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     */
    function _isValidAbsorbCaller(IJasperVault _jasperVault) internal view returns(bool) {
        return airdropModule.airdropSettings(_jasperVault).anyoneAbsorb || _manager(_jasperVault).operatorAllowlist(msg.sender);
    }

    /**
     * Must be operator or must have both AirdropModule anyoneAbsorb and ClaimModule anyoneClaim
     *
     * @param _jasperVault             Instance of the JasperVault corresponding to the DelegatedManager
     */
    function _isValidClaimAndAbsorbCaller(IJasperVault _jasperVault) internal view returns(bool) {
        return (
            (claimModule.anyoneClaim(_jasperVault) && airdropModule.airdropSettings(_jasperVault).anyoneAbsorb)
            || _manager(_jasperVault).operatorAllowlist(msg.sender)
        );
    }

    /**
     * Absorb specified token into position. If airdropFee defined, send portion to feeRecipient and portion to protocol feeRecipient address.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _token                    Address of token to absorb
     */
    function _absorb(IJasperVault _jasperVault, IERC20 _token) internal {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.absorb.selector,
            _jasperVault,
            _token
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
    }

    /**
     * Absorb passed tokens into respective positions. If airdropFee defined, send portion to feeRecipient and portion to protocol feeRecipient address.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _tokens                   Array of tokens to absorb
     */
     function _batchAbsorb(IJasperVault _jasperVault, address[] memory _tokens) internal {
        bytes memory callData = abi.encodeWithSelector(
            IAirdropModule.batchAbsorb.selector,
            _jasperVault,
            _tokens
        );
        _invokeManager(_manager(_jasperVault), address(airdropModule), callData);
     }

    /**
     * Claim the rewards available on the rewardPool for the specified claim integration and absorb the reward token into position.
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _rewardPool               Address of the rewardPool that identifies the contract governing claims
     * @param _integrationName          ID of claim module integration (mapping on integration registry)
     */
    function _claim(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) internal {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.claim.selector,
            _jasperVault,
            _rewardPool,
            _integrationName
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * Claims rewards on all the passed rewardPool/claim integration pairs and absorb the reward tokens into positions.
     *
     * @param _jasperVault             Address of JasperVault
     * @param _rewardPools          Addresses of rewardPools that identifies the contract governing claims. Maps to same index integrationNames
     * @param _integrationNames     Human-readable names matching adapter used to collect claim on pool. Maps to same index in rewardPools
     */
    function _batchClaim(IJasperVault _jasperVault, address[] calldata _rewardPools, string[] calldata _integrationNames) internal {
        bytes memory callData = abi.encodeWithSelector(
            IClaimModule.batchClaim.selector,
            _jasperVault,
            _rewardPools,
            _integrationNames
        );
        _invokeManager(_manager(_jasperVault), address(claimModule), callData);
    }

    /**
     * Get the rewards token from the rewardPool and integrationName and check if it is an allowed asset on the DelegatedManager
     *
     * @param _jasperVault                 Address of JasperVault
     * @param _rewardPool               Address of the rewardPool that identifies the contract governing claims
     * @param _integrationName          ID of claim module integration (mapping on integration registry)
     */
    function _getAndValidateRewardsToken(IJasperVault _jasperVault, address _rewardPool, string calldata _integrationName) internal view returns(IERC20) {
        IClaimAdapter adapter = IClaimAdapter(integrationRegistry.getIntegrationAdapter(address(claimModule), _integrationName));
        IERC20 rewardsToken = adapter.getTokenAddress(_rewardPool);
        require(_manager(_jasperVault).isAllowedAsset(address(rewardsToken)), "Must be allowed asset");
        return rewardsToken;
    }
}
