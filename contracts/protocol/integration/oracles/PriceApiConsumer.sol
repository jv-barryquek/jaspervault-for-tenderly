// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2"; // note: necessary for decoding and encoding struct[] types

import {Chainlink} from "@chainlink/contracts/src/v0.6/Chainlink.sol";
import {ChainlinkClient} from "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import {Owned} from "@chainlink/contracts/src/v0.6/Owned.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.6/interfaces/LinkTokenInterface.sol";
import {IGenericAsset} from "../../../interfaces/external/IGenericAsset.sol";
import {PreciseUnitMath} from "../../../lib/PreciseUnitMath.sol";

/**
 * @title PriceApiConsumer
 * @author JasperVault
 *
 * Contract that extends ChainlinkClient to make requests to a dedicated external API
 * Used + OWNED by PriceOracleV2 to query JasperVault's dedicated API that returns price data for a large number of assets relative to some master asset (fixed by the API)
 * Ideally, we should get the price data from system components (i.e., the Oracles and Adapters registered with PriceOracle), so this ApiConsumer should only be used to get asset-pair pricing as a last resort.
 * This ApiConsumer is not intended as a 'generic' API consumer, but only makes a very particular request to a particular endpoint.
 * We embrace this trade-off to make it straightforward for the PriceOracleV2 to control how its instance of this contract is used.
 * ! < === Still To Be Tested === >
 */
