// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

/// @title Extended factory interface for FreeTheBlocks-specific features
interface IFreeTheBlocksFactory {
    function treasury() external view returns (address);
    function feeCollector() external view returns (address);
    function pendingOwner() external view returns (address);
    function defaultProtocolFee() external view returns (uint8);
}
