pragma solidity 0.4.24;

contract ISubscription {

    function isValidSubscription(bytes _subscriptionHash) view public returns (bool);


    function createSubscription(address _destination, address _recipient, uint _value, bytes _data, uint _expires, uint _interval, uint _externalId, bytes[] _meta);

    function cancelSubscription(bytes _subscriptionHash) public returns (bool);

    function pauseSubscription(bytes _subscriptionHash) public returns (bool);

    function getSubscription(bytes _subscriptionHash) view public returns (address, address, uint, bytes, uint, uint, uint, uint, uint, uint, uint, bool, bytes[]);

    function getSubscriptionIds(uint from, uint to, bool withdrawAvailable, bool expired) public view returns (uint[]);

    function getSubscriptionValue(bytes _subscriptionHash) view public returns (uint);

    function getSubscriptionMeta(bytes _subscriptionHash) view public returns (bytes);

    function getSubscriptionData(bytes _subscriptionHash) view public returns (bytes);

    function getSubscriptionInterval(bytes _subscriptionHash) view public returns (uint);

    function getSubscriptionExternalId(bytes _subscriptionHash) view public returns (uint);

    function getSubscriptionDestination(bytes _subscriptionHash) view public returns (address);

    function getSubscriptionRecipient(bytes _subscriptionHash) view public returns (address);

    function getSubscriptionExpire(bytes _subscriptionHash) view public returns (uint);

    function getSubscriptionData(bytes _subscriptionHash) view public returns (bytes);


    function editSubscriptionValue(bytes _subscriptionHash, uint _newValue) public returns (bool);

    function editSubscriptionExpiration(bytes _subscriptionHash, uint _newExpires) public returns (bool);

    function editSubscriptionInterval(bytes _subscriptionHash, uint _newInterval) public returns (bool);

    function editSubscriptionExternalId(bytes _subscriptionHash, uint _newExternalId) public returns (bool);

    function editSubscriptionData(bytes _subscriptionHash, bytes _newData) public returns (bool);

    function editSubscriptionMeta(bytes _subscriptionHash, bytes _newMeta) public returns (bool);
}