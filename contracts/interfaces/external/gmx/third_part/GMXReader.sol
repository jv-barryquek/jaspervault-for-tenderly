pragma solidity ^0.6.10;

contract GMXReader {
    function getPositions(
        address _vault,
        address _account,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) external view returns (uint256[] memory) {
        uint256[] memory p = new uint256[](9);
        p[0] = 99009686402000000000000000000000;
        p[1] = 9900990313598000000000000000000;
        p[2] = 26806880000000000000000000000000000;
        p[3] = 359657;
        p[4] = 1;
        p[5] = 0;
        p[6] = 1685942799;
        p[7] = 0;
        p[8] = 8033238777670135427919996657;
        return p;
    }
}
