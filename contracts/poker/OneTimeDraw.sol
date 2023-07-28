//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import './GameInstance.sol';

// Interface OneTimeDraw game instance.
interface IOneTimeDraw {
    /// Player draws all his/her cards at once.
    event PlayerDrewCards(address indexed player, uint256[] cards);

    /// @dev A player draws all his/her (`num` of) cards from deck and submit reveal tokens for other players' cards.
    /// @dev This function is used for games that require players to draw all their cards at once.
    /// @param _player The player's address.
    /// @param _myIndexes The indexes (in deck) of the player's cards.
    /// @param _othersIndexes The indexes (in deck) of the others' cards.
    /// @param _revealTokens The reveal tokens for others' cards.
    /// @param _revealProofs The reveal proofs for others' cards.
    function drawCardsNSubmitRevealTokens(
        address _player,
        uint256[] memory _myIndexes,
        uint256[] memory _othersIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external;

    /// @dev A player folds his/her hand.
    /// @dev A player may leave game once he/she folds hand.
    /// @dev It's developer's responsibility to pass in the correct list of necessary un-revealed cards.
    /// @dev It's developer's responsibility to slash the player who refuses to fold AND submit reveal tokens.
    /// @param _player The player's address.
    /// @param _unrevealedIndexes The indexes (in deck) of un-revealed cards.
    /// @param _revealTokens The reveal tokens for un-revealed cards.
    /// @param _revealProofs The reveal proofs for un-revealed cards.
    function foldCards(
        address _player,
        uint256[] memory _unrevealedIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external;

    /// @dev A player shows his/her hand.
    /// @dev It's developer's responsibility to pass in the correct list of cards.
    /// @param _player The player's address.
    /// @param _cardIndexes The indexes (in deck) of player's cards.
    /// @param _revealTokens The reveal tokens for player's cards.
    /// @param _revealProofs The reveal proofs for player's cards.
    function showHand(
        address _player,
        uint256[] memory _cardIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external;
}

// A game that players draw all their cards at once.
contract OneTimeDrawInstance is GameInstance {
    /// Player draws all his/her cards at once.
    event PlayerDrewCards(address indexed player, uint256[] cards);

    /// @dev Creates a game containing initial deck of cards.
    /// @dev All players have to agree on this initial deck before joining the game.
    /// @param _controller The controller contract address.
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
    ) GameInstance(_controller, _poker, _params, _deck, _numPlayers) {}

    /// @dev A player draws all his/her (`num` of) cards from deck and submit reveal tokens for other players' cards.
    /// @dev This function is used for games that require players to draw all their cards at once.
    /// @param _player The player's address.
    /// @param _myIndexes The indexes (in deck) of the player's cards.
    /// @param _othersIndexes The indexes (in deck) of the others' cards.
    /// @param _revealTokens The reveal tokens for others' cards.
    /// @param _revealProofs The reveal proofs for others' cards.
    function drawCardsNSubmitRevealTokens(
        address _player,
        uint256[] memory _myIndexes,
        uint256[] memory _othersIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external onlyPlayers(_player) {
        // Draws my cards.
        require(_myIndexes.length > 0, 'Invalid number of cards to draw');
        require(addrToPlayers[_player]._cards.length == 0, 'Player already drew cards');
        for (uint i = 0; i < _myIndexes.length; i++) {
            require(_myIndexes[i] < hashedCards.length, 'Invalid card index');
            require(usedCards[_myIndexes[i]] == false, 'Card already drawn');
            addrToPlayers[_player]._cards.push(_myIndexes[i]);
        }

        // Submits reveal tokens for other players' cards.
        submitOthersRevealTokens(_player, _othersIndexes, _revealTokens, _revealProofs);
        emit PlayerDrewCards(_player, addrToPlayers[_player]._cards);
    }

    /// @dev A player submits reveal tokens for all other players' cards.
    /// @dev Other players need these reveal tokens to see their cards.
    /// @dev As players may leave at any time (e.g. due to network issue), the reveal tokens must be collected before they leave.
    /// @dev It's developer's responsibility to pass in the correct list of indexes of the others' cards according to their game rules.
    /// @dev It's developer's responsibility to slash the player who refuses to submit reveal tokens.
    /// @dev Given 4 players, once 3 players submit their reveal tokens, the 4th player can see his/her cards immediately.
    /// @param _player The player's address.
    /// @param _otherIndexes The indexes (in deck) of the others' cards.
    /// @param _revealTokens The reveal tokens for others' cards.
    /// @param _revealProofs The reveal proofs for others' cards.
    function submitOthersRevealTokens(
        address _player,
        uint256[] memory _otherIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) private {
        require(_otherIndexes.length == _revealTokens.length, 'Number of cards and reveal tokens do not match');
        require(_otherIndexes.length == _revealProofs.length, 'Number of cards and reveal proofs do not match');
        addRevealTokens(_player, false, _otherIndexes, _revealTokens, _revealProofs);
    }

    /// @dev A player folds his/her hand.
    /// @dev A player may leave game once he/she folds hand.
    /// @dev It's developer's responsibility to pass in the correct list of necessary un-revealed cards.
    /// @dev It's developer's responsibility to slash the player who refuses to fold AND submit reveal tokens.
    /// @param _player The player's address.
    /// @param _unrevealedIndexes The indexes (in deck) of un-revealed cards.
    /// @param _revealTokens The reveal tokens for un-revealed cards.
    /// @param _revealProofs The reveal proofs for un-revealed cards.
    function foldCards(
        address _player,
        uint256[] memory _unrevealedIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external onlyPlayers(_player) {
        uint num = _unrevealedIndexes.length;
        require(num == _revealTokens.length, 'Incorrect number of reveal tokens');
        require(num == _revealProofs.length, 'Incorrect number of reveal proofs');

        if (num > 0) {
            addRevealTokens(_player, false, _unrevealedIndexes, _revealTokens, _revealProofs);
        }
    }

    /// @dev A player shows his/her hand.
    /// @dev It's developer's responsibility to pass in the correct list of cards.
    /// @param _player The player's address.
    /// @param _cardIndexes The indexes (in deck) of player's cards.
    /// @param _revealTokens The reveal tokens for player's cards.
    /// @param _revealProofs The reveal proofs for player's cards.
    function showHand(
        address _player,
        uint256[] memory _cardIndexes,
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external onlyPlayers(_player) {
        uint num = _cardIndexes.length;
        require(num > 0, 'Invalid number of cards to show');
        require(num == _revealTokens.length, 'Incorrect number of reveal tokens');
        require(num == _revealProofs.length, 'Incorrect number of reveal proofs');

        addRevealTokens(_player, true, _cardIndexes, _revealTokens, _revealProofs);
    }
}
