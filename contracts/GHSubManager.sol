pragma solidity ^0.4.24;

import "./ISubscription.sol";
import "./Registry.sol";
import "./base/ERC20.sol";



/// @title ERC-948 Enhanced Multi-signature wallet - Allows multiple parties to agree on transactions abd before execution.
/// @author Stefan George - <stefan.george@consensys.net>
/// @author Andrew Redden - <andrew@blockcrushr.com> ERC-948
contract MultiSigWallet is ISubscription {


    enum SupportedTypes {
        ETH_ESCROW,
        TOKEN_ESCROW,
        TOKEN_APPROVE
    }


    SupportedTypes supportedTypes;
    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event ExecutionSubscription(uint subscriptionId);
    event ExecutionSubscriptionFailure(uint subscriptionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint required);
    event AddSubscription(uint subscriptionId, address indexed txDestination, address indexed recipient, uint value, uint period, uint type);
    event RevokeSubscription(uint subscriptionId, address indexed destination);
    event RegistryChanged(address indexed oldRegistry, address indexed newRegistry);

    /*
     *  views
     */
    uint constant public MAX_OWNER_COUNT = 50;

    /*
     *  Storage
     */
    mapping(uint => Subscriptions) public subscriptions;
    mapping(uint => Transaction) public transactions;
    mapping(uint => mapping(address => bool)) public confirmations;
    mapping(address => bool) public isOwner;
    address[] public owners;
    IRegistry public registry;

    uint public required;
    uint public transactionCount;
    uint public subscriptionCount;

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    struct Subscription {
        address destination;
        address recipient;
        address wallet;
        uint value;
        uint created;
        uint expires;
        uint cycle;
        uint period;
        uint withdrawPrev;
        uint withdrawNext;
        uint externalId;
        bytes data;
        bytes[] meta;
        bool pause;
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner]);
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner]);
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != address(0));
        _;
    }

    modifier subscriptionExists(uint subscriptionId) {
        require(subscriptions[subscriptionId].destination != address(0));
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        require(confirmations[transactionId][owner]);
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner]);
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed);
        _;
    }

    modifier subscriptionNotExpired(uint subscriptionId) {
        require(!subscriptions[subscriptionId].expire <= now);
        _;
    }

    modifier notNull(address _address) {
        require(_address != 0);
        _;
    }

    modifier validRequirement(uint ownerCount, uint _required) {
        require(ownerCount <= MAX_OWNER_COUNT
        && _required <= ownerCount
        && _required != 0
        && ownerCount != 0);
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function()
    payable
    {
        if (msg.value > 0)
            emit Deposit(msg.sender, msg.value);
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    constructor (address[] _owners, uint _required, address _registry)
    payable
    public
    validRequirement(_owners.length, _required)
    {
        for (uint i = 0; i < _owners.length; i++) {
            require(!isOwner[_owners[i]] && _owners[i] != 0);
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
        registry = IRegistry(_registry);

        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    function addOwner(address _owner)
    public
    onlyWallet
    ownerDoesNotExist(_owner)
    notNull(_owner)
    validRequirement(owners.length + 1, required)
    {
        isOwner[_owner] = true;
        owners.push(_owner);
        emit OwnerAddition(_owner);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner.
    function removeOwner(address _owner)
    public
    onlyWallet
    ownerExists(_owner)
    {
        isOwner[_owner] = false;
        for (uint i = 0; i < owners.length - 1; i++)
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (required > owners.length)
            changeRequirement(owners.length);
        emit OwnerRemoval(_owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner to be replaced.
    /// @param newOwner Address of new owner.
    function replaceOwner(address _owner, address _newOwner)
    public
    onlyWallet
    ownerExists(_owner)
    ownerDoesNotExist(_newOwner)
    {
        for (uint i = 0; i < owners.length; i++)
            if (owners[i] == _owner) {
                owners[i] = _newOwner;
                break;
            }
        isOwner[_owner] = false;
        isOwner[_newOwner] = true;
        emit OwnerRemoval(_owner);
        emit OwnerAddition(_newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required)
    public
    onlyWallet
    validRequirement(owners.length, _required)
    {
        required = _required;
        emit RequirementChange(_required);
    }

    function changeRegistryAddress(address _newRegistry)
    public
    onlyWallet
    ownerExists(msg.sender) {
        registry = _newRegistry;
        emit RegistryChanged(_newRegistry);
    }



    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address _tx_destination, uint _value, bytes _data)
    public
    returns (uint transactionId)
    {
        transactionId = addTransaction(_tx_destination, _value, _data);
        confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to submit and confirm a subscription.
    /// @param destination Subscription target address.
    /// @param recipient Subscription recipient address (optional)
    /// @param value Subscription value, depends on type.
    /// @param type Subscription type
    /// @param period Subscription withdrawal period
    /// @param data Subscription data payload.
    /// @param meta Subscription meta data payload.
    /// @return Returns subscriptionId.
    function submitSubscription(
        address _txDestination,
        address _recipient,
        uint _value,
        uint _period,
        uint _type,
        bytes _data,
        bytes[] _meta
    )
    payable
    public
    returns (uint subscriptionId)
    {
        (subscriptionId, externalId) = addSubscription(_txDestination, _recipient, _type, _value, _period, _data, _meta);

        registry.handleNewSubscription(_txDestination, address(this), subscriptionId, _externalId);

        if (msg.value >= _value || (this.balance >= _value) || _data != null) {// check to see if payment is valid
            executeSubscription(subscriptionId);
        }

        emit NewSubscription(subscriptionId, _txDestination, _value, _period, _type);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @param expires Transaction data payload.
    /// @param period Transaction data payload.
    /// @param externalId Transaction data payload.
    /// @return Returns transaction ID.
    function cancelSubscription(uint _subscriptionId)
    public
    ownerExists(msg.sender)
    returns (uint subscriptionId)
    {
        //load subscription into storage, modify expire to match today

        Subscription storage sub = subscriptions[_subscriptionId];
        sub.expires = now;
        emit CancelSubscription(address(this), _subscriptionId);
    }



    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
    public
    ownerExists(msg.sender)
    transactionExists(transactionId)
    notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
    public
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }


    modifier validOperator(address _operator) {
        require(registry.isOperator[_operator] || isOwner[_operator]);
        _;
    }

    modifier validWithdrawal(uint subscriptionId) {
        require(subscriptions[subscriptionId].expires > now);
        require(subscriptions[subscriptionId].withdrawNext <= now);
        _;
    }

    /// @dev Allows valid operators to execute a valid subscription
    /// @param subscriptionId Subscription ID.
    function executeSubscription(uint subscriptionId)
    public
    validOperator(msg.sender)
    validWithdrawal(subscriptionId)
    {

        //check type of subscription, if normal txn, build and do external call

        Subscription storage sub = subscriptions[subscriptionId];

        bool success = false;

        if (sub.type == uint(0)) {
            //check to see if the contract has the correct balance for the subscription
            require(address(this).balance >= subscriptions[subscriptionId].value);

            if (external_call(sub.destination, sub.value, sub.data.length, sub.data)) {
                success = true;
            }
        } else if (sub.type == uint(1)) {
            if (transferFrom(sub.txDestination, sub.wallet, sub.recipient, sub.value)) {
                success = true;
            }
        } else {
            revert("Un implemented type");
        }

        if (success) {

            Subscription storage sub = subscriptions[subscriptionId];

            sub.withdrawPrev = now;

            sub.withdrawNext = sub.created + (sub.period * sub.cycle);

            emit ExecutionSubscription(subscriptionId);

            if (address(tcr) != address(0)) {

                ITCR dest = ITCR(tcr);

                bool first = false;

                if (sub.cycle == 0) {
                    first = true;
                }

                dest.handlePaymentNotification(tx_destination, subscriptionId, sub.externalId, first);
            }
            sub.cycle++;
        } else {
            emit ExecutionSubscriptionFailure(subscriptionId);
        }


    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
    public
    ownerExists(msg.sender)
    confirmed(transactionId, msg.sender)
    notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes data) private returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
            sub(gas, 34710), // 34710 is the value that solidity is currently emitting
            // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
            // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
            destination,
            value,
            d,
            dataLength, // Size of the input (in bytes) - this is what fixes the padding problem
            x,
            0                  // Output is ignored, therefore the output size is zero
            )
        }
        return result;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint transactionId)
    public
    view
    returns (bool)
    {
        uint count = 0;
        for (uint i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address _destination, uint _value, bytes _data)
    internal
    notNull(_destination)
    returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination : _destination,
            value : _value,
            data : _data,
            executed : false
            });
        transactionCount += 1;
        emit Submission(transactionId);
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param _txDestination Subscription target address, smart contract, normal wallet, etc.
    /// @param _txDestination Subscription target recipient address, smart contract, normal wallet, etc.
    /// @param _value Transaction ether or token value.
    /// @param _type Enumerated tx type
    /// @param _period Transaction data payload.
    /// @param _data Transaction data payload.
    /// @param _meta Transaction data payload.
    /// @param _data Transaction data payload.
    /// @return Returns transaction ID.
    function addSubscription(
        address _txDestination,
        address _recipient,
        uint _value,
        uint _type,
        uint _period,
        bytes _data,
        bytes[] _meta)
    internal
    notNull(destination)
    validType(_type)
    returns (uint subscriptionId, bytes externalId)
    {
        //hash the destination and the data to make sure we don't have a copy of the subscription

        //check type value, then check meta data to match the schema, wallet


        require(_meta[0]);
        require(_meta[1]);
        require(_meta[2]);

        uint type = bytesToUInt(_meta[0]);
        //check to ensure we support the type;
        require(supportedTypes[type]);

        uint externalId = bytesToUInt(_meta[1]);

        uint expires = (_meta[2]) ? bytesToUInt(_meta[2]) : 0;

        address wallet;
        bytes externalId;
        wallet = address(this);

        if (type == supportedTypes.ETH_ESCROW) {
            //set any specific variables around ETH_ESCROW
        } else if (type == supportedTypes.TOKEN_ESCROW) {

        } else if (type == supportedTypes.TOKEN_APPROVE) {
            require(_meta[3] != bytes(0));
            wallet = bytesToAddress(_meta[3]);
        }





        bytes externalId = "";


        subscriptionId = subscriptionCount;

        subscriptions[subscriptionId] = Subscription({
            destination : _txDestination,
            recipient : _recipient,
            type : type,
            wallet : wallet,
            value : value,
            data : data,
            created : now,
            expires : expires,
            period : period,
            externalId : externalId
            });
        subscriptionCount += 1;

        emit AddSubscription(subscriptionId, txDestination, recipient, value, period, type);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint transactionId)
    public
    view
    returns (uint count)
    {
        for (uint i = 0; i < owners.length; i++)
            if (confirmations[transactionId][owners[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed)
    public
    view
    returns (uint count)
    {
        for (uint i = 0; i < transactionCount; i++)
            if (pending && !transactions[i].executed
            || executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param withdraw Include transactions available for withdraw.
    /// @param expired Include expired subscriptions.
    /// @return Total number of transactions after filters are applied.
    function getSubscriptionCount(bool withdraw, bool expired)
    public
    view
    returns (uint count)
    {
        for (uint i = 0; i < subscriptionCount; i++) {
            if (withdraw) {
                if (subscriptions[i].withdraw <= now) {
                    subscriptionIdsTemp[count] = i;
                    count += 1;
                }
            } else if (expired) {
                if (subscriptions[i].expired >= now) {
                    subscriptionIdsTemp[count] = i;
                    count += 1;
                }
            } else {
                subscriptionIdsTemp[count] = i;
                count += 1;
            }
        }
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners()
    public
    view
    returns (address[])
    {
        return owners;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint transactionId)
    public
    view
    returns (address[] _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i = 0; i < owners.length; i++)
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i = 0; i < count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
    public
    view
    returns (uint[] _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i = 0; i < transactionCount; i++)
            if (pending && !transactions[i].executed
            || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i = from; i < to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }


    /// @dev Returns list of subscription IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param withdraw Include subscriptions that can be withdrawn.
    /// @param expired include expired subscriptions
    /// @return Returns array of subscription IDs.
    function getSubscriptionIds(uint from, uint to, bool withdraw, bool expired)
    public
    view
    returns (uint[] _subscriptionIds)
    {
        uint[] memory subscriptionIdsTemp = new uint[](subscriptionCount);
        uint count = 0;
        uint i;
        for (i = 0; i < subscriptionCount; i++) {
            if (withdraw) {
                if (subscriptions[i].withdrawNext <= now) {
                    subscriptionIdsTemp[count] = i;
                    count += 1;
                }
            }
            if (expired) {
                if (subscriptions[i].expired >= now) {
                    subscriptionIdsTemp[count] = i;
                    count += 1;
                }
            }

            if (!withdraw && !expired) {
                subscriptionIdsTemp[count] = i;
                count += 1;
            }
        }
        _subscriptionIds = new uint[](to - from);
        for (i = from; i < to; i++) {
            _subscriptionIds[i - from] = subscriptionIdsTemp[i];
        }
    }


    function transferFrom(
        address _token,
        address _from,
        address _to,
        uint _value)
    internal
    validOperator(msg.sender)
    returns (bool success)
    {
        return ERC20(_token).transferFrom(_from, _to, _value);
    }




    // utilities


    function bytesToAddress(bytes _bytes, uint _start) internal pure returns (address oAddress) {
        require(_bytes.length >= (_start + 20));
        assembly {
            oAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }
    }

    function bytesToUint(bytes _bytes, uint _start) internal pure returns (uint oUint) {
        require(_bytes.length >= (_start + 32));
        assembly {
            oUint := mload(add(add(_bytes, 0x20), _start))
        }
    }
}