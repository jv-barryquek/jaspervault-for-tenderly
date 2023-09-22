pragma solidity 0.6.10;
import {IJasperVault} from "./IJasperVault.sol";
pragma experimental "ABIEncoderV2";

interface IDelegatedManagerFactory {
    function createSetAndManager(
        uint256 _vaultType,
        address[] memory _components,
        int256[] memory _units,
        string memory _name,
        string memory _symbol,
        address _owner,
        address _methodologist,
        address[] memory _modules,
        address[] memory _adapters,
        address[] memory _operators,
        address[] memory _assets,
        address[] memory _extensions
    ) external returns (IJasperVault, address);

    function initialize(
        IJasperVault _jasperVault,
        uint256 _ownerFeeSplit,
        address _ownerFeeRecipient,
        address[] memory _extensions,
        bytes[] memory _initializeBytecode
    ) external;

    function jasperVaultType(address _jasperVault) external view returns(uint256);
    function account2setToken(address _account) external view returns(address);
    function setToken2account(address _jasperVault) external view returns(address);

}
