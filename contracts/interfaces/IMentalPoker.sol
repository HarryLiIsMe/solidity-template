//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title Zero-knowledge mental poker interface.
interface IMentalPoker {
    /// @dev Verify the ownership of a `pubKey`.
    /// @param params Public parameters of the game.
    /// @param pubKey The public game key to verify.
    /// @param memo The player memo (e.g., the player's nick name).
    /// @param keyProof The zero-knowledge proof of the key ownership.
    /// @return Ture if verified, false otherwise.
    function verifyKeyOwnership(
        bytes calldata params,
        bytes calldata pubKey,
        bytes calldata memo,
        bytes calldata keyProof
    ) external pure returns (bool);

    /// @dev Compute the public aggregate key.
    /// @param pubKeys List of all players' public game keys.
    /// @return The public aggregate key.
    function computeAggregateKey(bytes[] calldata pubKeys) external pure returns (bytes memory);

    /// @dev Mask intial encoded card with the public aggregate key.
    /// @param params Public parameters of the game.
    /// @param sharedKey The public aggregate key.
    /// @param encoded The initial encoded card.
    /// @return The masked card.
    function mask(
        bytes calldata params,
        bytes calldata sharedKey,
        bytes calldata encoded
    ) external pure returns (bytes memory);

    /// @dev Verify a shuffling of the deck.
    /// @param params Public parameters of the game.
    /// @param sharedKey The public aggregate key.
    /// @param curDeck The current deck.
    /// @param newDeck The shuffled deck.
    /// @param shuffleProof The zero-knowledge proof of the shuffling.
    /// @return Ture if verified, false otherwise.
    function verifyShuffle(
        bytes calldata params,
        bytes calldata sharedKey,
        bytes[] calldata curDeck,
        bytes[] calldata newDeck,
        bytes calldata shuffleProof
    ) external pure returns (bool);

    /// @dev Verify a shuffling of the deck.
    /// @param params Public parameters of the game.
    /// @param pubKey The player's public game key.
    /// @param revealToken The reveal token for the masked card.
    /// @param masked The masked card.
    /// @param revealProof The zero-knowledge proof of the reveal.
    /// @return Ture if verified, false otherwise.
    function verifyReveal(
        bytes calldata params,
        bytes calldata pubKey,
        bytes calldata revealToken,
        bytes calldata masked,
        bytes calldata revealProof
    ) external pure returns (bool);

    /// @dev Reveal a masked card.
    /// @param revealTokens The full list of reveal tokens.
    /// @param masked The masked card.
    /// @return The revealed card.
    function reveal(
        bytes[] calldata revealTokens,
        bytes calldata masked
    ) external pure returns (bytes memory);
}
