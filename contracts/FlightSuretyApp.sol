pragma solidity >=0.4.24;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

//import "@openzeppelin/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
//import "./FlightSuretyData.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    //Added 
    FlightSuretyData flightSuretyData;


    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    //Insurance Constants

    address private contractOwner;          // Account used to deploy contract
    mapping(address => bool) multiCalls;    //Multi-call address
    address[] multiCallKeys = new address[](0);

 
    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
         // Modify to call data contract's status
        bool dataOperational = flightSuretyData.isOperational();
        require(dataOperational, "Contract is currently not operational");  
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier isFunded(address wallet){
        require(flightSuretyData.isAirlineFunded(wallet), "Airline is not funded");
        _;
    }

    modifier isAllowedToRegisterAirline(){
        if(msg.sender != contractOwner){
            require(flightSuretyData.isAirlineRegistered(msg.sender), "Caller is not a registred airline");
            require(flightSuretyData.isAirlineFunded(msg.sender), "Airline is not funded");
        }
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor(address dataContract) public 
    {
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() 
                            public 
                            returns(bool) 
    {
        return flightSuretyData.isOperational();  // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

  
   /**
    * @dev Add an airline to the registration queue
    *
    */   
    function registerAirline(string name, address wallet) external isAllowedToRegisterAirline returns(bool, uint256)
    {
        require(!flightSuretyData.isAirlineRegistered(wallet), "Airline is registred");
        uint airlineCount = flightSuretyData.getAirlineCount();
        uint votes_needed = airlineCount.div(2);
        if(airlineCount.mod(2) != 0){
            flightSuretyData.registerAirline(name, wallet);
            return (true, 1);
        } else {
            bool isDuplicated = multiCalls[msg.sender];
            require(!isDuplicated, "This function has already called");
            multiCalls[msg.sender] = true;
            multiCallKeys.push(msg.sender);
            if(multiCallKeys.length >= votes_needed){
                flightSuretyData.registerAirline(name, wallet);
                for (uint i = 0; i < multiCallKeys.length; i++){
                    multiCalls[multiCallKeys[i]] = false;
                }
                multiCallKeys = new address[](0);
                return (true, votes_needed);
            }
            return (false, multiCallKeys.length);
        }
    }

    // function getFunds() external {
    //     flightSuretyData.pay(msg.sender);
    // }


   /**
    * @dev Register a future flight for insuring.
    *
    */  
    function registerFlight(string name, uint256 timestamp, address airline) external
    {
        flightSuretyData.registerFlight(name, timestamp, airline);
    }
    
   /**
    * @dev Called after oracle has updated flight status
    *
    */  
    function processFlightStatus(
                                    address airline,
                                    string memory flight,
                                    uint256 timestamp,
                                    uint8 statusCode
                                )
                                internal
    {
        if(statusCode == 20){
            flightSuretyData.creditInsurees(flight, timestamp, airline);
        }
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(address airline,string flight, uint256 timestamp) external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));

        ResponseInfo storage response = oracleResponses[key];
        response.requester = msg.sender;
        response.isOpen = true;

        // oracleResponses[key] = ResponseInfo({
        //                                         requester: msg.sender,
        //                                         isOpen: true

        //                                     });

        emit OracleRequest(index, airline, flight, timestamp);
    } 


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;    

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;        
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle()
                            external
                            payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes() view external returns(uint8[3] memory)
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
                            uint8 index,
                            address airline,
                            string flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp)); 
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey(
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (                       
                                address account         
                            )
                            internal
                            returns(uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);
        
        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    function() external payable {}

// endregion

}   

interface FlightSuretyData{

    function isOperational() external view returns (bool);

    function setOperatingStatus(bool mode) external;

    function isAirlineRegistered(address wallet) external view returns (bool);

    function isAirlineFunded(address wallet) external view returns (bool);

    function registerAirline(string name, address wallet) external;

    function getAirlineCount() external view returns (uint256);

    function isFlightRegistered(string name, uint256 timestamp, address airline) external view returns (bool);

    function registerFlight(string name, uint timestamp, address airline) external;

    function buy(string flight, uint256 timestamp, address airline, address insuree) external payable;

    function creditInsurees(string flight, uint256 timestamp, address airline) external;

    function pay(address insuree) external;

    function fundForwarded(address sender) external payable;
}