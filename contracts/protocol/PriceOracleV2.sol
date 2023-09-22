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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AddressArrayUtils} from "../lib/AddressArrayUtils.sol";
import {IController} from "../interfaces/IController.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {IGenericAsset} from "../interfaces/external/IGenericAsset.sol";
import {PreciseUnitMath} from "../lib/PreciseUnitMath.sol";
import {PriceApiConsumer} from "./integration/oracles/PriceApiConsumer.sol";

/**
 * @title PriceOracleV2
 * @author JasperVault
 *
 * Contract that returns the price for any given asset pair. Price is retrieved either directly from an oracle,
 * calculated using common asset pairs, or uses external data to calculate price.
 * Note: Prices are returned in preciseUnits (i.e. 18 decimals of precision)
 *
 * Changelog:
 * V2 makes use of the ApiConsumer contract instance in order to access an off-chain API for price data, in the case that system oracles and adapters fail to return relative price for an asset pair in `getPrice()`
 */
contract PriceOracleV2 is Ownable {
  using PreciseUnitMath for uint256;
  using AddressArrayUtils for address[];

  /* ============ Structs ============ */
  struct PriceApiData {
    // String specifiying the endpoint
    string externalApiEndpoint;
    // String for HTTP method to make request to endpoint with; lowercase like in the Chainlink docs examples for making requests
    string httpMethodLowerCase;
    // String specifying the 'path' to get the particular data point (in this case, price) by 'indexing' the response object returned by the external API
    string pathForPricesData; // should be something like 'prices', accessing an array of objects resembling AssetPairPriceResponse
  }

  struct DataForApiConsumerConstruction {
    // * we package them into a struct to avoid compilation errors from having too many parameters in the constructor
    uint256 networkId; // used as query parameter to API request
    address linkTokenAddress;
    address chainLinkNodeAddress; // the on-chain address used by our Chainlink node instance to sign and send responses; needed to restrict access to initiating the ApiCall
    address operatorContract; // our operator contract address
    bytes32 nodeJobId;
    uint256 linkTokenDivisibility; // varies by network and job
    string httpMethodLowerCase; // in lower case as per Chainlink convention
    string endpointUrl;
    string pathForPriceData; // specifies how to index API's response data for specific data wanted
  }

  /* ============ Events ============ */

  event PairAdded(
    address indexed _assetOne,
    address indexed _assetTwo,
    address _oracle
  );
  event PairRemoved(
    address indexed _assetOne,
    address indexed _assetTwo,
    address _oracle
  );
  event PairEdited(
    address indexed _assetOne,
    address indexed _assetTwo,
    address _newOracle
  );
  event AdapterAdded(address _adapter);
  event AdapterRemoved(address _adapter);
  event MasterQuoteAssetEdited(address _newMasterQuote);

  /* ============ State Variables ============ */

  // Address of the Controller contract
  IController public controller;

  // Mapping between assetA/assetB and its associated Price Oracle
  // Asset 1 -> Asset 2 -> IOracle Interface
  mapping(address => mapping(address => IOracle)) public oracles;

  // Token address of the bridge asset that prices are derived from if the specified pair price is missing
  address public masterQuoteAsset;

  address[] public QuoteAssets;

  // List of IOracleAdapters used to return prices of third party protocols (e.g. Uniswap, Compound, Balancer)
  address[] public adapters;

  // Interface to get asset pair price from PriceApiConsumer as a last resort if oracles and LP pools do not provide data
  PriceApiConsumer public priceApiConsumer;

  /* ============ Constructor ============ */

  /**
   * Set state variables and map asset pairs to their oracles
   *
   * @param _controller             Address of controller contract
   * @param _quoteAssets       Address of asset that can be used to link unrelated asset pairs
   * @param _adapters               List of adapters used to price assets created by other protocols
   * @param _assetOnes              List of first asset in pair, index i maps to same index in assetTwos and oracles
   * @param _assetTwos              List of second asset in pair, index i maps to same index in assetOnes and oracles
   * @param _oracles                List of oracles, index i maps to same index in assetOnes and assetTwos
   * @param _apiConsumerData     Struct containg data required to construct the PriceApiConsumer instance
   */
  constructor(
    IController _controller,
    address[] memory _quoteAssets,
    address[] memory _adapters,
    address[] memory _assetOnes,
    address[] memory _assetTwos,
    IOracle[] memory _oracles,
    DataForApiConsumerConstruction memory _apiConsumerData
  ) public {
    controller = _controller;
    masterQuoteAsset = _quoteAssets[0];
    QuoteAssets = _quoteAssets;
    adapters = _adapters;
    require(
      _assetOnes.length == _assetTwos.length &&
        _assetTwos.length == _oracles.length,
      "Array lengths do not match."
    );

    for (uint256 i = 0; i < _assetOnes.length; i++) {
      oracles[_assetOnes[i]][_assetTwos[i]] = _oracles[i];
    }
    priceApiConsumer = new PriceApiConsumer(
      _apiConsumerData.networkId,
      _apiConsumerData.linkTokenAddress,
      _apiConsumerData.chainLinkNodeAddress,
      _apiConsumerData.operatorContract,
      _apiConsumerData.nodeJobId,
      _apiConsumerData.linkTokenDivisibility,
      _apiConsumerData.httpMethodLowerCase,
      _apiConsumerData.endpointUrl,
      _apiConsumerData.pathForPriceData
    );
  }

  /* ============ External Functions ============ */

  /**
   * SYSTEM-ONLY PRIVELEGE: Find price of passed asset pair, if possible. The steps it takes are:
   *  1) Check to see if a direct or inverse oracle of the pair exists,
   *  2) If not, use masterQuoteAsset to link pairs together (i.e. BTC/ETH and ETH/USDC
   *     could be used to calculate BTC/USDC).
   *  3) If not, check oracle adapters in case one or more of the assets needs external protocol data
   *     to price.
   *  4) If all steps fail, revert.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @return                  Price of asset pair to 18 decimals of precision
   */
  function getPrice(
    address _assetOne,
    address _assetTwo
  ) external view returns (uint256) {
    // * uncomment this check for testing
    require(
      controller.isSystemContract(msg.sender),
      "PriceOracleV2.getPrice: Caller must be system contract."
    );

    bool priceFound;
    uint256 price;

    (priceFound, price) = _getDirectOrInversePrice(_assetOne, _assetTwo);

    if (!priceFound) {
      (priceFound, price) = _getPriceFromMasterQuote(_assetOne, _assetTwo);
    }

    if (!priceFound) {
      (priceFound, price) = _getPriceFromAdapters(_assetOne, _assetTwo);
    }

    if (!priceFound) {
      price = priceApiConsumer.getCalculatedPairPrice(_assetOne, _assetTwo);
    }

    return price;
  }

  function addQuoteAsset(address _quoteAsset) external onlyOwner {
    QuoteAssets.push(_quoteAsset);
  }

  function removeQuoteAsset(address _quoteAsset) external onlyOwner {
    QuoteAssets = QuoteAssets.remove(_quoteAsset);
    masterQuoteAsset = QuoteAssets[0];
  }

  /**
   * GOVERNANCE FUNCTION: Add new asset pair oracle.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @param _oracle           Address of asset pair's oracle
   */
  function addPair(
    address _assetOne,
    address _assetTwo,
    IOracle _oracle
  ) external onlyOwner {
    require(
      address(oracles[_assetOne][_assetTwo]) == address(0),
      "PriceOracleV2.addPair: Pair already exists."
    );
    oracles[_assetOne][_assetTwo] = _oracle;

    emit PairAdded(_assetOne, _assetTwo, address(_oracle));
  }

  // todo: probably want to add the equivalent for addPairForAPI.
  // * rename the above to addPairWithOracle; will need to create a new interface

  /**
   * GOVERNANCE FUNCTION: Edit an existing asset pair's oracle.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @param _oracle           Address of asset pair's new oracle
   */
  function editPair(
    address _assetOne,
    address _assetTwo,
    IOracle _oracle
  ) external onlyOwner {
    require(
      address(oracles[_assetOne][_assetTwo]) != address(0),
      "PriceOracleV2.editPair: Pair doesn't exist."
    );
    oracles[_assetOne][_assetTwo] = _oracle;

    emit PairEdited(_assetOne, _assetTwo, address(_oracle));
  }

  /**
   * GOVERNANCE FUNCTION: Remove asset pair's oracle.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   */
  function removePair(address _assetOne, address _assetTwo) external onlyOwner {
    require(
      address(oracles[_assetOne][_assetTwo]) != address(0),
      "PriceOracleV2.removePair: Pair doesn't exist."
    );
    IOracle oldOracle = oracles[_assetOne][_assetTwo];
    delete oracles[_assetOne][_assetTwo];

    emit PairRemoved(_assetOne, _assetTwo, address(oldOracle));
  }

  /**
   * GOVERNANCE FUNCTION: Add new oracle adapter.
   *
   * @param _adapter         Address of new adapter
   */
  function addAdapter(address _adapter) external onlyOwner {
    require(
      !adapters.contains(_adapter),
      "PriceOracleV2.addAdapter: Adapter already exists."
    );
    adapters.push(_adapter);

    emit AdapterAdded(_adapter);
  }

  /**
   * GOVERNANCE FUNCTION: Remove oracle adapter.
   *
   * @param _adapter         Address of adapter to remove
   */
  function removeAdapter(address _adapter) external onlyOwner {
    require(
      adapters.contains(_adapter),
      "PriceOracleV2.removeAdapter: Adapter does not exist."
    );
    adapters = adapters.remove(_adapter);

    emit AdapterRemoved(_adapter);
  }

  /**
   * GOVERNANCE FUNCTION: Change the master quote asset.
   *
   * @param _newMasterQuoteAsset         New address of master quote asset
   */
  function editMasterQuoteAsset(
    address _newMasterQuoteAsset
  ) external onlyOwner {
    masterQuoteAsset = _newMasterQuoteAsset;
    QuoteAssets[0] = _newMasterQuoteAsset;
    emit MasterQuoteAssetEdited(_newMasterQuoteAsset);
  }

  /* ============ External View Functions ============ */

  /**
   * Returns an array of adapters
   */
  function getAdapters() external view returns (address[] memory) {
    return adapters;
  }

  /* ============ Internal Functions ============ */

  /**
   * Check if direct or inverse oracle exists. If so return that price along with boolean indicating
   * it exists. Otherwise return boolean indicating oracle doesn't exist.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @return bool             Boolean indicating if oracle exists
   * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
   */
  function _getDirectOrInversePrice(
    address _assetOne,
    address _assetTwo
  ) internal view returns (bool, uint256) {
    IOracle directOracle = oracles[_assetOne][_assetTwo];
    bool hasDirectOracle = address(directOracle) != address(0);

    // Check asset1 -> asset 2. If exists, then return value
    if (hasDirectOracle) {
      return (true, directOracle.read());
    }

    IOracle inverseOracle = oracles[_assetTwo][_assetOne];
    bool hasInverseOracle = address(inverseOracle) != address(0);

    // If not, check asset 2 -> asset 1. If exists, then return 1 / asset1 -> asset2
    if (hasInverseOracle) {
      return (true, _calculateInversePrice(inverseOracle));
    }

    return (false, 0);
  }

  /**
   * Try to calculate asset pair price by getting each asset in the pair's price relative to master
   * quote asset. Both prices must exist otherwise function returns false and no price.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @return bool             Boolean indicating if oracle exists
   * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
   */
  function _getPriceFromMasterQuote(
    address _assetOne,
    address _assetTwo
  ) internal view returns (bool, uint256) {
    address quote_assetOne = masterQuoteAsset;
    address quote_assetTwo = masterQuoteAsset;
    uint256 assetOnePrice;
    uint256 assetTwoPrice;
    bool priceFoundOne;
    bool priceFoundTwo;
    for (uint256 i = 0; i < QuoteAssets.length; i++) {
      address quoteAsset = QuoteAssets[i];
      (priceFoundOne, assetOnePrice) = _getDirectOrInversePrice(
        _assetOne,
        quoteAsset
      );
      if (priceFoundOne) {
        quote_assetOne = quoteAsset;
      }
    }
    if (_assetTwo != masterQuoteAsset) {
      for (uint256 i = 0; i < QuoteAssets.length; i++) {
        address quoteAsset = QuoteAssets[i];
        (priceFoundTwo, assetTwoPrice) = _getDirectOrInversePrice(
          _assetTwo,
          quoteAsset
        );
        if (priceFoundTwo) {
          quote_assetTwo = quoteAsset;
        }
      }
    } else {
      priceFoundTwo = true;
    }
    if (priceFoundOne && priceFoundTwo) {
      if (quote_assetOne == quote_assetTwo) {
        return (true, assetOnePrice.preciseDiv(assetTwoPrice));
      } else {
        (
          bool quote_assetOne_price_found,
          uint256 quote_assetOne_price
        ) = _getDirectOrInversePrice(quote_assetOne, masterQuoteAsset);
        require(
          quote_assetOne_price_found,
          "PriceOracleV2._getPriceFromMasterQuote: quote_assetOne price not found"
        );
        if (quote_assetTwo == masterQuoteAsset) {
          return (true, quote_assetOne_price.preciseMul(assetOnePrice));
        }
      }
    }
    return (false, 0);
  }

  /**
   * Scan adapters to see if one or more of the assets needs external protocol data to be priced. If
   * does not exist return false and no price.
   *
   * @param _assetOne         Address of first asset in pair
   * @param _assetTwo         Address of second asset in pair
   * @return bool             Boolean indicating if oracle exists
   * @return uint256          Price of asset pair to 18 decimal precision (if exists, otherwise 0)
   */
  function _getPriceFromAdapters(
    address _assetOne,
    address _assetTwo
  ) internal view returns (bool, uint256) {
    for (uint256 i = 0; i < adapters.length; i++) {
      (bool priceFound, uint256 price) = IOracleAdapter(adapters[i]).getPrice(
        _assetOne,
        _assetTwo
      );

      if (priceFound) {
        return (priceFound, price);
      }
    }

    return (false, 0);
  }

  /**
   * Calculate inverse price of passed oracle. The inverse price is 1 (or 1e18) / inverse price
   *
   * @param _inverseOracle        Address of oracle to invert
   * @return uint256              Inverted price of asset pair to 18 decimal precision
   */
  function _calculateInversePrice(
    IOracle _inverseOracle
  ) internal view returns (uint256) {
    uint256 inverseValue = _inverseOracle.read();

    return PreciseUnitMath.preciseUnit().preciseDiv(inverseValue);
  }
}