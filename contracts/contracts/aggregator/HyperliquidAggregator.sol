pragma solidity =0.8.20;

import "../interfaces/IERC20.sol";

contract HyperliquidAggregator {
    bytes32 private constant REPORT_TYPEHASH = keccak256(
        "ExecutionReport(bytes32 reportId,address user,address tokenIn,address tokenOut,uint256 amountIn,uint256 amountOut,uint256 deadline)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;

    string public constant NAME = "HyperliquidAggregator";
    string public constant VERSION = "1";

    address public owner;

    mapping(address => mapping(address => uint256)) public escrow;

    mapping(address => bool) public attestorAllowed;
    mapping(bytes32 => bool) public processedReports;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event AttestorAllowedUpdated(address indexed attestor, bool allowed);

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);

    event ExecutionReported(bytes32 indexed reportId, address indexed attestor, address indexed user);
    event Settled(
        bytes32 indexed reportId,
        address indexed user,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "HyperliquidAggregator: NOT_OWNER");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                chainId,
                address(this)
            )
        );
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HyperliquidAggregator: ZERO_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setAttestorAllowed(address attestor, bool allowed) external onlyOwner {
        attestorAllowed[attestor] = allowed;
        emit AttestorAllowedUpdated(attestor, allowed);
    }

    function deposit(address token, uint256 amount) external {
        require(token != address(0), "HyperliquidAggregator: ZERO_TOKEN");
        require(amount > 0, "HyperliquidAggregator: ZERO_AMOUNT");

        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "HyperliquidAggregator: TRANSFER_FROM_FAILED");

        escrow[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(token != address(0), "HyperliquidAggregator: ZERO_TOKEN");
        require(amount > 0, "HyperliquidAggregator: ZERO_AMOUNT");

        uint256 bal = escrow[msg.sender][token];
        require(bal >= amount, "HyperliquidAggregator: INSUFFICIENT_ESCROW");
        escrow[msg.sender][token] = bal - amount;

        require(IERC20(token).transfer(msg.sender, amount), "HyperliquidAggregator: TRANSFER_FAILED");

        emit Withdraw(msg.sender, token, amount);
    }

    struct ExecutionReport {
        bytes32 reportId;
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 deadline;
    }

    function submitExecutionReport(ExecutionReport calldata report, bytes calldata signature) external {
        require(block.timestamp <= report.deadline, "HyperliquidAggregator: EXPIRED");
        require(!processedReports[report.reportId], "HyperliquidAggregator: REPORT_ALREADY_PROCESSED");

        bytes32 digest = _hashTypedData(report);
        address signer = _recoverSigner(digest, signature);
        require(attestorAllowed[signer], "HyperliquidAggregator: ATTESTOR_NOT_ALLOWED");

        processedReports[report.reportId] = true;

        emit ExecutionReported(report.reportId, signer, report.user);

        _applySettlement(report);

        emit Settled(
            report.reportId,
            report.user,
            report.tokenIn,
            report.tokenOut,
            report.amountIn,
            report.amountOut
        );
    }

    function _applySettlement(ExecutionReport calldata report) internal {
        require(report.user != address(0), "HyperliquidAggregator: ZERO_USER");
        require(report.tokenIn != address(0) && report.tokenOut != address(0), "HyperliquidAggregator: ZERO_TOKEN");

        uint256 inBal = escrow[report.user][report.tokenIn];
        require(inBal >= report.amountIn, "HyperliquidAggregator: INSUFFICIENT_ESCROW");

        escrow[report.user][report.tokenIn] = inBal - report.amountIn;
        escrow[report.user][report.tokenOut] += report.amountOut;
    }

    function _hashTypedData(ExecutionReport calldata report) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                REPORT_TYPEHASH,
                report.reportId,
                report.user,
                report.tokenIn,
                report.tokenOut,
                report.amountIn,
                report.amountOut,
                report.deadline
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "HyperliquidAggregator: BAD_SIG_LENGTH");

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "HyperliquidAggregator: BAD_V");
        return ecrecover(digest, v, r, s);
    }
}
