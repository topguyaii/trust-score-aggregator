// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IACPHook
 * @notice Interface for ERC-8183 hooks
 * @dev Hooks receive callbacks before and after job lifecycle actions
 *
 * Per ERC-8183 specification:
 * - beforeAction: Called before each hookable function
 * - afterAction: Called after each hookable function
 * - claimRefund is deliberately NOT hookable for recovery assurance
 */
interface IACPHook {
    /**
     * @notice Called before a job action executes
     * @param jobId The job identifier
     * @param selector The function selector being called (e.g., createJob, fund, submit)
     * @param data ABI-encoded function parameters
     * @dev Revert to block the action
     */
    function beforeAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external;

    /**
     * @notice Called after a job action executes
     * @param jobId The job identifier
     * @param selector The function selector that was called
     * @param data ABI-encoded function parameters
     * @dev Can emit events, trigger side effects, but cannot undo the action
     */
    function afterAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external;
}
