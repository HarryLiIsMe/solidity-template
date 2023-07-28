//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '../interfaces/IMentalPoker.sol';

// Interface of basic game instance.
abstract contract IGameInstance {
    // Any custom card.
    struct AnyCard {
        bytes _encoded;
        bytes _masked;
        string _playingCardID;
    }

    // The player.
    struct Player {
        address _acc;
        bytes _key;
        bytes _memo;
        uint256[] _cards;
    }

    function players() public view virtual returns (address[] memory);

    function getPlayer(address _account) public view virtual returns (Player memory);

    function isPlayer(address _account) public view virtual returns (bool);

    function isFull() public view virtual returns (bool);

    function cardHash(bytes memory _card) public pure virtual returns (bytes32);

    function isOpen(uint256 _cardIndex) public view virtual returns (bool);

    function isUsed(uint256 _cardIndex) public view virtual returns (bool);

    function playingCard(uint256 _cardIndex) public view virtual returns (string memory);

    function getRevealTokens(uint256 _cardIndex) public view virtual returns (bytes[] memory);

    /// @dev Resets the game instance.
    /// @dev This allows the game instance to be reused.
    /// @param _params The public game parameters.
    /// @param _numPlayers The required number of players for game.
    function resetGame(bytes memory _params, uint256 _numPlayers) external virtual;

    /// @dev Player joins Game.
    /// @dev A player joins the game after checking everything (e.g., the initial deck).
    /// @dev A specific game may require a player to stake some tokens (table fee, etc.) on joining.
    /// @param _player The player's address.
    /// @param _pubKey The player's public game key.
    /// @param _memo The player memo (e.g., the player's nick name).
    /// @param _keyProof The proof of player's public game key ownership.
    function joinGame(
        address _player,
        bytes memory _pubKey,
        bytes memory _memo,
        bytes memory _keyProof
    ) external virtual;

    /// @dev A player might leave the game at any time before the game starts.
    /// @dev It depends on the specific game to decide wether or not to let a player leave the game before the game starts.
    /// @dev It depends on the specific game to decide wether or not to slash table fee if a player leaves the game.
    /// @param _player The player's address.
    function leaveGame(address _player) external virtual;

    /// @dev Every player must shuffle the deck.
    /// @param _player The player's address.
    /// @param _shuffledDeck The shuffled deck of masked cards.
    /// @param _shuffleProof The proof of shuffling.
    function shuffleDeck(address _player, bytes[] memory _shuffledDeck, bytes memory _shuffleProof) external virtual;

    /// @dev Verifies and adds reveal tokens.
    /// @param _player The player's address.
    /// @param _revealMine Whether the player reveals his/her own cards.
    /// @param _cardIndexes The indexes (in deck) of the cards.
    /// @param _revealTokens The reveal tokens for the cards.
    /// @param _revealProofs The reveal proofs for the cards.
    function addRevealTokens(
        address _player,
        bool _revealMine,
        uint256[] memory _cardIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) public virtual;

    /// @dev Ready to reveal cards or not.
    function readyToReveal(uint256[] memory _cardIndexes) public view virtual returns (bool);

    /// @dev Set card as used.
    function setUsed(uint256[] memory _cardIndexes) external virtual;

    /// @dev Number of used cards.
    function numUsed() public view virtual returns (uint256);
}

