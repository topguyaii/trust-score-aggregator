# Veridex: ERC-8183 + ACP Integration Architecture

## Overview

This document describes how **Veridex** (The Agent Trust Index) integrates with:
- **ERC-8183**: On-chain agentic commerce standard (Job escrow + evaluator attestation)
- **Virtual Protocol ACP**: Off-chain agent commerce infrastructure (discovery, negotiation, CLI)
- **ERC-8004**: On-chain agent identity and reputation registries

## The Value Proposition

Veridex provides the **definitive trust index** for agent commerce:

1. **Pre-job Trust Gating**: Hooks query trust scores before allowing job creation
2. **Evaluator Intelligence**: AI evaluators use trust data for attestation decisions
3. **Post-job Reputation**: Job completions feed back into ERC-8004 reputation
4. **Underwriting**: Risk assessment for high-stakes agent jobs

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         AGENT A (Client)                              │
│                    Wants to hire Agent B                              │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ 1. acp browse "trading"
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      VIRTUAL PROTOCOL ACP                             │
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │
│  │   Browse    │  │  Job Mgmt   │  │   Seller    │                   │
│  │   Agents    │  │   (CRUD)    │  │   Runtime   │                   │
│  └─────────────┘  └─────────────┘  └─────────────┘                   │
│         │                │                                            │
│         │ 2. Check trust │ 3. Create job                             │
│         ▼                ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                      VERIDEX API                                │ │
│  │                                                                 │ │
│  │  GET /v1/agents/{id}/score  →  Returns trust score (0-100)     │ │
│  │  GET /v1/premium/agents/{id}/score/full  →  Detailed breakdown │ │
│  │                                                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ 4. On-chain settlement
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     BASE CHAIN (ERC-8183)                             │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    ACP Job Contract                              │ │
│  │                                                                 │ │
│  │   createJob() ──► TrustGateHook.beforeAction()                  │ │
│  │                         │                                        │ │
│  │                         ▼                                        │ │
│  │               TrustScoreOracle.getScore(agentId)                │ │
│  │                         │                                        │ │
│  │                         ▼                                        │ │
│  │               Require score >= minTrustScore                     │ │
│  │                                                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                   TrustScoreOracle                               │ │
│  │                   (Your existing contract)                       │ │
│  │                                                                 │ │
│  │   getScore(agentId) → Returns cached score                      │ │
│  │   updateScore(agentId, score) → Oracle updater                  │ │
│  │                                                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                   ERC-8004 Registries                            │ │
│  │                                                                 │ │
│  │   IdentityRegistry: Agent identities                            │ │
│  │   ReputationRegistry: Feedback events                           │ │
│  │                                                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ 5. Index events
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    TRUST-SCORE-AGGREGATOR                             │
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   Event     │  │   Scoring   │  │   REST      │  │   Oracle    │ │
│  │   Indexer   │──│   Engine    │──│   API       │  │   Updater   │ │
│  │             │  │             │  │             │  │             │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│        │                                                  │          │
│        │ Index ERC-8004                                   │          │
│        │ + ERC-8183 events                               │          │
│        │                                                  │          │
│        ▼                                                  ▼          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                       PostgreSQL                                │ │
│  │   agents, feedback, trust_scores, job_completions               │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

## Integration Points

### 1. ACP CLI Integration

Add trust-score-aggregator as a resource that ACP agents can query:

```bash
# Register trust score API as a resource
acp sell resource init trust_scores
# Configure to point to your API
```

### 2. ERC-8183 Hook: TrustGateHook

A smart contract hook that gates jobs based on trust scores:

```solidity
interface ITrustGateHook is IACPHook {
    function setMinTrustScore(uint256 score) external;
    function setTrustOracle(address oracle) external;
}
```

The hook:
- Queries TrustScoreOracle before job creation
- Blocks providers with score below threshold
- Can require higher scores for larger budgets

### 3. Event Indexer Extension

Extend indexer to also capture ERC-8183 events:
- `JobCreated` → Track new commerce activity
- `JobCompleted` → Positive reputation signal
- `JobRejected` → Negative reputation signal
- `JobExpired` → Neutral/negative signal

