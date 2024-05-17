//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Imports for Factory
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

// Imports for CCIP
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
import {IERC165} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract MyCopyTrader is Initializable {
    
    address public owner;    

    function initialize(address _owner) public {
        owner = _owner;
    }

    function returnAddress() public view returns(address) {
        return address(this);
    }

    function getOwner() public view returns(address) {
        return owner;
    }
}


contract CopyTraderFactory is CCIPReceiver, ReentrancyGuard {

    address public immutable implementation;
    LinkTokenInterface linkToken;

    constructor(address _router, address link) CCIPReceiver(_router) {
        implementation = address(new MyCopyTrader());
        linkToken = LinkTokenInterface(link);
    }

    /* CCIP Events & Definitions */ 
    event MessageSent(
        bytes32 indexed messageId, 
        uint64 indexed destinationChainSelector, 
        address receiver, 
        Message indexed message,
        Client.EVMTokenAmount tokenAmount, 
        uint256 fees 
    );

    event MessageReceived(
        bytes32 indexed messageId, 
        uint64 indexed sourceChainSelector, 
        address sender, 
        Message indexed message,
        Client.EVMTokenAmount tokenAmount 
    );
    // Struct to hold details of a message.
    struct MessageIn {
        uint64 sourceChainSelector; 
        address sender; 
        Message message; // message data
        address token; // received token.
        uint256 amount; // received amount.
    }

    enum MessageStatus { Created, InProgress, Completed, Canceled }

    struct Message {
        uint256 messageId;
        address sender; 
        address receiver; 
        uint256 amount; 
        address fromCurrency; 
        string toCurrency; 
        Network target;
        MessageStatus status; 
    } 

    struct Network {
        string name;
        address router; // Other Message Contract or EOA of an agent
        uint64 selector; // destinationChainSelector
        address messageContract;
    }


    /* CCIP Messaging Database */
    bytes32[] public receivedMessages; // Keeps track of the IDs of received messages.
    mapping(bytes32 => MessageIn) public messageDetail; // Message details, message id => message data.
    mapping(uint256 => mapping(address => uint256)) public deposits; // Message => sender ==> amount


    /* CCIP Functions */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        bytes32 messageId = any2EvmMessage.messageId; 
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; 
        address sender = abi.decode(any2EvmMessage.sender, (address)); // sender contract's address
        // Message [ + unlocking code] 
        Message memory message = abi.decode(any2EvmMessage.data, (Message)); // the Message data 

        // Collect tokens transferred. This increases this contract's balance for that Token.
        Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage.destTokenAmounts;
        address token = tokenAmounts[0].token;
        uint256 amount = tokenAmounts[0].amount;

        receivedMessages.push(messageId);
        MessageIn memory detail = MessageIn(sourceChainSelector, sender, message, token, amount);
        messageDetail[messageId] = detail;

        emit MessageReceived(messageId, sourceChainSelector, sender, message, tokenAmounts[0]);

        deposits[message.messageId][token] += amount; // Store depositor data
    }

    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        address tokenToTransfer,
        uint256 transferAmount
    ) internal returns (bytes32 messageId) {
        Message memory message;

        // Compose the EVMTokenAmountStruct. This struct describes the tokens being transferred using CCIP.
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);

        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: tokenToTransfer, 
            amount: transferAmount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // encoded receiver address
            data: abi.encode(message), // encoded string message 
            tokenAmounts: tokenAmounts,
            extraArgs: "", /* Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false}) 
            ),*/
            feeToken: address(linkToken) 
        });

        // Initialize a router client instance to interact with cross-chain
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        // Approve the Router to send LINK tokens on contract's behalf. Fees are in LINK
        linkToken.approve(address(router), fees);

        require(IERC20(tokenToTransfer).approve(address(router), transferAmount), "Failed to approve router");

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, destinationChainSelector, receiver, message, tokenAmount, fees);

        deposits[message.messageId][tokenToTransfer] -= transferAmount;
        
        // Return the message ID
        return messageId;
    }


    /* TRADER FUNCTIONALITY */

    event NewTraderCreated(address newTraderAddress);

    function deployTrader(/*, string salt */) public {
        
        /** user create2 to secure the address and sender
         * bytes20 salt = keccak256(bytes('my_salt/some_enc_text_from_backend'));
         * address newContractAddress = address(
         *     uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt)))
         * );
        _*/

        address payable clone = payable(Clones.clone(implementation));
        MyCopyTrader newTrader = MyCopyTrader(clone);
        newTrader.initialize(msg.sender);
        
        emit NewTraderCreated(address(newTrader));
    }
}