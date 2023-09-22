pragma solidity ^0.8.0;
import "openzeppelin-contracts-V4/governance/TimelockController.sol";

contract JasperContractOwner is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}
}