// A base contract for a zero-knowledge card game.
contract GameInstance is IGameInstance {
    // The controller contract.
    address public controller;

    // The mental poker contract.
    IMentalPoker public poker;

    // Public game parameters.
    bytes public params;

    // The initial deck of cards.
    AnyCard[] public deck;

    // Aggregated public key.
    bytes public sharedKey;

    // The required number of players for game.
    uint256 public numPlayers;

    // The number of players who joined the game.
    uint256 public numJoinedPlayers;

    // Each player has to pay a table fee to join the game.
    // The table fee is a deposit paid in advance to the contract to
    // 1> cover the gas cost of the contract owner.
    // 2> bind the players to their obligations(e.g., submit reveal tokens).
    uint256 public tableFee;

    // Number of cards already used.
    uint256 public numUsedCards;

    // Used cards.
    mapping(uint256 => bool) public usedCards;

    // The hashes of masked cards in the initial deck.
    bytes32[] public hashedCards;

    // The hashes of opened cards.
    bytes32[] public openedCards;

    // The mapping of card hash to masked card.
    mapping(bytes32 => bytes) public hashToMaskedCards;

    // The mapping of initial card's hash to playing card ID in initial deck.
    // This mapping WON'T change (during shuffing) once initial deck is set.
    // A playing card ID is a unique identifier for a card. For example
    // |-------------------------------------------------------------------------------|
    // | ID | Playing Card | ID | Playing Card | ID | Playing Card | ID | Playing Card |
    // | 2H |   2-Heart    | TC |   10-Club    | JD | Jack-Diamond | AS |  Ace-Spades  |
    // |-------------------------------------------------------------------------------|
    mapping(bytes32 => string) public hashToPlayingCards;

    // Player addresses.
    address[] public addrList;

    // The mapping of address to player struct.
    mapping(address => Player) public addrToPlayers;

    // The mapping of card index to reveal token set.
    mapping(uint256 => bytes[]) public revealTokens;

    event PlayerJoined(address indexed player, bytes pubKey, bytes memo);
    event PlayerLeft(address indexed player);
    event PlayerShuffledDeck(address indexed player, bytes[] shuffledDeck);
    event RevealedCards(uint256[] indexes, bytes32[] hashes);

    bytes32 public constant NONE = bytes32(0);

    modifier onlyController() {
        require(msg.sender == controller, 'Not the controller');
        _;
    }

    modifier onlyPlayers(address _account) {
        require(isPlayer(_account), 'Not a player');
        _;
    }

    function players() public view override returns (address[] memory) {
        return addrList;
    }

    function getPlayer(address _account) public view override returns (Player memory) {
        return addrToPlayers[_account];
    }

    function isPlayer(address _account) public view override returns (bool) {
        return addrToPlayers[_account]._acc != address(0);
    }

    function isFull() public view override returns (bool) {
        return numPlayers == addrList.length;
    }

    function cardHash(bytes memory _card) public pure override returns (bytes32) {
        return keccak256(_card);
    }

    function isOpen(uint256 _cardIndex) public view override returns (bool) {
        return openedCards[_cardIndex] != NONE;
    }

    function isUsed(uint256 _cardIndex) public view override returns (bool) {
        return usedCards[_cardIndex];
    }

    function playingCard(uint256 _cardIndex) public view override returns (string memory) {
        return hashToPlayingCards[openedCards[_cardIndex]];
    }

    function getRevealTokens(uint256 _cardIndex) public view override returns (bytes[] memory) {
        return revealTokens[_cardIndex];
    }

    /// @dev Creates a game containing initial deck of cards.
    /// @dev All players have to agree on this initial deck before joining the game.
    /// @param _controller The address of the controller contract.
    /// @param _poker The mental poker contract address.
    /// @param _params The public game parameters.
    /// @param _deck The initial deck of cards.
    /// @param _numPlayers The required number of players for game.
    constructor(
        address _controller,
        address _poker,
        bytes memory _params,
        AnyCard[] memory _deck,
        uint256 _numPlayers
    ) {
        controller = _controller;
        poker = IMentalPoker(_poker);
        params = _params;
        for (uint i = 0; i < _deck.length; i++) {
            deck.push(_deck[i]);
        }
        numPlayers = _numPlayers;
    }

    /// @dev Resets the game instance.
    /// @dev This allows the game instance to be reused.
    /// @param _params The public game parameters.
    /// @param _numPlayers The required number of players for game.
    function resetGame(bytes memory _params, uint256 _numPlayers) external virtual override onlyController {
        params = _params;
        numPlayers = _numPlayers;

        // Reset everything.
        numJoinedPlayers = 0;
        numUsedCards = 0;
        for (uint i = 0; i < deck.length; i++) {
            usedCards[i] = false;
        }
        for (uint i = 0; i < hashedCards.length; i++) {
            delete hashToMaskedCards[hashedCards[i]];
            delete revealTokens[i];
        }
        hashedCards = new bytes32[](0);
        openedCards = new bytes32[](0);
        for (uint i = 0; i < addrList.length; i++) {
            delete addrToPlayers[addrList[i]];
        }
        addrList = new address[](0);

        // Re-initialize the deck.
        initializeDeck();
    }

    /// @dev Player joins Game.
    /// @dev A player joins the game after checking everything (e.g., the initial deck).
    /// @dev A specific game may require a player to stake some tokens (table fee, etc.) on joining.
    /// @param _player The player's address.
    /// @param _pubKey The player's public game key.
    /// @param _memo The player memo (e.g., the player's nick name).
    /// @param _keyProof The proof of player's public game key ownership.
    function joinGame(
        address _player,
        bytes memory _pubKey,
        bytes memory _memo,
        bytes memory _keyProof
    ) external override onlyController {
        require(!isFull(), 'Game is full');
        require(!isPlayer(_player), 'Player already joined');
        for (uint i = 0; i < addrList.length; i++) {
            require(keccak256(addrToPlayers[addrList[i]]._key) != keccak256(_pubKey), 'PubKey already used');
            require(keccak256(addrToPlayers[addrList[i]]._memo) != keccak256(_memo), 'Memo already used');
        }
        require(poker.verifyKeyOwnership(params, _pubKey, _memo, _keyProof), 'Invalid key proof');

        // Add player.
        addrList.push(_player);
        addrToPlayers[_player] = Player({_acc: _player, _key: _pubKey, _memo: _memo, _cards: new uint256[](0)});

        // Compute aggregate key if number of players is reached.
        if (isFull()) {
            bytes[] memory pubKeys = new bytes[](numPlayers);
            for (uint i = 0; i < numPlayers; i++) {
                pubKeys[i] = addrToPlayers[addrList[i]]._key;
            }
            sharedKey = poker.computeAggregateKey(pubKeys);
            initializeDeck();
        }
        emit PlayerJoined(_player, _pubKey, _memo);
    }

    /// @dev A player might leave the game at any time before the game starts.
    /// @dev It depends on the specific game to decide wether or not to let a player leave the game before the game starts.
    /// @dev It depends on the specific game to decide wether or not to slash table fee if a player leaves the game.
    /// @param _player The player's address.
    function leaveGame(address _player) external override onlyController onlyPlayers(_player) {
        delete addrToPlayers[_player];
        for (uint i = 0; i < addrList.length; i++) {
            if (addrList[i] == _player) {
                addrList[i] = addrList[addrList.length - 1];
                addrList.pop();
                break;
            }
        }
        sharedKey = '';
        emit PlayerLeft(_player);
    }

    /// @dev Every player must shuffle the deck.
    /// @param _player The player's address.
    /// @param _shuffledDeck The shuffled deck of masked cards.
    /// @param _shuffleProof The proof of shuffling.
    function shuffleDeck(
        address _player,
        bytes[] memory _shuffledDeck,
        bytes memory _shuffleProof
    ) external override onlyController onlyPlayers(_player) {
        require(_shuffledDeck.length == hashedCards.length, 'Invalid deck');

        // Clean current deck
        bytes[] memory currentDeck = new bytes[](hashedCards.length);
        for (uint i = 0; i < hashedCards.length; i++) {
            bytes32 hs = hashedCards[i];
            currentDeck[i] = hashToMaskedCards[hs];
            delete hashToMaskedCards[hs];
        }
        require(poker.verifyShuffle(params, sharedKey, currentDeck, _shuffledDeck, _shuffleProof), 'Invalid shuffle');

        // Replace deck
        for (uint i = 0; i < _shuffledDeck.length; i++) {
            bytes32 hs = cardHash(_shuffledDeck[i]);
            hashedCards[i] = hs;
            hashToMaskedCards[hs] = _shuffledDeck[i];
        }
        emit PlayerShuffledDeck(_player, _shuffledDeck);
    }

    /// @dev Check if a card is in a player's hand.
    /// @param _player The player's address.
    function inHand(address _player, uint256 index) internal view returns (bool) {
        for (uint i = 0; i < addrToPlayers[_player]._cards.length; i++) {
            if (addrToPlayers[_player]._cards[i] == index) {
                return true;
            }
        }
        return false;
    }

    /// @dev Verifies and adds reveal tokens.
    /// @param _player The player's address.
    /// @param _revealMine Whether the player reveals his/her own cards.
    /// @param _cardIndexes The indexes (in deck) of the cards.
    /// @param _revealTokens The reveal tokens for the cards.
    /// @param _revealProofs The reveal proofs for the cards.
    function addRevealTokens(
        address _player,
        bool _revealMine,
        uint256[] memory _cardIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) public override onlyController {
        // Check against hand.
        for (uint i = 0; i < _cardIndexes.length; i++) {
            require(_cardIndexes[i] < hashedCards.length, 'Invalid card index');
            if (_revealMine) {
                require(inHand(_player, _cardIndexes[i]), 'Not your card!');
            } else {
                require(!inHand(_player, _cardIndexes[i]), "Cowboy... don't leak your own cards!");
            }
        }

        // Stores reveal tokens.
        bytes memory pubKey = addrToPlayers[_player]._key;
        for (uint i = 0; i < _cardIndexes.length; i++) {
            bytes32 hs = hashedCards[_cardIndexes[i]];
            bytes memory masked = hashToMaskedCards[hs];
            require(poker.verifyReveal(params, pubKey, _revealTokens[i], masked, _revealProofs[i]), 'Invalid reveal');
            revealTokens[_cardIndexes[i]].push(_revealTokens[i]);
        }

        // Reveal cards if ready.
        if (readyToReveal(_cardIndexes)) {
            revealCards(_cardIndexes);
        }
    }

    /// @dev Ready to reveal cards or not.
    function readyToReveal(uint256[] memory _cardIndexes) public view override returns (bool) {
        for (uint i = 0; i < _cardIndexes.length; i++) {
            if (revealTokens[_cardIndexes[i]].length != numPlayers) {
                return false;
            }
        }
        return true;
    }

    /// @dev Reveal cards by indexes.
    /// @param _cardIndexes The indexes (in deck) of the cards.
    function revealCards(uint256[] memory _cardIndexes) internal {
        uint256 num = _cardIndexes.length;
        for (uint i = 0; i < num; i++) {
            require(_cardIndexes[i] < hashedCards.length, 'Invalid card index');
            require(openedCards[_cardIndexes[i]] == NONE, 'Card already revealed');
            require(revealTokens[_cardIndexes[i]].length == numPlayers, 'Incorrect number of reveal tokens');
        }

        // Reveal cards.
        uint256[] memory openIndexes = new uint256[](num);
        bytes32[] memory openHashes = new bytes32[](num);
        for (uint i = 0; i < num; i++) {
            bytes32 hs = hashedCards[_cardIndexes[i]];
            bytes memory masked = hashToMaskedCards[hs];
            bytes memory opened = poker.reveal(revealTokens[_cardIndexes[i]], masked);
            bytes32 openHash = cardHash(opened);
            require(bytes(hashToPlayingCards[openHash]).length > 0, 'Reveal failed... cheating?');

            openIndexes[i] = _cardIndexes[i];
            openHashes[i] = openHash;
            openedCards[_cardIndexes[i]] = openHash;
        }
        emit RevealedCards(openIndexes, openHashes);
    }

    /// @dev Set card as used.
    function setUsed(uint256[] memory _cardIndexes) external override onlyController {
        for (uint i = 0; i < _cardIndexes.length; i++) {
            numUsedCards++;
            usedCards[_cardIndexes[i]] = true;
        }
    }

    /// @dev Number of used cards.
    function numUsed() public view override returns (uint256) {
        return numUsedCards;
    }

    /// @dev Initialize the deck.
    function initializeDeck() private {
        for (uint i = 0; i < deck.length; i++) {
            deck[i]._masked = poker.mask(params, sharedKey, deck[i]._encoded);
            bytes32 hs = cardHash(deck[i]._masked);
            hashedCards.push(hs);
            openedCards.push(NONE);
            hashToMaskedCards[hs] = deck[i]._masked;
            hashToPlayingCards[hs] = deck[i]._playingCardID;
        }
    }
}
