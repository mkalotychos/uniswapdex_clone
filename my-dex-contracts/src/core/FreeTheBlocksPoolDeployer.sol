// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';

import './FreeTheBlocksPool.sol';

/// @title FreeTheBlocks Pool Deployer
/// @notice Standalone deployer that holds the Pool bytecode so the Factory stays under 24KB (EIP-170).
///         Also acts as a facade: periphery contracts treat this address as "factory" for CREATE2
///         pool-address computation, and getPool/createPool calls are forwarded to the real Factory.
contract FreeTheBlocksPoolDeployer is IUniswapV3PoolDeployer {
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @inheritdoc IUniswapV3PoolDeployer
    Parameters public override parameters;

    /// @notice The real FreeTheBlocksFactory that owns pool-creation logic
    address public factoryAddress;

    /// @dev One-time link to the factory (called by the factory constructor)
    function setFactoryAddress(address _factory) external {
        require(factoryAddress == address(0), 'ALREADY_SET');
        factoryAddress = _factory;
    }

    // ── Facade: periphery calls these via IUniswapV3Factory(factory).* ──

    function owner() external view returns (address) {
        return IUniswapV3Factory(factoryAddress).owner();
    }

    function feeAmountTickSpacing(uint24 fee) external view returns (int24) {
        return IUniswapV3Factory(factoryAddress).feeAmountTickSpacing(fee);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return IUniswapV3Factory(factoryAddress).getPool(tokenA, tokenB, fee);
    }

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        return IUniswapV3Factory(factoryAddress).createPool(tokenA, tokenB, fee);
    }

    // ── Pool deployment (only callable by Factory.createPool) ──

    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) external returns (address pool) {
        require(msg.sender == factoryAddress, 'NOT_FACTORY');
        parameters = Parameters({factory: factory, token0: token0, token1: token1, fee: fee, tickSpacing: tickSpacing});
        pool = address(new FreeTheBlocksPool{salt: keccak256(abi.encode(token0, token1, fee))}());
        delete parameters;
    }
}
