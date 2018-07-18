pragma solidity 0.4.24;

contract IRegistry {

    mapping(address => bool) public isOperator;

    function handlePaymentNotification(address, uint, uint, bool);

    function handleNewSubscription(address, address, uint, uint);

}