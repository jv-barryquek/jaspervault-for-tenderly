/**
 * @notice This script will contain the addresses/constants for various tokens on various networks. Took the values and tokens from 王志's awesome python-sdk. Thanks 王志.
 */

/**
 * @template T
 * @typedef {Object.<string,T>} EthereumTokenAddresses
 * @example `EthereumTokenAddresses["DAI"]` to get the address of the `DAI` token
 */
const EthereumTokenAddresses = {
  USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
  sDAI: "0x83F20F44975D03b1b09e64809B757c47f942BEeA",
  spsDAI: "0x78f897F0fE2d3B5690EbAe7f19862DEacedF10a7",
  spDAI: "0x4DEDf26112B3Ec8eC46e7E31EA5e123490B05B8B",
  spWETH: "0x59cD1C87501baa753d0B5B5Ab5D8416A45cD71DB",
  USDT: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  aWETH: "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e",
  WBTC: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
  aETH: "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e",
  aWBTC: "0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656",
  stETH: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  astETH: "0x1982b2F5814301d4e9a8b0201555376e62F82428",
  wstETH: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
  spwstETH: "0x12B54025C112Aa61fAce2CDB7118740875A566E9",
  UNI: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984",
  LDO: "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32",
  MKR: "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2",
  AAVE: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9",
  SNX: "0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F",
  RPL: "0xD33526068D116cE69F19A9ee46F0bd304F21A51f",
  COMP: "0xc00e94Cb662C3520282E6f5717214004A7f26888",
  YFI: "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e",
  BAL: "0xba100000625a3754423978a60c9317c58a424e3D",
  LRC: "0xBBbbCA6A901c926F240b89EacB641d8Aec7AEafD",
};

/**
 * @template T
 * @typedef {Object.<string,T>} PolygonTokenAddresses
 * @example `PolygonTokenAddresses["MATIC"]` to get the address of the `MATIC` token
 */
const PolygonTokenAddresses = {
  MATIC: "0x0000000000000000000000000000000000001010",
  QUICK: "0xB5C064F955D8e7F38fE0460C556a72987494eE17",
  USDC: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
  USDT: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
  DAI: "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063",
  UNI: "0xb33eaad8d922b1083446dc23f610c2567fb5180f",
  AAVE: "0xd6df932a45c0f255f85145f286ea0b292b21c90b",
  WMATIC: "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
  WETH: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
  WBTC: "0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6",
  aWETH: "0x28424507fefb6f7f8E9D3860F56504E4e5f5f390",
  aWBTC: "0x5c2ed810328349100A66B82b78a1791B101C9D61",
  wstETH: "0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD",
  awstETH: "0xf59036CAEBeA7dC4b86638DFA2E3C97dA9FcCd40",
  LINK: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39",
};

/**
 * @template T
 * @typedef {Object.<string,T>} ArbitrumTokenAddresses
 * @example `ArbitrumTokenAddresses["WETH"]` to get the address of the `WETH` token
 */
const ArbitrumTokenAddresses = {
  USDC: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
  WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
  aWETH: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8",
  WBTC: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
  aWBTC: "0x078f358208685046a11C85e8ad32895DED33A249",
  DAI: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
  wstETH: "0x5979D7b546E38E414F7E9822514be443A4800529",
  awstETH: "0x513c7E3a9c69cA3e22550eF58AC1C0088e918FFf",
  sGLP: "0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE",
  GMX: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
  sbfGMX: "0xd2D1162512F927a7e282Ef43a362659E4F2a728F",
  UNI: "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0",
  LINK: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
  LDO: "0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60",
  ARB: "0x912CE59144191C1204E64559FE8253a0e49E6548",
  CRV: "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978",
  COMP: "0x354A6dA3fcde098F8389cad84b0182725c6C91dE",
  LRC: "0x46d0cE7de6247b0A95f67b43B589b4041BaE7fbE",
  YFI: "0x82e3A8F066a6989666b031d916c43672085b1582",
  BAL: "0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8",
  SUSHI: "0xd4d42F0b6DEF4CE0383636770eF773390d85c61A",
};

module.exports = {
  EthereumTokenAddresses,
  PolygonTokenAddresses,
  ArbitrumTokenAddresses,
};
