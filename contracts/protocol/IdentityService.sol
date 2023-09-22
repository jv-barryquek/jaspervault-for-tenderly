// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import {IController} from "../interfaces/IController.sol";
import {Ownable} from "openzeppelin-contracts-V4/access/Ownable.sol";
import {AddressArrayUtils} from "../lib/AddressArrayUtilsV2.sol";
import {JasperSoulBoundToken} from "./JasperSoulBoundToken.sol";
import {IJasperSoulBoundToken} from "../interfaces/IJasperSoulBoundToken.sol";
import {IERC721} from "openzeppelin-contracts-V4/token/ERC721/IERC721.sol";

interface IJasperVault {
    function manager() external view returns (address);
}

interface IOwnable {
    function owner() external view returns (address);
}

/**


 *
 * The IntegrationRegistry holds state relating to the Modules and the integrations they are connected with.
 * The state is combined into a single Registry to allow governance updates to be aggregated to one contract.
 */
contract IdentityService is Ownable {
    using AddressArrayUtils for address[];
    modifier onlyAdmin() {
        require(_admins[msg.sender], "Caller is not an admin");
        _;
    }

    /* ============ Events ============ */
    event SetAccountType(address account, uint8 value, address id_nft);

    event RemoveAccount(address account);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IController public controller;
    address[] public accounts;
    mapping(address => address) public account2idnft;
    mapping(address => uint8) public account_type;
    mapping(address => bool) private _admins;
    address[] private _adminList;

    /* ============ Constructor ============ */

    /**
     * Initializes the controller
     *
     * @param _controller          Instance of the controller
     */
    constructor(IController _controller) {
        controller = _controller;
    }

    /* ============ External Functions ============ */
    function set_account_type(address account, uint8 value) public onlyAdmin {
        require(account != address(0), "Account address must exist.");
        account_type[account] = value;
        accounts.push(account);
        JasperSoulBoundToken newaccountNFT = new JasperSoulBoundToken(
            msg.sender
        );
        account2idnft[account] = address(newaccountNFT);
        emit SetAccountType(account, value, address(newaccountNFT));
    }

    function removeAccount(address account) public onlyAdmin {
        require(account != address(0), "Account address must exist.");
        IJasperSoulBoundToken id_nft = IJasperSoulBoundToken(
            account2idnft[account]
        );
        require(
            msg.sender == id_nft.admin(),
            "Only admin can remove their account"
        );
        accounts = accounts.remove(account);
        id_nft.burn(0);
        emit RemoveAccount(account);
    }

    function batchSet_account_type(
        address[] memory _accounts,
        uint8[] memory _values
    ) external onlyAdmin {
        require(
            _accounts.length == _values.length,
            "Accounts and Values lengths mismatch"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            set_account_type(_accounts[i], _values[i]);
        }
    }

    function getAccounts() external view returns (address[] memory) {
        return accounts;
    }

    function isPrimeByJasperVault(
        address _jasperVault
    ) external view returns (bool) {
        address dm = IJasperVault(_jasperVault).manager();
        address vault = IOwnable(dm).owner();
        address wallet_addr = IOwnable(vault).owner();
        IERC721 id_nft = IERC721(account2idnft[wallet_addr]);
        return id_nft.balanceOf(wallet_addr) == 1;
    }

    function isAdmin(address admin) public view returns (bool) {
        return _admins[admin];
    }

    function addAdmin(address admin) public onlyOwner {
        _addAdmin(admin);
    }

    function removeAdmin(address admin) public onlyOwner {
        require(_admins[admin], "Account is not an admin");
        _admins[admin] = false;
        for (uint256 i = 0; i < _adminList.length; i++) {
            if (_adminList[i] == admin) {
                _adminList[i] = _adminList[_adminList.length - 1];
                _adminList.pop();
                break;
            }
        }
    }

    function getAdmins() public view returns (address[] memory) {
        return _adminList;
    }

    function _addAdmin(address admin) internal {
        require(!_admins[admin], "Account is already an admin");
        _admins[admin] = true;
        _adminList.push(admin);
    }
}