contract PriceApiConsumer is ChainlinkClient, Owned {
  using PreciseUnitMath for uint256;
  /* ============ Modifiers  ============ */
  modifier onlyOperatorNode(address _nodeAddress) {
    require(
      _nodeAddress != address(0),
      "Only JVault chainlink node can initiate API req"
    );
    _;
  }
  /* ============ Types  ============ */
  using Chainlink for Chainlink.Request;

  // * shape of data expected from API; API should return data that can be decoded an array of such structs
  struct AssetToMasterAssetPrice {
    address asset;
    uint256 priceToMasterAsset; // 18 decimal places
    // * the API should be designed to specify prices relative to a single master asset; calculation of asset-pair prices is done in fulfillPriceRequest after receiving the data
  }

  /* ============ Events  ============ */
  event PriceRequestMade(bytes32 requestId);
  event PriceResponseReceived(bytes32 requestId, uint256 lengthOfResponseArray);
  event PricesUpdated(bytes32 requestId, uint256 blockTimeStamp);

  /* ============ State Variables  ============ */
  // * Id of Network deploying the PriceApiConsumer on; used as query parameter for API request
  uint256 public NETWORK_ID;

  // * Mapping stores assets and their prices relative to some master asset; this master asset is determined by our API which we call
  mapping(address => uint256) public prices;

  // * Timestamp for when the prices mapping was last updated
  uint256 public lastUpdated;

  // * Address of on-chain account that is used by Chainlink node to sign and send responses; auto-generated when chainlink node is started. Used to restrict calls to initiateRequestForPrices
  address public chainlinkNodeAddress;

  // * Id of Chainlink Operator job that supports the data type our contract needs to consume.
  bytes32 private operatorJobId;

  // * Fee to pay Chainlink Oracle Node for executing job of fetching price data from external API.
  uint256 private oracleNodeFee; // varies by network and operator job

  // * String specifiying the endpoint
  string externalApiEndpoint;
  // * String for HTTP method to make request to endpoint with; lowercase like in the Chainlink docs examples for making requests
  string httpMethodLowerCase;
  // * String specifying the 'path' to get the particular data point (in this case, price) by 'indexing' the response object returned by the external API
  string pathForPricesData; // should be something like 'prices', accessing an array of objects resembling AssetPairPriceResponse

  /**
   * Set state variables and store asset addresses in mappings
   * Should be constructed by PriceOracleV2 in our system
   * @param _chainLinkTokenAddress   Address of LINK token for operator payment
   * @param _chainLinkNodeAddress   Address of on-chain account that chainlink node uses to sign and send responses
   * @param _chainLinkOperator      Address of Operator contract that functions as Oracle
   * @param _operatorJobId         Id of Operator job that makes the API request we want
   * @param _linkTokenDivisibility  Decimal offset for LINK token on specific network and operator job
   */
  constructor(
    uint256 _networkId,
    address _chainLinkTokenAddress,
    address _chainLinkNodeAddress,
    address _chainLinkOperator,
    bytes32 _operatorJobId,
    uint256 _linkTokenDivisibility, // varies by network and job
    string memory _httpMethodLowerCase,
    string memory _endpointUrl,
    string memory _pathForPriceData
  ) public {
    require(_networkId != 0, "network Id cannot be 0");
    require(
      _chainLinkTokenAddress != address(0),
      "Link token address cannot be 0x0"
    );
    require(
      _chainLinkNodeAddress != address(0),
      "CL Node address cannot be 0x0"
    );
    require(_chainLinkOperator != address(0), "Operator address cannot be 0x0");
    require(bytes(_endpointUrl).length > 0, "endpoint must be specified");
    require(
      bytes(_httpMethodLowerCase).length > 0,
      "http method must be specified"
    );
    require(
      bytes(_pathForPriceData).length > 0,
      "path for prices data must be specified"
    );
    NETWORK_ID = _networkId;
    setChainlinkToken(_chainLinkTokenAddress);
    setChainlinkOracle(_chainLinkOperator);
    chainlinkNodeAddress = _chainLinkNodeAddress;
    operatorJobId = _operatorJobId;
    oracleNodeFee = (1 * _linkTokenDivisibility) * 10;
    httpMethodLowerCase = _httpMethodLowerCase;
    externalApiEndpoint = _endpointUrl;
    pathForPricesData = _pathForPriceData;
  }

  /* ============ External Functions ============ */
  /**
   * @dev Function for PriceOracle(V2) to call as a last resort to get price data on an asset pair
   * @param _assetOne   Address of first asset in pairing
   * @param _assetTwo   Address of second asset in pairing
   * @return uint256    The calculatedPairPrice derived by dividing their relative-to-master-asset prices; result is rounded down. The master asset their prices are relative to is fixed by the API we fetch the prices from.
   */
  function getCalculatedPairPrice(
    address _assetOne,
    address _assetTwo
  ) external view onlyOwner returns (uint256) {
    require(prices[_assetOne] != 0, "no stored price for asset one");
    require(prices[_assetTwo] != 0, "no stored price for asset two");
    return prices[_assetOne].preciseDiv(prices[_assetTwo]);
  }

  /**
   * @dev Function to initiate request to our dedicated API to fetch price data. Should be called at a set time interval by our Chainlink Node by its job
   * emits PriceRequestMade event after done
   */
  function initiateRequestForPrices() external onlyOperatorNode(msg.sender) {
    // ! note: unsure whether modifier added will allow the cron job defined on the node to call this every 1 min
    bytes32 requestId = _requestPriceFromExternalApi();
    emit PriceRequestMade(requestId);
  }

  /**
   * Callback function for (Chainlink) oracle node to pass response to contract
   * @param _requestId   Id of request that is being fulfilled
   * @param _arrayOfAssetPrices   Encoded AssetToMasterAssetPrice[], specifying the price of assets relative to some master asset (fixed and determined by the API)
   */
  function fulfillPriceRequest(
    bytes32 _requestId,
    bytes memory _arrayOfAssetPrices
  ) external recordChainlinkFulfillment(_requestId) {
    emit PriceResponseReceived(_requestId, _arrayOfAssetPrices.length);
    AssetToMasterAssetPrice[] memory res = abi.decode(
      _arrayOfAssetPrices,
      (AssetToMasterAssetPrice[])
    );
    for (uint i; i < res.length; i++) {
      prices[res[i].asset] = res[i].priceToMasterAsset;
    }
    lastUpdated = block.timestamp;
    emit PricesUpdated(_requestId, lastUpdated);
  }

  /**
   * OnlyOwner-- i.e, PriceOracleV2
   * Allow withdraw of Link tokens from the contract
   */
  function withdrawLink() external onlyOwner {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(
      link.transfer(msg.sender, link.balanceOf(address(this))),
      "Unable to transfer"
    );
  }

  /* ============ Internal Functions ============ */

  /**
   * Get the prices of assets relative to some dedicated master asset from our dedicated API, so we can calculate requested pair prices in getCalculatedPairPrice
   * Ideally, we should get price data from system oracles and adapters that aggregate many sources, so we only call this function in `getPrice()` as a last resort after trying the various oracles/adapters we have.
   *
   * @return requestId         Id of Chainlink Request sent to external API
   */
  function _requestPriceFromExternalApi() internal returns (bytes32 requestId) {
    Chainlink.Request memory req = buildChainlinkRequest(
      operatorJobId,
      address(this),
      this.fulfillPriceRequest.selector
    );
    req.add(httpMethodLowerCase, externalApiEndpoint);
    req.add("path", pathForPricesData);
    req.addUint("networkId", NETWORK_ID);

    // * send the request and return the requestId
    return sendChainlinkRequest(req, oracleNodeFee);
  }
}
