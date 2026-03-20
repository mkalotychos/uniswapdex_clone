// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './NoDelegateCall.sol';

interface IFreeTheBlocksPoolDeployer {
    function deploy(address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
        external
        returns (address pool);
    function setFactoryAddress(address _factory) external;
}

/// @title FreeTheBlocks DEX factory
/// @notice Deploys FreeTheBlocks pools (via external PoolDeployer) and manages ownership,
///         treasury, and protocol fee control.
contract FreeTheBlocksFactory is IUniswapV3Factory, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    address public override owner;

    /// @notice The external PoolDeployer that holds Pool bytecode and performs CREATE2
    address public poolDeployer;

    /// @notice Address that receives protocol fees (treasury / multisig)
    address public treasury;

    /// @notice Address authorized to collect protocol fees from pools (FeeDistributor contract)
    address public feeCollector;

    /// @notice Pending owner for 2-step ownership transfer
    address public pendingOwner;

    /// @notice Default protocol fee numerator applied to new pools (e.g. 6 = 1/6 of LP fees)
    /// @dev Packed as feeProtocol0 in low 4 bits, feeProtocol1 in high 4 bits
    uint8 public defaultProtocolFee;

    /// @inheritdoc IUniswapV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IUniswapV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    event TreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event FeeCollectorChanged(address indexed oldCollector, address indexed newCollector);
    event PendingOwnerSet(address indexed pendingOwner);

    constructor(address _poolDeployer) {
        owner = msg.sender;
        treasury = msg.sender;
        poolDeployer = _poolDeployer;
        defaultProtocolFee = 6 + (6 << 4);
        emit OwnerChanged(address(0), msg.sender);

        IFreeTheBlocksPoolDeployer(_poolDeployer).setFactoryAddress(address(this));

        feeAmountTickSpacing[100] = 1;
        emit FeeAmountEnabled(100, 1);
        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        require(getPool[token0][token1][fee] == address(0));
        pool = IFreeTheBlocksPoolDeployer(poolDeployer).deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @notice Sets the treasury address that receives protocol fees
    function setTreasury(address _treasury) external {
        require(msg.sender == owner, 'NOT_OWNER');
        require(_treasury != address(0), 'ZERO_ADDRESS');
        emit TreasuryChanged(treasury, _treasury);
        treasury = _treasury;
    }

    /// @notice Sets the default protocol fee for new pools (packed: fee0 + fee1 << 4)
    function setDefaultProtocolFee(uint8 _fee) external {
        require(msg.sender == owner, 'NOT_OWNER');
        uint8 fee0 = _fee % 16;
        uint8 fee1 = _fee >> 4;
        require(
            (fee0 == 0 || (fee0 >= 4 && fee0 <= 10)) &&
            (fee1 == 0 || (fee1 >= 4 && fee1 <= 10)),
            'INVALID_FEE'
        );
        defaultProtocolFee = _fee;
    }

    /// @notice Sets the fee collector address (typically FeeDistributor contract)
    function setFeeCollector(address _feeCollector) external {
        require(msg.sender == owner, 'NOT_OWNER');
        emit FeeCollectorChanged(feeCollector, _feeCollector);
        feeCollector = _feeCollector;
    }

    /// @notice Initiates 2-step ownership transfer
    function setPendingOwner(address _pendingOwner) external {
        require(msg.sender == owner, 'NOT_OWNER');
        pendingOwner = _pendingOwner;
        emit PendingOwnerSet(_pendingOwner);
    }

    /// @notice Completes 2-step ownership transfer — must be called by pending owner
    function acceptOwner() external {
        require(msg.sender == pendingOwner, 'NOT_PENDING');
        emit OwnerChanged(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /// @inheritdoc IUniswapV3Factory
    /// @dev Kept for interface compatibility but replaced by 2-step transfer.
    ///      Directly sets owner (use setPendingOwner + acceptOwner for safety).
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        require(msg.sender == owner);
        require(fee < 1000000);
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
