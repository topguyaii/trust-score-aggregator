// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title TrustScoreOracleV2
 * @notice Enhanced on-chain oracle for ERC-8004 agent trust scores
 * @dev Adds address-based queries for ERC-8183 hook integration
 *
 * Features:
 * - Query by bytes32 agentId (ERC-8004 standard)
 * - Query by wallet address (ERC-8183 hook compatibility)
 * - Free view functions for hooks (hooks need fast, free access)
 * - Paid queries for external callers
 * - Batch operations for efficiency
 */
contract TrustScoreOracleV2 is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ Structs ============

    /// @notice Score data for an agent
    struct AgentScore {
        uint256 score;          // Trust score (0-100, scaled by 100 = 0-10000)
        uint256 lastUpdated;    // Timestamp of last update
        uint256 feedbackCount;  // Number of feedback events indexed
        bool exists;            // Whether score has been set
    }

    // ============ State Variables ============

    /// @notice Mapping of agent ID (bytes32) to score data
    mapping(bytes32 => AgentScore) public scoresByAgentId;

    /// @notice Mapping of wallet address to agent ID
    mapping(address => bytes32) public addressToAgentId;

    /// @notice Mapping of wallet address to score (direct lookup for hooks)
    mapping(address => AgentScore) public scoresByAddress;

    /// @notice Fee required per paid query (default 0.001 ETH)
    uint256 public queryFee;

    /// @notice Total revenue accumulated
    uint256 public totalRevenue;

    /// @notice Total queries processed
    uint256 public totalQueries;

    /// @notice Authorized updaters (can update scores)
    mapping(address => bool) public authorizedUpdaters;

    /// @notice Authorized hooks (free queries)
    mapping(address => bool) public authorizedHooks;

    // ============ Events ============

    event ScoreUpdated(bytes32 indexed agentId, address indexed agent, uint256 oldScore, uint256 newScore);
    event ScoreQueried(bytes32 indexed agentId, address indexed querier, uint256 score);
    event AddressScoreQueried(address indexed agent, address indexed querier, uint256 score);
    event QueryFeeUpdated(uint256 oldFee, uint256 newFee);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event HookAuthorized(address indexed hook, bool authorized);
    event AgentRegistered(address indexed agent, bytes32 indexed agentId);

    // ============ Errors ============

    error InsufficientFee();
    error ScoreOutOfRange();
    error ArrayLengthMismatch();
    error Unauthorized();
    error WithdrawFailed();
    error RefundFailed();
    error AgentNotRegistered();

    // ============ Modifiers ============

    modifier onlyUpdater() {
        if (!authorizedUpdaters[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param owner_ The contract owner address
     * @param queryFee_ Initial query fee in wei
     */
    function initialize(address owner_, uint256 queryFee_) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        queryFee = queryFee_;
        authorizedUpdaters[owner_] = true;
    }

    // ============ Free View Functions (For Hooks) ============

    /**
     * @notice Get trust score by wallet address (FREE for hooks)
     * @param agent The agent's wallet address
     * @return score Trust score (0-100)
     */
    function getScoreByAddress(address agent) external view returns (uint256 score) {
        return scoresByAddress[agent].score / 100; // Convert from 10000 to 100 scale
    }

    /**
     * @notice Check if an agent meets a trust threshold (FREE)
     * @param agent The agent's wallet address
     * @param threshold Minimum required score (0-100)
     * @return meets Whether score >= threshold
     */
    function meetsThreshold(address agent, uint256 threshold) external view returns (bool meets) {
        return scoresByAddress[agent].score >= threshold * 100;
    }

    /**
     * @notice Get multiple scores by address (FREE)
     * @param agents Array of agent addresses
     * @return scores Array of trust scores (0-100)
     */
    function getScoresByAddressBatch(address[] calldata agents) external view returns (uint256[] memory scores) {
        scores = new uint256[](agents.length);
        for (uint256 i = 0; i < agents.length; i++) {
            scores[i] = scoresByAddress[agents[i]].score / 100;
        }
    }

    /**
     * @notice Get score with full metadata (FREE)
     * @param agent The agent's wallet address
     * @return score Trust score (0-100)
     * @return lastUpdated Last update timestamp
     * @return feedbackCount Number of feedback events
     * @return exists Whether score exists
     */
    function getScoreWithMetadata(address agent) external view returns (
        uint256 score,
        uint256 lastUpdated,
        uint256 feedbackCount,
        bool exists
    ) {
        AgentScore storage s = scoresByAddress[agent];
        return (s.score / 100, s.lastUpdated, s.feedbackCount, s.exists);
    }

    /**
     * @notice Get score by agent ID (FREE view)
     * @param agentId The agent's ERC-8004 identifier
     * @return score Trust score (0-10000)
     * @return lastUpdated Last update timestamp
     * @return exists Whether score exists
     */
    function getScoreView(bytes32 agentId) external view returns (
        uint256 score,
        uint256 lastUpdated,
        bool exists
    ) {
        AgentScore storage s = scoresByAgentId[agentId];
        return (s.score, s.lastUpdated, s.exists);
    }

    // ============ Paid Query Functions ============

    /**
     * @notice Get trust score by agent ID (PAID)
     * @param agentId The agent's identifier
     * @return score The trust score (0-10000)
     * @return lastUpdated Timestamp of last update
     */
    function getScore(bytes32 agentId) external payable nonReentrant returns (
        uint256 score,
        uint256 lastUpdated
    ) {
        if (msg.value < queryFee) revert InsufficientFee();

        AgentScore storage agentScore = scoresByAgentId[agentId];

        totalRevenue += queryFee;
        totalQueries += 1;

        emit ScoreQueried(agentId, msg.sender, agentScore.score);

        _refundExcess(queryFee);

        return (agentScore.score, agentScore.lastUpdated);
    }

    /**
     * @notice Batch query scores by agent ID (PAID)
     * @param agentIds Array of agent identifiers
     * @return scores Array of trust scores
     * @return lastUpdates Array of last update timestamps
     */
    function getScoreBatch(bytes32[] calldata agentIds) external payable nonReentrant returns (
        uint256[] memory scores,
        uint256[] memory lastUpdates
    ) {
        uint256 totalFee = queryFee * agentIds.length;
        if (msg.value < totalFee) revert InsufficientFee();

        scores = new uint256[](agentIds.length);
        lastUpdates = new uint256[](agentIds.length);

        for (uint256 i = 0; i < agentIds.length; i++) {
            AgentScore storage s = scoresByAgentId[agentIds[i]];
            scores[i] = s.score;
            lastUpdates[i] = s.lastUpdated;

            emit ScoreQueried(agentIds[i], msg.sender, s.score);
        }

        totalRevenue += totalFee;
        totalQueries += agentIds.length;

        _refundExcess(totalFee);

        return (scores, lastUpdates);
    }

    // ============ Score Update Functions (Updater Only) ============

    /**
     * @notice Register agent address to agent ID mapping
     * @param agent The agent's wallet address
     * @param agentId The agent's ERC-8004 identifier
     */
    function registerAgent(address agent, bytes32 agentId) external onlyUpdater {
        addressToAgentId[agent] = agentId;
        emit AgentRegistered(agent, agentId);
    }

    /**
     * @notice Update trust score by agent ID
     * @param agentId The agent's identifier
     * @param score New trust score (0-10000)
     */
    function updateScore(bytes32 agentId, uint256 score) external onlyUpdater {
        if (score > 10000) revert ScoreOutOfRange();

        uint256 oldScore = scoresByAgentId[agentId].score;

        scoresByAgentId[agentId] = AgentScore({
            score: score,
            lastUpdated: block.timestamp,
            feedbackCount: scoresByAgentId[agentId].feedbackCount + 1,
            exists: true
        });

        emit ScoreUpdated(agentId, address(0), oldScore, score);
    }

    /**
     * @notice Update trust score by wallet address
     * @param agent The agent's wallet address
     * @param score New trust score (0-10000)
     */
    function updateScoreByAddress(address agent, uint256 score) external onlyUpdater {
        if (score > 10000) revert ScoreOutOfRange();

        uint256 oldScore = scoresByAddress[agent].score;

        scoresByAddress[agent] = AgentScore({
            score: score,
            lastUpdated: block.timestamp,
            feedbackCount: scoresByAddress[agent].feedbackCount + 1,
            exists: true
        });

        // Also update by agentId if registered
        bytes32 agentId = addressToAgentId[agent];
        if (agentId != bytes32(0)) {
            scoresByAgentId[agentId] = scoresByAddress[agent];
        }

        emit ScoreUpdated(agentId, agent, oldScore, score);
    }

    /**
     * @notice Batch update scores by address
     * @param agents Array of agent addresses
     * @param scores Array of new scores (0-10000)
     */
    function updateScoresBatch(
        address[] calldata agents,
        uint256[] calldata scores
    ) external onlyUpdater {
        if (agents.length != scores.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < agents.length; i++) {
            if (scores[i] > 10000) revert ScoreOutOfRange();

            uint256 oldScore = scoresByAddress[agents[i]].score;

            scoresByAddress[agents[i]] = AgentScore({
                score: scores[i],
                lastUpdated: block.timestamp,
                feedbackCount: scoresByAddress[agents[i]].feedbackCount + 1,
                exists: true
            });

            bytes32 agentId = addressToAgentId[agents[i]];
            if (agentId != bytes32(0)) {
                scoresByAgentId[agentId] = scoresByAddress[agents[i]];
            }

            emit ScoreUpdated(agentId, agents[i], oldScore, scores[i]);
        }
    }

    /**
     * @notice Update score with feedback count
     * @param agent The agent's wallet address
     * @param score New trust score (0-10000)
     * @param feedbackCount Total feedback events
     */
    function updateScoreWithMetadata(
        address agent,
        uint256 score,
        uint256 feedbackCount
    ) external onlyUpdater {
        if (score > 10000) revert ScoreOutOfRange();

        uint256 oldScore = scoresByAddress[agent].score;

        scoresByAddress[agent] = AgentScore({
            score: score,
            lastUpdated: block.timestamp,
            feedbackCount: feedbackCount,
            exists: true
        });

        bytes32 agentId = addressToAgentId[agent];
        if (agentId != bytes32(0)) {
            scoresByAgentId[agentId] = scoresByAddress[agent];
        }

        emit ScoreUpdated(agentId, agent, oldScore, score);
    }

    // ============ Admin Functions ============

    /**
     * @notice Authorize/deauthorize an updater
     * @param updater Address to authorize
     * @param authorized Whether to authorize
     */
    function setUpdater(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    /**
     * @notice Authorize/deauthorize a hook for free queries
     * @param hook Hook address
     * @param authorized Whether to authorize
     */
    function setHook(address hook, bool authorized) external onlyOwner {
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    /**
     * @notice Set query fee
     * @param newFee New fee in wei
     */
    function setQueryFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = queryFee;
        queryFee = newFee;
        emit QueryFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Withdraw accumulated fees
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert WithdrawFailed();

        (bool success, ) = owner().call{value: balance}("");
        if (!success) revert WithdrawFailed();

        emit FundsWithdrawn(owner(), balance);
    }

    // ============ Internal Functions ============

    function _refundExcess(uint256 fee) internal {
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert RefundFailed();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}
}
