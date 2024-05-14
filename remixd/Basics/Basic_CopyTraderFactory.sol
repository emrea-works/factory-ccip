//SPDX-License-Identifier: MIT
pragma solidity 0.8;

contract MyCopyTrader {

    address public immutable owner;    

    constructor(address _owner) payable {
        owner = _owner;
        returnAddress();
    }

    function returnAddress() public view returns(address) {
        return address(this);
    }

    function getOwner() public view returns(address) {
        return owner;
    }
}

contract CopyTraderFactory {

    event NewTraderCreated(address newTraderAddress);

    function create(/* string salt */) public {
        
        /** user create2 to secure the address and sender
         * bytes20 salt = keccak256(bytes('my_salt/some_enc_text_from_backend'));
         * address newContractAddress = address(
         *     uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt)))
         * );
        _*/

        MyCopyTrader newTrader = new MyCopyTrader(msg.sender);
        emit NewTraderCreated(address(newTrader));
    }
}