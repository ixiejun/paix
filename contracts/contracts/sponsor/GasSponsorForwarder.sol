pragma solidity =0.8.20;

contract GasSponsorForwarder {
    bytes32 private constant META_TX_TYPEHASH = keccak256(
        "MetaTx(address from,address to,uint256 value,bytes32 dataHash,uint256 nonce,uint256 deadline)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;

    string public constant NAME = "GasSponsorForwarder";
    string public constant VERSION = "1";

    address public owner;

    mapping(address => uint256) public nonces;

    bool public requireRelayerAllowed;
    mapping(address => bool) public relayerAllowed;

    struct MetaTx {
        address from;
        address to;
        uint256 value;
        bytes data;
        uint256 deadline;
    }

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event RequireRelayerAllowedUpdated(bool required);
    event RelayerAllowedUpdated(address indexed relayer, bool allowed);

    event MetaTxExecuted(
        address indexed from,
        address indexed to,
        uint256 nonce,
        uint256 value,
        bytes32 dataHash
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "GasSponsorForwarder: NOT_OWNER");
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
        require(newOwner != address(0), "GasSponsorForwarder: ZERO_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setRequireRelayerAllowed(bool required) external onlyOwner {
        requireRelayerAllowed = required;
        emit RequireRelayerAllowedUpdated(required);
    }

    function setRelayerAllowed(address relayer, bool allowed) external onlyOwner {
        relayerAllowed[relayer] = allowed;
        emit RelayerAllowedUpdated(relayer, allowed);
    }

    function executeMetaTx(MetaTx calldata metaTx, bytes calldata signature) external payable returns (bytes memory result) {
        require(metaTx.to != address(0), "GasSponsorForwarder: ZERO_TO");
        require(block.timestamp <= metaTx.deadline, "GasSponsorForwarder: EXPIRED");

        if (requireRelayerAllowed) {
            require(relayerAllowed[msg.sender], "GasSponsorForwarder: RELAYER_NOT_ALLOWED");
        }

        uint256 nonce = nonces[metaTx.from];
        bytes32 digest = _hashTypedData(metaTx.from, metaTx.to, metaTx.value, metaTx.data, nonce, metaTx.deadline);
        require(_recoverSigner(digest, signature) == metaTx.from, "GasSponsorForwarder: BAD_SIG");

        nonces[metaTx.from] = nonce + 1;

        require(msg.value == metaTx.value, "GasSponsorForwarder: BAD_VALUE");

        (bool ok, bytes memory ret) = metaTx.to.call{ value: metaTx.value }(abi.encodePacked(metaTx.data, metaTx.from));
        require(ok, "GasSponsorForwarder: CALL_FAILED");

        emit MetaTxExecuted(metaTx.from, metaTx.to, nonce, metaTx.value, keccak256(metaTx.data));

        return ret;
    }

    function _hashTypedData(
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                META_TX_TYPEHASH,
                from,
                to,
                value,
                keccak256(data),
                nonce,
                deadline
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "GasSponsorForwarder: BAD_SIG_LENGTH");

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

        require(v == 27 || v == 28, "GasSponsorForwarder: BAD_V");
        return ecrecover(digest, v, r, s);
    }
}
