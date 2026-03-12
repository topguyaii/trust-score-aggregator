// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IACPHook.sol";
import "../interfaces/ITrustScoreOracle.sol";

/**
 * @title TrustGateHook
 * @notice ERC-8183 hook that gates jobs based on trust scores from ERC-8004
 * @dev Queries TrustScoreOracle to enforce minimum trust requirements
 *
 * Integration with Virtual Protocol ACP:
 * - Deployed as a hook for ACP Job contracts
 * - Prevents low-reputation agents from accepting jobs
 * - Can enforce tiered requirements based on job budget
 */
contract TrustGateHook is IACPHook {
    // ============ Constants ============

    /// @notice Function selector for createJob
    bytes4 public constant CREATE_JOB_SELECTOR = bytes4(keccak256("createJob(address,address,uint256,string,address)"));

    /// @notice Function selector for setProvider
    bytes4 public constant SET_PROVIDER_SELECTOR = bytes4(keccak256("setProvider(uint256,address,bytes)"));

    /// @notice Function selector for fund
    bytes4 public constant FUND_SELECTOR = bytes4(keccak256("fund(uint256,uint256,bytes)"));

    /// @notice Maximum trust score (100 = 100%)
    uint256 public constant MAX_SCORE = 100;

    // ============ State Variables ============

    /// @notice Trust score oracle (queries ERC-8004 data)
    ITrustScoreOracle public oracle;

    /// @notice Default minimum trust score required (0-100)
    uint256 public defaultMinTrustScore;

    /// @notice Contract owner
    address public owner;

    /// @notice Whether the hook is paused
    bool public paused;

    // ============ Tiered Requirements ============

    /// @notice Budget threshold for medium trust requirement
    uint256 public mediumBudgetThreshold;

    /// @notice Budget threshold for high trust requirement
    uint256 public highBudgetThreshold;

    /// @notice Trust score required for medium budget jobs
    uint256 public mediumBudgetMinScore;

    /// @notice Trust score required for high budget jobs
    uint256 public highBudgetMinScore;

    // ============ Per-Client Overrides ============

    /// @notice Custom minimum scores per client
    mapping(address => uint256) public clientMinScores;

    /// @notice Whether client has custom score set
    mapping(address => bool) public hasCustomScore;

    // ============ Whitelist/Blacklist ============

    /// @notice Providers that bypass trust checks (whitelisted)
    mapping(address => bool) public whitelistedProviders;

    /// @notice Providers that are always blocked (blacklisted)
    mapping(address => bool) public blacklistedProviders;

    // ============ Events ============

    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event DefaultMinScoreUpdated(uint256 oldScore, uint256 newScore);
    event TieredThresholdsUpdated(
        uint256 mediumThreshold,
        uint256 highThreshold,
        uint256 mediumScore,
        uint256 highScore
    );
    event ClientMinScoreSet(address indexed client, uint256 minScore);
    event ProviderWhitelisted(address indexed provider, bool whitelisted);
    event ProviderBlacklisted(address indexed provider, bool blacklisted);
    event JobGated(
        uint256 indexed jobId,
        address indexed provider,
        uint256 score,
        uint256 requiredScore,
        bool allowed
    );
    event Paused(bool isPaused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ Errors ============

    error Unauthorized();
    error InvalidOracle();
    error InvalidScore();
    error ProviderBlacklisted(address provider);
    error InsufficientTrustScore(address provider, uint256 score, uint256 required);
    error HookPaused();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert HookPaused();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize the TrustGateHook
     * @param _oracle Address of TrustScoreOracle
     * @param _defaultMinScore Default minimum trust score (0-100)
     */
    constructor(address _oracle, uint256 _defaultMinScore) {
        if (_oracle == address(0)) revert InvalidOracle();
        if (_defaultMinScore > MAX_SCORE) revert InvalidScore();

        oracle = ITrustScoreOracle(_oracle);
        defaultMinTrustScore = _defaultMinScore;
        owner = msg.sender;

        // Default tiered thresholds
        mediumBudgetThreshold = 1000 * 1e6; // 1000 USDC
        highBudgetThreshold = 10000 * 1e6;  // 10000 USDC
        mediumBudgetMinScore = 60;
        highBudgetMinScore = 80;
    }

    // ============ IACPHook Implementation ============

    /**
     * @notice Called before each hookable action
     * @param jobId The job ID
     * @param selector The function selector being called
     * @param data Encoded function parameters
     */
    function beforeAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external override whenNotPaused {
        // Gate job creation - check provider trust
        if (selector == CREATE_JOB_SELECTOR) {
            _handleCreateJob(jobId, data);
        }
        // Gate provider assignment
        else if (selector == SET_PROVIDER_SELECTOR) {
            _handleSetProvider(jobId, data);
        }
        // Gate funding - could enforce budget-based requirements
        else if (selector == FUND_SELECTOR) {
            _handleFund(jobId, data);
        }
    }

    /**
     * @notice Called after each hookable action
     * @param jobId The job ID
     * @param selector The function selector that was called
     * @param data Encoded function parameters
     */
    function afterAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external override {
        // Emit events for indexer to capture
        // Could trigger reputation updates here
    }

    // ============ Internal Handlers ============

    function _handleCreateJob(uint256 jobId, bytes calldata data) internal {
        // Decode: createJob(provider, evaluator, expiredAt, description, hook)
        (address provider, , , , ) = abi.decode(
            data,
            (address, address, uint256, string, address)
        );

        // Skip check if provider not yet assigned (zero address)
        if (provider == address(0)) return;

        _checkProviderTrust(jobId, provider, 0);
    }

    function _handleSetProvider(uint256 jobId, bytes calldata data) internal {
        // Decode: setProvider(jobId, provider, optParams)
        (, address provider, ) = abi.decode(data, (uint256, address, bytes));

        _checkProviderTrust(jobId, provider, 0);
    }

    function _handleFund(uint256 jobId, bytes calldata data) internal {
        // Decode: fund(jobId, expectedBudget, optParams)
        (, uint256 budget, ) = abi.decode(data, (uint256, uint256, bytes));

        // Budget-based checks could be implemented here
        // For now, just emit an event
    }

    function _checkProviderTrust(
        uint256 jobId,
        address provider,
        uint256 budget
    ) internal {
        // Check blacklist first
        if (blacklistedProviders[provider]) {
            emit JobGated(jobId, provider, 0, MAX_SCORE, false);
            revert ProviderBlacklisted(provider);
        }

        // Check whitelist - bypass trust check
        if (whitelistedProviders[provider]) {
            emit JobGated(jobId, provider, MAX_SCORE, 0, true);
            return;
        }

        // Get provider's trust score
        uint256 score = oracle.getScoreByAddress(provider);

        // Determine required score based on budget tiers
        uint256 requiredScore = _getRequiredScore(msg.sender, budget);

        // Check if score meets requirement
        bool allowed = score >= requiredScore;

        emit JobGated(jobId, provider, score, requiredScore, allowed);

        if (!allowed) {
            revert InsufficientTrustScore(provider, score, requiredScore);
        }
    }

    function _getRequiredScore(address client, uint256 budget) internal view returns (uint256) {
        // Check for client-specific override
        if (hasCustomScore[client]) {
            return clientMinScores[client];
        }

        // Tiered requirements based on budget
        if (budget >= highBudgetThreshold) {
            return highBudgetMinScore;
        } else if (budget >= mediumBudgetThreshold) {
            return mediumBudgetMinScore;
        }

        return defaultMinTrustScore;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update the trust score oracle
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) revert InvalidOracle();
        emit OracleUpdated(address(oracle), _oracle);
        oracle = ITrustScoreOracle(_oracle);
    }

    /**
     * @notice Update default minimum trust score
     * @param _score New minimum score (0-100)
     */
    function setDefaultMinTrustScore(uint256 _score) external onlyOwner {
        if (_score > MAX_SCORE) revert InvalidScore();
        emit DefaultMinScoreUpdated(defaultMinTrustScore, _score);
        defaultMinTrustScore = _score;
    }

    /**
     * @notice Update tiered budget thresholds and scores
     */
    function setTieredThresholds(
        uint256 _mediumThreshold,
        uint256 _highThreshold,
        uint256 _mediumScore,
        uint256 _highScore
    ) external onlyOwner {
        if (_mediumScore > MAX_SCORE || _highScore > MAX_SCORE) revert InvalidScore();

        mediumBudgetThreshold = _mediumThreshold;
        highBudgetThreshold = _highThreshold;
        mediumBudgetMinScore = _mediumScore;
        highBudgetMinScore = _highScore;

        emit TieredThresholdsUpdated(_mediumThreshold, _highThreshold, _mediumScore, _highScore);
    }

    /**
     * @notice Set custom minimum score for a specific client
     * @param client Client address
     * @param minScore Minimum score required for this client's jobs
     */
    function setClientMinScore(address client, uint256 minScore) external onlyOwner {
        if (minScore > MAX_SCORE) revert InvalidScore();
        clientMinScores[client] = minScore;
        hasCustomScore[client] = true;
        emit ClientMinScoreSet(client, minScore);
    }

    /**
     * @notice Remove custom minimum score for a client
     * @param client Client address
     */
    function removeClientMinScore(address client) external onlyOwner {
        hasCustomScore[client] = false;
        emit ClientMinScoreSet(client, defaultMinTrustScore);
    }

    /**
     * @notice Whitelist a provider (bypass trust checks)
     * @param provider Provider address
     * @param whitelisted Whether to whitelist
     */
    function setWhitelisted(address provider, bool whitelisted) external onlyOwner {
        whitelistedProviders[provider] = whitelisted;
        emit ProviderWhitelisted(provider, whitelisted);
    }

    /**
     * @notice Blacklist a provider (always blocked)
     * @param provider Provider address
     * @param blacklisted Whether to blacklist
     */
    function setBlacklisted(address provider, bool blacklisted) external onlyOwner {
        blacklistedProviders[provider] = blacklisted;
        emit ProviderBlacklisted(provider, blacklisted);
    }

    /**
     * @notice Pause/unpause the hook
     * @param _paused Whether to pause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert Unauthorized();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ============ View Functions ============

    /**
     * @notice Check if a provider would pass trust check for a budget
     * @param client Client address (for custom rules)
     * @param provider Provider address
     * @param budget Job budget
     * @return allowed Whether provider would be allowed
     * @return score Provider's current score
     * @return required Required score for this job
     */
    function checkProvider(
        address client,
        address provider,
        uint256 budget
    ) external view returns (bool allowed, uint256 score, uint256 required) {
        if (blacklistedProviders[provider]) {
            return (false, 0, MAX_SCORE);
        }
        if (whitelistedProviders[provider]) {
            return (true, MAX_SCORE, 0);
        }

        score = oracle.getScoreByAddress(provider);
        required = _getRequiredScore(client, budget);
        allowed = score >= required;
    }
}
