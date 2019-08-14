pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721Metadata.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721MetadataMintable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721Metadata.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/lifecycle/Pausable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/drafts/Counters.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "tabookey-gasless/contracts/GsnUtils.sol";
import "tabookey-gasless/contracts/IRelayHub.sol";
import "tabookey-gasless/contracts/RelayRecipient.sol";


/// @title A Nifties exchange game to incentivize tourism and onboard to crypto
/// @author santteegt
/// @notice NFTs Market price is artificially calculated based on randomness feed from previous block hashes and user demand
/// @dev Contract can be upgraded through a proxy contract supplied by OpenZeppelin SDK
/// @dev Contract can be used with the GSN
contract StampCollectible is Initializable, RelayRecipient, Pausable, ERC721MetadataMintable {
    /// Library used to perform unit increment/decrements
    using Counters for Counters.Counter;
    /// Library to avoid overflow/underflow bugs
    using SafeMath for uint256;

    /// Data structure that represents a NFT Tourist stamp
    struct Stamp {
        uint256 price;
        uint256 maxClones;
        uint256 inWild;
        uint256 clonedFrom;
    }

    struct ClonedStamp {
        bool owned;
        uint tokenId;
    }

    /// Tracks the total minted stamps
    Counters.Counter public totalMinted;
    /// Store all minted stamps
    // Stamp[] public stamps;
    mapping (uint256 => Stamp) public stamps;
    ///
    mapping (uint256 => bool) public ownedTokensIndex;
    /// Game parameter to provide an scarce amount of stamps
    uint256 public maxClones;
    /// Game parameter thah establish the depth of blockhashes to scan during NFT price estimate
    // uint8 constant private PRICEDEPTH = 255;
    uint8 private priceDepth;
    /// Cost multiplier to transform NFT price (in finney) to ETH
    // uint256 constant private COSTMULTIPLIER = 1000000000000;
    uint256 private costMultiplier;

    /// Maintains a record of minted NFTS and ownership per account
    // mapping (address => mapping (uint256 => bool)) public balances;
    mapping (address => mapping (uint256 => ClonedStamp)) public balances;

    /// Verify that the priceDepth parameters is within the max No. of historical blocks a contract can track
    modifier checkMaxBlockDepth(uint _value) {
        require(_value > 0 && _value <= 255, "Price Depth parameter must be within then range [1-255]");
        _;
    }

    /// Triggered when a new Gen0 stamp is minted by the contract owner
    event MintedStamp(address indexed owner, uint256 tokenId, uint256 price);
    /// Triggered when a stamp is cloned and minted to a user
    event NewStamp(address indexed owner, uint256 tokenId, uint256 price);
    /// Triggered when a cloned stamp is returned to the contract and thus burned
    event BurnedStamp(address indexed owner, uint256 tokenId, uint256 clonedTokenId);

    /// @dev This constructor was deprecated in favour of the initialize function
    /// @dev so the contract can be upgraded through a proxy contract
    // constructor(uint256 _maxClones) ERC721Metadata("CryptoStamps", "STAMPS") public {
    //     maxClones = _maxClones;
    //     if(stamps.length == 0) {
    //         Stamp memory _dummy = Stamp({
    //             price: 0, maxClones: 0, inWild: 0, clonedFrom: 0});
    //         stamps.push(_dummy);
    //     }
    // }

    /** @dev Initialize current and derived contracts
      * @param _maxClones Maximum number of clones allowed per Gen0 NFT
      * @param _priceDepth Game parameter thah establish the depth of blockhashes to scan during NFT price estimate
      * @param _costMultiplier Cost multiplier to transform NFT price (in finney) to ETH
      * @param _name NFT name
      * @param _symbol NFT symbol
      */
    function initialize(uint256 _maxClones, uint8 _priceDepth,
        uint256 _costMultiplier, string memory _name, string memory _symbol)
        public
        initializer // ensures that the contract only initilizes once
        checkMaxBlockDepth(_maxClones) {

            Pausable.initialize(msg.sender);
            if(!ERC721._hasBeenInitialized()) {
                ERC721.initialize();
            }
            if(!ERC721Metadata._hasBeenInitialized()) {
                ERC721Metadata.initialize(_name, _symbol);
            }
            ERC721MetadataMintable.initialize(msg.sender);

            maxClones = _maxClones;
            priceDepth = _priceDepth;
            costMultiplier = _costMultiplier;

            Stamp memory _dummy = Stamp({
                price: 0, maxClones: 0, inWild: 0, clonedFrom: 0});
            stamps[0] = _dummy;
    }

    /** @dev Calculate the new NFT price based on demand and randomness based on past block hashes
      * @notice Market value is artificially generated for the game using the entropy found in past block hashes
      * @param _index NFT index in storage
      * @return uint16 NFt new estimate market price
      */
    function getNFTPrice(uint256 _index) internal view returns (uint16) {
        Stamp memory stamp = stamps[_index];
        uint256 x = 0;
        for(uint8 depth = priceDepth; depth > 0 ; depth--) {
          bytes32 blockHash = blockhash(block.number-depth);
          x += convert(blockHash[_index * 2]) << 8 | convert(blockHash[_index * 2 + 1]);
        }
        return uint16(x / priceDepth) + uint16(stamp.inWild);
    }

    /** @dev Helper function to convert a bytes32 to uint
      * @param _b bytes32 data hash
      * @return uint uint representation of _b
      */
    function convert(bytes32 _b) internal pure returns (uint) {
        return uint(_b);
    }

    /** @dev Mint a Gen0 stamp
      * @notice This function can only be called by the contract owner
      * @param _priceFinney Initial NFT price in finney
      * @param _tokenURI URI of the associated digital collectible art
      * @return bool true if Gen0 NFT is minted
      */
    function mint(uint256 _priceFinney, string memory _tokenURI) public
        onlyMinter
        whenNotPaused
        returns (bool) {
        Stamp memory collectible = Stamp({
            price: _priceFinney.mul(costMultiplier),
            maxClones: maxClones,
            inWild: 0,
            clonedFrom: 0
        });
        totalMinted.increment();
        uint256 tokenId = totalMinted.current();
        stamps[tokenId] = collectible;
        ownedTokensIndex[tokenId] = true;
        emit MintedStamp(msg.sender, tokenId, _priceFinney);

        return mintWithTokenURI(msg.sender, tokenId, _tokenURI);
    }

    /** @dev Allow to buy a cloned stamp from minted Gen0 NFTs
      * @param _tokenId Gen0 NFT index in storage
      * @return uint tokenId corresponding to the cloned NFT
      */
    function buyStamp(address sender, uint256 _tokenId) public payable
        whenNotPaused
        returns (uint) {
            Stamp storage stamp = stamps[_tokenId];
            require(stamp.clonedFrom == 0, "You can only generate new stamps from Gen0 NFTs");
            require(!balances[sender][_tokenId].owned, "You already own this stamp");
            require(stamp.inWild.add(1) <= stamp.maxClones, "Max clones have been reached");
            require(msg.value >= stamp.price, "Not enough funds");
            stamp.inWild = stamp.inWild.add(1);
            stamp.price = uint256(getNFTPrice(_tokenId)).mul(costMultiplier);

            /// mint and increase total minted
            totalMinted.increment();
            uint tokenId = totalMinted.current();
            Stamp memory clonedStamp = Stamp({
                price: stamp.price,
                maxClones: 0,
                inWild: 0,
                clonedFrom: _tokenId
            });
            stamps[tokenId] = clonedStamp;
            ownedTokensIndex[tokenId] = true;
            _mint(sender, tokenId);
            balances[sender][_tokenId].owned = true;
            balances[sender][_tokenId].tokenId = tokenId;

            // emit NewStamp(msg.sender, _tokenId, stamp.price);
            emit NewStamp(sender, tokenId, msg.value);
            return tokenId;
    }

    /** @dev Allow to sell an owned stamp and profit/loose based on current market price
      * @param _tokenId Gen0 NFT index in storage
      * @return bool true if processed
      */
    function sellStamp(uint256 _tokenId) public
        whenNotPaused
        returns (bool) {
            address sender = getSender();
            require(balances[sender][_tokenId].owned, "User does not own this stamp");
            Stamp storage stamp = stamps[_tokenId];
            uint256 payout = stamp.price;
            require(address(this).balance >= payout, "Prize pot is almost empty so it is no longer possible to sell stamps");
            stamp.inWild = stamp.inWild.sub(1);
            stamp.price = uint256(getNFTPrice(_tokenId)).mul(costMultiplier);

            ClonedStamp storage clonedStamp = balances[sender][_tokenId];
            clonedStamp.owned = false;

            // burn token
            _burn(clonedStamp.tokenId);
            ownedTokensIndex[clonedStamp.tokenId] = false;

            emit BurnedStamp(sender, _tokenId, clonedStamp.tokenId);
            delete stamps[clonedStamp.tokenId];
            // TODO: disabled when upgrading the contract
            // msg.sender.transfer(payout); // This approach can block the asset if owned by a bad actor (contract account)
            // TODO: to be addded in an upgraded version of the contract
            outstandingBalance[sender] = outstandingBalance[sender].add(payout);
            return true;
    }

    /** @dev Fallback function to allow the contract accept deposits in ETH
      * @notice deposits can be crodwsourced to fund the Prize pot
      */
    function () external payable whenNotPaused {

    }

    /// Maintains a record of outstanding balance owned to users before withdrawal
    /// Required to implement the Pull vs Push design pattern for payments
    /// TODO: to be included later in an upgradable contract
    mapping (address => uint) public outstandingBalance;

    /// Triggered when a user withdraw her outstanding balance from selling stamps in the market
    /// TODO: this has to be added as an upgrade
    event WithdrawnBalance(address indexed owner, uint256 amount);

    /** @dev Allow users to withdraw funds from sold stamps. Required to enable a pull vs push design pattern
      * @return bool true if processed
      */
    /// TODO: to be addded in an upgraded version of the contract
    function withdraw() public whenNotPaused returns (bool) {
        address sender = getSender();
    	require(outstandingBalance[sender] > 0, "You dont have any outstanding balance to withdraw");
    	uint amount = outstandingBalance[sender];
    	outstandingBalance[sender] = 0;
        hasWithdrawn[sender] = true;
        emit WithdrawnBalance(sender, amount);
        msg.sender.transfer(amount);
    	return true;
    }

    /// Logs if a user already withdraw some balance from the pot
    mapping (address => bool) public hasWithdrawn;

    /// Verifies that a call is done by the relayer
    modifier onlyByRelayer() {
        require(msg.sender == getHubAddr(), "Transaction can only be perfomed by the relayer");
        _;
    }

    /// Triggered when a stamp is airdroped through the relayer
    event AirdropedStamp(address indexed sender, uint tokenId);

    /**
     * @dev Airdrop a stamp throguh a relayer in the GSN
     * param _tokenId Gen0 NFT index in storage
     * @return uint tokenId corresponding to the cloned NFT
     */
    function airdropStamp(uint256 _tokenId) public
        whenNotPaused
        onlyByRelayer
        returns (uint) {
            address sender = getSender();
            Stamp storage stamp = stamps[_tokenId];
            require(stamp.clonedFrom == 0, "You can only generate new stamps from Gen0 NFTs");
            require(!balances[sender][_tokenId].owned, "You already own this stamp");
            require(stamp.inWild.add(1) <= stamp.maxClones, "Sorry! This Stamp is not currently available");
            stamp.inWild = stamp.inWild.add(1);

            /// mint and increase total minted
            totalMinted.increment();
            uint tokenId = totalMinted.current();
            Stamp memory clonedStamp = Stamp({
                price: stamp.price,
                maxClones: 0,
                inWild: 0,
                clonedFrom: _tokenId
            });
            stamps[tokenId] = clonedStamp;
            ownedTokensIndex[tokenId] = true;
            _mint(sender, tokenId);
            balances[sender][_tokenId].owned = true;
            balances[sender][_tokenId].tokenId = tokenId;

            emit AirdropedStamp(sender, tokenId);
            emit NewStamp(sender, tokenId, stamp.price);
            return tokenId;
    }

    /** @dev It's an error code designed to help the DApp identify the reason. Low negatives are reserved for known issues but you can add your own errors in your contract
      * @param _relay RelayHub address
      * @param _from Tx sender
      * @param  _encodedFunction encoded Function being called
      * @param _transactionFee tx fee
      * @param _gasPrice tx gas price
      * @param _gasLimit tx gas limit
      * @param _nonce tx nonce
      * @param _approvalData tx data
      * @param _maxPossibleCharge max possible charge per tx
      * @return uint256 0 means you accept sponsoring the relayed transaction. Anything else indicates rejection.
      * @return bytes Error message
      */
    function acceptRelayedCall(address _relay, address _from, bytes calldata _encodedFunction,
            uint256 _transactionFee, uint256 _gasPrice, uint256 _gasLimit, uint256 _nonce,
            bytes calldata _approvalData, uint256 _maxPossibleCharge)
            external view returns (uint256, bytes memory) {

                if(hasWithdrawn[_from]) {
                    return (10, "User has already withdrawn some balance");
                }
                return (0, "");
    }

    /** @dev Inform of the maximum cost the call may have, and can be used to charge the user in advance.
      * @notice This is useful if the user may spend their allowance as part of the call, so you can lock some funds here.
      * @param _context tx data
      * @return bytes32 the maximum cost the call may have
      */
    function preRelayedCall(bytes calldata _context) /*relayHubOnly*/ external returns (bytes32) {
        return bytes32(uint(123456));
    }

    /** @dev The success flag indicates whether it was relayed successfully or not. This is where you would usually subtract from the user's remaining credit
      * @param _context tx data
      * @param _success True if tx was relayed
      * @param _actualCharge charged value
      * @param _preRetVal preRetVal
      */
    function postRelayedCall(bytes calldata _context, bool _success, uint _actualCharge, bytes32 _preRetVal) /*relayHubOnly*/ external {
    }

    function updateRelayHub(IRelayHub _rhub) public onlyMinter {
        setRelayHub(_rhub);
    }
}