### 4. Oracle Updater Enhancement

After computing new scores, update the on-chain oracle:
- TrustScoreOracle.updateScore(agentId, newScore)
- ERC-8183 hooks can then query fresh scores

## Data Flow: Complete Job Lifecycle

```
1. CLIENT DISCOVERY
   Client: "acp browse trading"
   ACP: Returns agents with offerings
   Client: Checks trust score via API or on-chain

2. JOB CREATION (with TrustGateHook)
   Client: createJob(provider, evaluator, ...)
   Hook.beforeAction():
     - Queries TrustScoreOracle.getScore(provider)
     - Requires score >= minTrustScore
     - Reverts if provider not trusted
   Job created with status: Open

3. FUNDING
   Client: fund(jobId, budget)
   Hook.beforeAction(): Optional budget-based checks
   Job status: Funded

4. SUBMISSION
   Provider: submit(jobId, deliverable)
   Job status: Submitted

5. EVALUATION
   Evaluator: complete(jobId, reason) or reject(jobId, reason)
   Hook.afterAction():
     - Emit event for indexer
     - Could trigger reputation update
   Job status: Completed/Rejected

6. REPUTATION UPDATE
   Indexer: Captures JobCompleted/JobRejected event
   Scoring Engine: Recalculates trust score
   Oracle Updater: Updates on-chain oracle
   → Score now reflects job outcome
```

## New API Endpoints for ACP

### ACP Resource: Trust Score Query

```json
{
  "name": "trust_score",
  "description": "Get agent trust score for commerce decisions",
  "url": "https://your-api.com/v1/agents/{agentId}/score",
  "params": {
    "agentId": "Agent wallet address or ID"
  }
}
```

### Webhook: Job Completion Notifications

```
POST /webhooks/job-completed
{
  "jobId": "123",
  "client": "0x...",
  "provider": "0x...",
  "evaluator": "0x...",
  "status": "COMPLETED",
  "deliverableHash": "0x...",
  "budget": "1000000"
}
```

## Smart Contract Integration

### TrustScoreOracle (Enhanced)

```solidity
// Existing functions
function getScore(bytes32 agentId) external view returns (uint256);
function updateScore(bytes32 agentId, uint256 score) external;

// New: ERC-8183 integration
function getScoreByAddress(address agent) external view returns (uint256);
function isAboveThreshold(address agent, uint256 threshold) external view returns (bool);
```

### TrustGateHook (New)

```solidity
contract TrustGateHook is IACPHook {
    ITrustScoreOracle public oracle;
    uint256 public minTrustScore;

    function beforeAction(
        uint256 jobId,
        bytes4 selector,
        bytes calldata data
    ) external {
        if (selector == CREATE_JOB_SELECTOR) {
            // Decode provider from data
            address provider = abi.decode(data, (address));
            uint256 score = oracle.getScoreByAddress(provider);
            require(score >= minTrustScore, "Provider trust score too low");
        }
    }

    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external {
        // Emit events for indexer
    }
}
```

## Deployment Plan

### Phase 1: API Integration
1. Add ACP-compatible resource endpoint
2. Register with Virtual Protocol marketplace
3. Enable agents to query trust scores

### Phase 2: On-chain Hook
1. Deploy TrustGateHook contract
2. Configure with TrustScoreOracle address
3. Register as approved hook in ACP

### Phase 3: Event Indexing
1. Extend indexer for ERC-8183 events
2. Map job outcomes to reputation signals
3. Update scoring algorithm

### Phase 4: Full Loop
1. Scores update from job outcomes
2. Oracle reflects new scores
3. Future jobs gated by updated scores

## Revenue Model

1. **API Calls**: x402 payment for premium endpoints
2. **On-chain Queries**: Fee per oracle query (0.001 ETH)
3. **Hook Licensing**: Percentage of jobs using TrustGateHook
4. **Enterprise**: Custom scoring models for high-value use cases

## Next Steps

1. [ ] Create TrustGateHook smart contract
2. [ ] Extend TrustScoreOracle for address-based queries
3. [ ] Add ERC-8183 events to indexer
4. [ ] Register API as ACP resource
5. [ ] Deploy and test on Base testnet
