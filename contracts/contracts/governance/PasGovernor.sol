pragma solidity =0.8.20;

contract PasGovernor {
    struct Action {
        address target;
        uint256 value;
        bytes data;
    }

    struct Proposal {
        address proposer;
        uint64 startBlock;
        uint64 endBlock;
        uint64 executeAfter;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool canceled;
    }

    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    uint256 public proposalCount;

    uint256 public immutable votingPeriodBlocks;
    uint256 public immutable executionDelayBlocks;

    uint16 public immutable quorumBps;
    uint256 public immutable proposalThreshold;

    uint16 public defaultFeeBps;
    address public defaultFeeRecipient;

    mapping(address => uint256) public staked;
    mapping(address => uint64) public lockEndBlock;

    mapping(address => Checkpoint[]) private voteCheckpoints;
    Checkpoint[] private totalVoteCheckpoints;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Action[]) private proposalActions;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    mapping(bytes32 => bool) public marketListed;
    mapping(address => bool) public matcherOperators;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, uint64 startBlock, uint64 endBlock);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);

    event MarketListed(bytes32 indexed marketId, address indexed base, address indexed quote);
    event MarketDelisted(bytes32 indexed marketId, address indexed base, address indexed quote);

    event DefaultFeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event DefaultFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event MatcherOperatorUpdated(address indexed operator, bool allowed);

    modifier onlySelf() {
        require(msg.sender == address(this), "PasGovernor: ONLY_SELF");
        _;
    }

    constructor(
        uint256 _votingPeriodBlocks,
        uint256 _executionDelayBlocks,
        uint16 _quorumBps,
        uint256 _proposalThreshold,
        uint16 _defaultFeeBps,
        address _defaultFeeRecipient
    ) {
        require(_votingPeriodBlocks > 0, "PasGovernor: BAD_VOTING_PERIOD");
        require(_quorumBps <= 10_000, "PasGovernor: BAD_QUORUM");
        require(_defaultFeeBps <= 10_000, "PasGovernor: BAD_FEE");

        votingPeriodBlocks = _votingPeriodBlocks;
        executionDelayBlocks = _executionDelayBlocks;
        quorumBps = _quorumBps;
        proposalThreshold = _proposalThreshold;

        defaultFeeBps = _defaultFeeBps;
        defaultFeeRecipient = _defaultFeeRecipient;

        _writeTotalCheckpoint(0);
    }

    receive() external payable {
        revert("PasGovernor: DIRECT_TRANSFER_DISABLED");
    }

    function stake() external payable {
        require(msg.value > 0, "PasGovernor: ZERO_STAKE");

        staked[msg.sender] += msg.value;
        _writeVoteCheckpoint(msg.sender, staked[msg.sender]);
        _writeTotalCheckpoint(totalStaked() + msg.value);

        emit Staked(msg.sender, msg.value);
    }

    function unstake(uint256 amount) external {
        require(amount > 0, "PasGovernor: ZERO_UNSTAKE");
        require(block.number > lockEndBlock[msg.sender], "PasGovernor: STAKE_LOCKED");

        uint256 bal = staked[msg.sender];
        require(bal >= amount, "PasGovernor: INSUFFICIENT_STAKE");

        unchecked {
            staked[msg.sender] = bal - amount;
        }

        _writeVoteCheckpoint(msg.sender, staked[msg.sender]);
        _writeTotalCheckpoint(totalStaked() - amount);

        (bool ok, ) = msg.sender.call{ value: amount }(new bytes(0));
        require(ok, "PasGovernor: UNSTAKE_TRANSFER_FAILED");

        emit Unstaked(msg.sender, amount);
    }

    function totalStaked() public view returns (uint256) {
        uint256 len = totalVoteCheckpoints.length;
        if (len == 0) return 0;
        return uint256(totalVoteCheckpoints[len - 1].votes);
    }

    function getVotes(address account, uint256 blockNumber) public view returns (uint256) {
        return _getVotesFromCheckpoints(voteCheckpoints[account], blockNumber);
    }

    function getTotalVotes(uint256 blockNumber) public view returns (uint256) {
        return _getVotesFromCheckpoints(totalVoteCheckpoints, blockNumber);
    }

    function propose(Action[] calldata actions) external returns (uint256 proposalId) {
        require(actions.length > 0, "PasGovernor: NO_ACTIONS");

        uint256 proposerVotes = getVotes(msg.sender, block.number - 1);
        require(proposerVotes >= proposalThreshold, "PasGovernor: BELOW_THRESHOLD");

        proposalId = ++proposalCount;

        uint64 start = uint64(block.number + 1);
        uint64 end = uint64(uint256(start) + votingPeriodBlocks);
        uint64 executeAfter = uint64(uint256(end) + executionDelayBlocks);

        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            startBlock: start,
            endBlock: end,
            executeAfter: executeAfter,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            canceled: false
        });

        for (uint256 i = 0; i < actions.length; i++) {
            proposalActions[proposalId].push(actions[i]);
        }

        emit ProposalCreated(proposalId, msg.sender, start, end);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(p.proposer != address(0), "PasGovernor: PROPOSAL_NOT_FOUND");
        require(!p.canceled, "PasGovernor: CANCELED");
        require(block.number >= p.startBlock, "PasGovernor: NOT_STARTED");
        require(block.number <= p.endBlock, "PasGovernor: ENDED");
        require(!hasVoted[proposalId][msg.sender], "PasGovernor: ALREADY_VOTED");

        uint256 votes = getVotes(msg.sender, uint256(p.startBlock) - 1);
        require(votes > 0, "PasGovernor: NO_VOTES");

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            p.forVotes += votes;
        } else {
            p.againstVotes += votes;
        }

        if (lockEndBlock[msg.sender] < p.endBlock) {
            lockEndBlock[msg.sender] = p.endBlock;
        }

        emit VoteCast(proposalId, msg.sender, support, votes);
    }

    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.proposer != address(0), "PasGovernor: PROPOSAL_NOT_FOUND");
        require(!p.canceled, "PasGovernor: CANCELED");
        require(!p.executed, "PasGovernor: EXECUTED");

        require(block.number > p.endBlock, "PasGovernor: VOTING_ACTIVE");
        require(block.number >= p.executeAfter, "PasGovernor: DELAY");

        uint256 snapshotTotal = getTotalVotes(uint256(p.startBlock) - 1);
        uint256 quorumVotes = (snapshotTotal * uint256(quorumBps)) / 10_000;

        require(p.forVotes + p.againstVotes >= quorumVotes, "PasGovernor: NO_QUORUM");
        require(p.forVotes > p.againstVotes, "PasGovernor: DEFEATED");

        Action[] storage actions = proposalActions[proposalId];
        for (uint256 i = 0; i < actions.length; i++) {
            (bool ok, ) = actions[i].target.call{ value: actions[i].value }(actions[i].data);
            require(ok, "PasGovernor: ACTION_FAILED");
        }

        p.executed = true;

        emit ProposalExecuted(proposalId);
    }

    function marketId(address base, address quote) public pure returns (bytes32) {
        require(base != address(0) && quote != address(0), "PasGovernor: ZERO_TOKEN");
        return keccak256(abi.encode(base, quote));
    }

    function listMarket(address base, address quote) external onlySelf {
        bytes32 id = marketId(base, quote);
        marketListed[id] = true;
        emit MarketListed(id, base, quote);
    }

    function delistMarket(address base, address quote) external onlySelf {
        bytes32 id = marketId(base, quote);
        marketListed[id] = false;
        emit MarketDelisted(id, base, quote);
    }

    function setDefaultFeeBps(uint16 newFeeBps) external onlySelf {
        require(newFeeBps <= 10_000, "PasGovernor: BAD_FEE");
        emit DefaultFeeBpsUpdated(defaultFeeBps, newFeeBps);
        defaultFeeBps = newFeeBps;
    }

    function setDefaultFeeRecipient(address newRecipient) external onlySelf {
        emit DefaultFeeRecipientUpdated(defaultFeeRecipient, newRecipient);
        defaultFeeRecipient = newRecipient;
    }

    function setMatcherOperator(address operator, bool allowed) external onlySelf {
        matcherOperators[operator] = allowed;
        emit MatcherOperatorUpdated(operator, allowed);
    }

    function _writeVoteCheckpoint(address account, uint256 newVotes) internal {
        require(newVotes <= type(uint224).max, "PasGovernor: VOTES_OVERFLOW");
        Checkpoint[] storage ckpts = voteCheckpoints[account];

        uint32 bn = uint32(block.number);
        uint224 votes224 = uint224(newVotes);

        uint256 len = ckpts.length;
        if (len > 0 && ckpts[len - 1].fromBlock == bn) {
            ckpts[len - 1].votes = votes224;
        } else {
            ckpts.push(Checkpoint({ fromBlock: bn, votes: votes224 }));
        }
    }

    function _writeTotalCheckpoint(uint256 newVotes) internal {
        require(newVotes <= type(uint224).max, "PasGovernor: TOTAL_OVERFLOW");
        uint32 bn = uint32(block.number);
        uint224 votes224 = uint224(newVotes);

        uint256 len = totalVoteCheckpoints.length;
        if (len > 0 && totalVoteCheckpoints[len - 1].fromBlock == bn) {
            totalVoteCheckpoints[len - 1].votes = votes224;
        } else {
            totalVoteCheckpoints.push(Checkpoint({ fromBlock: bn, votes: votes224 }));
        }
    }

    function _getVotesFromCheckpoints(Checkpoint[] storage ckpts, uint256 blockNumber) internal view returns (uint256) {
        uint256 len = ckpts.length;
        if (len == 0) return 0;

        if (blockNumber >= ckpts[len - 1].fromBlock) {
            return uint256(ckpts[len - 1].votes);
        }

        if (blockNumber < ckpts[0].fromBlock) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = len - 1;
        while (high > low) {
            uint256 mid = (high + low + 1) / 2;
            if (ckpts[mid].fromBlock <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return uint256(ckpts[low].votes);
    }
}
