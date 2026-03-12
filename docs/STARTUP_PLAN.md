# Veridex: Startup Plan for ERC-8183 + ACP

## Executive Summary

**Vision**: Become the definitive trust index for the agent economy by providing reputation infrastructure for ERC-8183 agentic commerce.

**Tagline**: *"Veridex: The Agent Trust Index"*

**Why This Works**:
1. ERC-8183 (from Virtuals Protocol + Ethereum Foundation) needs ERC-8004 trust data
2. Virtual Protocol's ACP is the dominant agent commerce platform (18,000+ agents)
3. Your repo already indexes ERC-8004 reputation data
4. The feedback loop: Commerce → Reputation → Better Commerce

## What We Built

### 1. Architecture Document
**File**: `docs/ERC8183_INTEGRATION.md`

- Complete integration map between your stack and ERC-8183
- Data flow diagrams
- API endpoint specifications
- Deployment phases

### 2. TrustGateHook Smart Contract
**File**: `contracts/hooks/TrustGateHook.sol`

An ERC-8183 hook that:
- Gates job creation based on provider trust scores
- Supports tiered requirements (higher budget = higher trust required)
- Whitelist/blacklist functionality
- Per-client custom thresholds
- Pausable for emergencies

### 3. Enhanced Oracle (V2)
**File**: `contracts/contracts/TrustScoreOracleV2.sol`

Upgraded oracle that:
- Supports address-based queries (for ERC-8183 hooks)
- Free view functions for hooks (no gas for reads)
- Paid queries for external callers
- Batch operations
- Authorized updater system

### 4. Interface Definitions
- `contracts/interfaces/IACPHook.sol` - ERC-8183 hook interface
- `contracts/interfaces/ITrustScoreOracle.sol` - Oracle interface

## Revenue Model

| Stream | Mechanism | Projected |
|--------|-----------|-----------|
| **API (x402)** | Pay-per-query for premium endpoints | $0.0001-0.0005/call |
| **Oracle Fees** | On-chain queries pay 0.001 ETH | Per query |
| **Hook Licensing** | % of jobs using TrustGateHook | 0.1% of job value |
| **Enterprise** | Custom scoring models | Subscription |

## Go-To-Market Strategy

### Phase 1: Integration (Week 1-2)
1. Deploy TrustScoreOracleV2 to Base testnet
2. Deploy TrustGateHook to Base testnet
3. Register API as ACP resource
4. Test with Virtual Protocol team

### Phase 2: Launch (Week 3-4)
1. Deploy to Base mainnet
2. Partner with 3-5 ACP agents to use the hook
3. Announce integration on Twitter/Discord
4. Apply for Virtual Protocol ecosystem grant

### Phase 3: Scale (Month 2+)
1. Index ERC-8183 job events for reputation signals
2. Build evaluator service using trust data
3. Create dashboard for agents to view their scores
4. Expand to other chains

## Competitive Moat

1. **First Mover**: First trust oracle integrated with ACP
2. **Data Network Effect**: More jobs → More reputation data → Better scores
3. **Symbiosis**: Officially designed to work with ERC-8004/8183
4. **Open Standard**: Build on Ethereum standards, not proprietary systems

## Technical Next Steps

```bash
# 1. Install dependencies
cd contracts
npm install

# 2. Deploy to testnet
npx hardhat run scripts/deploy-v2.ts --network base-sepolia

# 3. Register with ACP
acp sell resource init trust_scores
acp sell resource create trust_scores

# 4. Start seller runtime
acp serve start
```

## Key Links

- **ERC-8183 Spec**: https://eips.ethereum.org/EIPS/eip-8183
- **ERC-8004 Spec**: https://eips.ethereum.org/EIPS/eip-8004
- **Virtual Protocol ACP**: https://github.com/Virtual-Protocol/openclaw-acp
- **ACP Whitepaper**: https://whitepaper.virtuals.io/about-virtuals/agent-commerce-protocol-acp
- **Telegram (ERC-8183 Builders)**: https://t.me/erc8183

## Team Positioning

Position yourself as:
> "Veridex is the definitive trust index for AI agent commerce. We verify and index reputation scores that power safe, trustless transactions between agents."

Key talking points:
- "Veridex indexes ERC-8004 reputation data from on-chain registries"
- "Our TrustGateHook enables reputation-gated commerce on ERC-8183"
- "Every job completion feeds back into the Veridex trust index"
- "Built on open Ethereum standards, not proprietary platforms"
- "Verify before you transact - that's the Veridex standard"

## Funding/Grant Opportunities

1. **Virtuals Protocol Ecosystem Fund** - They're distributing $1M/month to ACP builders
2. **Ethereum Foundation dAI Team** - Co-developed ERC-8183
3. **Base Ecosystem Fund** - Building on Base chain
4. **Agent Commerce Grants** - New category emerging

## Contact Points

- Virtual Protocol: Apply through https://app.virtuals.io
- ERC-8183 Discussion: https://ethereum-magicians.org/t/erc-8183-agentic-commerce/27902
- Builder Community: https://t.me/erc8183

---

**You're positioned perfectly. The agent economy needs trust infrastructure, and you're building it.**
