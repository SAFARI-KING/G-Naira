// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract G_Naira is ERC20 {

    // governor controls the contract
    address payable public Governor;

    // FG appoints governor and transfers ownership
    address payable public FG;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    event newTx(uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Execute(uint indexed txId);

    struct Transaction{
        address to;
        uint value;
        string name;
        bool executed;
    }

    address[] public multiSigs;
    mapping(address => bool) public isMultiSig;
    uint public totalSigners;
    uint public requiredSigners;

    // get number of multi-signers
    function getMultiSigs()external view returns(address[] memory){
        return multiSigs;
    }

    // set number of required signers to approve a transaction
    function setRequired()internal{
        requiredSigners = (multiSigs.length/2) + 1;
    }

    Transaction[] public transactions;
    mapping(uint => mapping(address => bool)) public isApproved;

    // get all transactions
    function getTransactions()external view returns(Transaction[] memory){
        return transactions;
    }

    constructor() ERC20("G-Naira","gNGN"){
        FG = payable(msg.sender);
    }

    // add an address to the multi-sig
    function addMultiSig(address multiSig) external onlyGovernor {

        require(multiSig != address(0), "Invalid Address!");
        require(!isMultiSig[multiSig], "Owner Already Exist!");

        isMultiSig[multiSig] = true;
        multiSigs.push(multiSig);
        totalSigners += 1;
        setRequired();
    }

    // remove address from multi-sig
    function removeMultiSig(address multiSig) public onlyGovernor {

        require(isMultiSig[multiSig], "Owner does not exist!");
        require(multiSig != Governor, "Cannot remove GOVERNOR!");

        isMultiSig[multiSig] = false;

        for (uint i; i < multiSigs.length; i++) {
                if (multiSigs[i] == multiSig) {
                    multiSigs[i] = multiSigs[multiSigs.length - 1];
                    break;
                }
        }

        multiSigs.pop();
        totalSigners -= 1;
        setRequired();
    }

    // only the governor can submit a mint request
    function mint(address _to,uint _value) external onlyGovernor {
        transactions.push(Transaction(_to,_value,"mint",false));
        emit newTx(transactions.length-1);
    }

    // only the governor can submit a burn request
    function burn(address _to,uint _value) external onlyGovernor {
        require(_value <= _totalSupply, "Value greater than totalSupply!");
        require(_value <= _balances[_to], "Value greater than balance!");
        transactions.push(Transaction(_to,_value,"burn",false));
        emit newTx(transactions.length-1);
    }

    // only multi signers can approve pending transactions
    function multiSigApprove(uint _txId) external onlySigners txExists(_txId) notApproved(_txId) notExecuted(_txId){
        isApproved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    // get approval count of a transaction
    function getApproval(uint _txId) public view txExists(_txId) returns(uint count){
        for(uint i; i < multiSigs.length; i++){
            if(isApproved[_txId][multiSigs[i]]){
                count += 1;
            }
        }
    }

    // only governor can execute approved transactions
    function multiSigExecute(uint _txId) external onlyGovernor txExists(_txId) notExecuted(_txId){
        require(getApproval(_txId) >= requiredSigners, "Aprovals less than required!");
        Transaction storage transaction = transactions[_txId];

        if (keccak256(abi.encodePacked('mint')) == keccak256(abi.encodePacked(transaction.name))){
            _mint(transaction.to, transaction.value * 10 ** 18);
        } else if(keccak256(abi.encodePacked('burn')) == keccak256(abi.encodePacked(transaction.name))){
            _burn(transaction.to, transaction.value * 10 ** 18);
        }

        transaction.executed = true;

        emit Execute(_txId);
    } 

    // to revoke an approval 
    function revokeApproval(uint _txId) external onlySigners txExists(_txId) notExecuted(_txId){
        require(isApproved[_txId][msg.sender], "Transaction not yet approved!");
        isApproved[_txId][msg.sender] = false;
        emit Revoke(msg.sender, _txId);
    }

    mapping(address => bool) public isBlacklist;

    // only governor can blacklist an address
    function setBlacklist(address _account) external onlyGovernor {
        require(_account != Governor, "The GOVERNOR can't be blacklisted!");

        require(!isBlacklist[_account], "Address already blacklisted!");
        isBlacklist[_account] = true;
    }

    // only governor can whitelist an address
    function unSetBlacklist(address _account) external onlyGovernor {
        require(isBlacklist[_account], "Address is not blacklisted!");
        isBlacklist[_account] = false;
    }

    function _beforeTokenTransfer(address from, address to, uint256 value) internal virtual override isNotBlacklisted(from, to){
       super._beforeTokenTransfer(from, to, value * 10 ** 18);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount * 10 ** 18);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount * 10 ** 18);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount * 10 ** 18);
        _transfer(from, to, amount * 10 ** 18);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual override {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount * 10 ** 18);
            }
        }
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + (addedValue * 10 ** 18));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue * 10 ** 18, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - (subtractedValue * 10 ** 18));
        }

        return true;
    }

    modifier onlyFG() {
        require(msg.sender == FG, "Only The FEDERAL GOVERNMENT can call this function");
        _;
    }

    modifier onlySigners() {
        require(isMultiSig[msg.sender], "Only the OWNERS can call this function");
        _;
    }

    modifier onlyGovernor() {
        require(msg.sender == Governor, "Only the GOVERNOR can call this function!");
        _;
    }

    modifier txExists(uint _txId){
        require(_txId < transactions.length, "Transaction does not exist!");
        _;
    }

    modifier notApproved(uint _txId) {
        require(!isApproved[_txId][msg.sender], "Transaction already approved!");
        _;
    }

    modifier notExecuted(uint _txId){
        require(!transactions[_txId].executed, "Transaction already executed!");
        _;
    }

    modifier isNotBlacklisted(address _from, address _to) {
        require(!isBlacklist[_from], "Sender is BLACKLISTED!");
        require(!isBlacklist[_to], "Recipient is BLACKLISTED!");
        _;
    }

    modifier newOfficial(address _newOfficial){
        require(!isBlacklist[_newOfficial], "Address is blacklisted!");
        require(!isMultiSig[_newOfficial], "Remove address from multi-sig");
        require(_newOfficial != address(0), "Ownable: new owner is the zero address");
        require(_newOfficial != Governor && _newOfficial != FG, "OFFICIAL already exist!");
        _;
    }

    // only FG can appoint new governor
    function setNewGovernor(address payable newGovernor) external onlyFG newOfficial(newGovernor) {
        // Removing old governor
        if(isMultiSig[Governor]){
            isMultiSig[Governor] = false;
            delete multiSigs[0];
            totalSigners -= 1;
        }

        // Adding new governor
        Governor = newGovernor;
        isMultiSig[Governor] = true;

        if(multiSigs.length >= 1){
        multiSigs[0] = Governor;
        } else {
            multiSigs.push(Governor);
        }
        totalSigners += 1;
        setRequired();
    }

    // only FG can transfer ownership
    function transferOwnership(address payable newOwner) external onlyFG newOfficial(newOwner){
        FG = newOwner;
    }

}
