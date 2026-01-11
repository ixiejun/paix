pragma solidity =0.5.16;

contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint public totalSupply;

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor(string memory _name, string memory _symbol, uint _supply) public {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _supply);
    }

    function _mint(address to, uint value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function mint(address to, uint value) external {
        _mint(to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        uint allowed = allowance[from][msg.sender];
        if (allowed != uint(-1)) {
            require(allowed >= value, 'TestERC20: INSUFFICIENT_ALLOWANCE');
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint value) internal {
        require(balanceOf[from] >= value, 'TestERC20: INSUFFICIENT_BALANCE');
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
