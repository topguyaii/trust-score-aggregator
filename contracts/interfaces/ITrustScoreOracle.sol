// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITrustScoreOracle
 * @notice Interface for querying agent trust scores
 * @dev Used by ERC-8183 hooks to gate commerce based on reputation
 *
 * Trust scores are computed off-chain by indexing ERC-8004 reputation
 * events and applying time-decayed weighted aggregation.
 */
interface ITrustScoreOracle {
    // ============ Events ============

    /// @notice Emitted when a score is updated
    event ScoreUpdated(bytes32 indexed agentId, uint256 oldScore, uint256 newScore);

    /// @notice Emitted when a score is queried (for tracking)
    event ScoreQueried(bytes32 indexed agentId, address indexed querier, uint256 score);

    // ============ Score Queries ============

    /**
     * @notice Get trust score by agent ID (bytes32)
     * @param agentId The agent's ERC-8004 identity
     * @return score Trust score (0-100)
     */
    function getScore(bytes32 agentId) external view returns (uint256 score);

    /**
     * @notice Get trust score by wallet address
     * @param agent The agent's wallet address
     * @return score Trust score (0-100)
     */
    function getScoreByAddress(address agent) external view returns (uint256 score);

    /**
     * @notice Check if an agent's score meets a threshold
     * @param agent The agent's wallet address
     * @param threshold Minimum required score
     * @return meets Whether score >= threshold
     */
    function meetsThreshold(address agent, uint256 threshold) external view returns (bool meets);

    /**
     * @notice Get multiple scores in batch
     * @param agents Array of agent addresses
     * @return scores Array of trust scores
     */
    function getScoresBatch(address[] calldata agents) external view returns (uint256[] memory scores);

    // ============ Score Updates (Owner/Updater Only) ============

    /**
     * @notice Update an agent's trust score
     * @param agentId The agent's ERC-8004 identity
     * @param score New trust score (0-100)
     */
    function updateScore(bytes32 agentId, uint256 score) external;

    /**
     * @notice Update score by wallet address
     * @param agent The agent's wallet address
     * @param score New trust score (0-100)
     */
    function updateScoreByAddress(address agent, uint256 score) external;

    /**
     * @notice Batch update multiple scores
     * @param agents Array of agent addresses
     * @param scores Array of new scores
     */
    function updateScoresBatch(address[] calldata agents, uint256[] calldata scores) external;

    // ============ Metadata ============

    /**
     * @notice Get the timestamp when a score was last updated
     * @param agent The agent's wallet address
     * @return timestamp Last update timestamp
     */
    function lastUpdated(address agent) external view returns (uint256 timestamp);

    /**
     * @notice Get score with metadata
     * @param agent The agent's wallet address
     * @return score Trust score (0-100)
     * @return updatedAt Last update timestamp
     * @return feedbackCount Number of feedback events
     */
    function getScoreWithMetadata(address agent) external view returns (
        uint256 score,
        uint256 updatedAt,
        uint256 feedbackCount
    );
}
