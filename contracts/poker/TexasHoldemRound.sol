//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./GameInstance.sol";
import "./OneTimeDraw.sol";

// The rounds of Texas Hold'em.
contract TexasHoldemRound is AccessControl {
    enum GameStatus {
        AwaitPlayers,
        PickButton,
        ShuffleDeck,
        SmallBlindBet,
        BigBlindBet,
        DrawCards,
        PreFlopBet,
        Flop,
        FlopBet,
        Turn,
        TurnBet,
        River,
        RiverBet,
        Showdown,
        End,
        Timeout
    }

    using SafeMath for uint256;

    uint256 public constant SMALL_BLIND = 0.01 ether;
    uint256 public constant BIG_BLIND = 0.02 ether;
    uint256 public constant MIN_RAISE = 2;
    uint256 public constant TIMEOUT_ACT = 120; // 120 seconds
    uint16[2] public COMMISSION = [1, 1000]; // 0.1%

    // The game instance.
    address public game;

    // The game status.
    GameStatus public status;

    // Each player has to pay a table fee to join the game.
    // The table fee is a deposit paid in advance to the contract to
    // 1> cover the gas cost of the contract owner.
    // 2> bind the players to their obligations(e.g., submit reveal tokens).
    uint256 public tableFee;

    // The players.
    address[] public players;

    // The button player.
    uint256 public button;

    // The next player to take action.
    address public player2Act;

    // The deadline for next action.
    uint256 public deadline;

    // The pot.
    uint256 public pot;

    // The winner.
    address public winner;

    // The last player who raised.
    address public whoRaised;

    // The first player who showed down.
    address public whoShowed;

    // Each player's bet.
    mapping(address => uint256) public playerBets;

    // The players done with the game.
    mapping(address => bool) public playerDone;

    event ButtonPicked(address indexed player);
    event BetSmallBlind(address indexed player, uint256 amount);
    event BetBigBlind(address indexed player, uint256 amount);
    event PlayerCalled(address indexed player, uint256 amount);
    event PlayerRaised(address indexed player, uint256 amount);
    event PlayerChecked(address indexed player, uint256 amount);
    event PlayerFolded(address indexed player);
    event PlayerShowed(address indexed player, uint256[] cards);
    event GameEnded(address indexed winner, uint256 amount);
    event GameTimeout(address indexed blame, uint256 fine);

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    modifier whenBet() {
        require(
            status == GameStatus.PreFlopBet ||
                status == GameStatus.FlopBet ||
                status == GameStatus.TurnBet ||
                status == GameStatus.RiverBet,
            "Action not allowed"
        );
        _;
    }

    modifier whenFlip() {
        require(
            status == GameStatus.Flop || status == GameStatus.Turn || status == GameStatus.River,
            "Action not allowed"
        );
        _;
    }

    modifier gameInProgress() {
        require(status != GameStatus.AwaitPlayers, "Game not started");
        require(status != GameStatus.PickButton, "Game not started");
        require(status != GameStatus.End, "Game already ended");
        require(status != GameStatus.Timeout, "Game already timeout");
        _;
    }

    modifier gameFinish() {
        require(status == GameStatus.End || status == GameStatus.Timeout, "Game not finished");
        _;
    }

    modifier whenTimeout(address _player) {
        require(_player == player2Act, "Not the player's turn");
        require(block.number > deadline, "Not timeout yet");
        _;
    }

    modifier inGame() {
        require(IGameInstance(game).isPlayer(msg.sender), "You are not in the game");
        require(!playerDone[msg.sender], "You are done with the game");
        _;
    }

    function playerBet(address _player) public view returns (uint256) {
        return playerBets[_player];
    }

    function playerRemain() public view returns (uint256 count) {
        for (uint256 i = 0; i < players.length; i++) {
            if (!playerDone[players[i]]) {
                count++;
            }
        }
    }

    constructor(uint256 _tableFee) {
        tableFee = _tableFee;
        status = GameStatus.AwaitPlayers;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Set the game instance.
    function setGameInstance(address _gameInstance) external onlyAdmin {
        game = _gameInstance;
    }

    /// @dev Reset the game instance.
    function resetGame(
        bytes memory _params,
        uint256 _numPlayers,
        uint256 _tableFee
    ) external gameFinish onlyAdmin {
        status = GameStatus.AwaitPlayers;
        tableFee = _tableFee;
        button = 0;
        player2Act = address(0);
        deadline = 0;
        pot = 0;
        winner = address(0);
        whoRaised = address(0);
        whoShowed = address(0);
        for (uint256 i = 0; i < players.length; i++) {
            delete playerBets[players[i]];
            delete playerDone[players[i]];
        }
        players = new address[](0);
        IGameInstance(game).resetGame(_params, _numPlayers);
    }

    /// @dev A player joins the game.
    function joinGame(
        bytes memory _pubKey,
        bytes memory _memo,
        bytes memory _keyProof
    ) external payable {
        require(status == GameStatus.AwaitPlayers, "Game already started");
        require(msg.value == tableFee, "Invalid table fee");

        IGameInstance(game).joinGame(msg.sender, _pubKey, _memo, _keyProof);
        if (IGameInstance(game).isFull()) {
            nextStatus();
        }
    }

    /// @dev A player leaves the game.
    function leaveGame() external {
        require(status == GameStatus.AwaitPlayers, "Game already started");
        IGameInstance(game).leaveGame(msg.sender);
        payable(msg.sender).transfer(tableFee);
    }

    /// @dev Pick a random player to be the button.
    /// @param _randFeed could be generated by an oracle.
    function pickButton(uint256 _randFeed) external {
        require(status == GameStatus.PickButton, "Game not in PickButton status");
        players = IGameInstance(game).players();
        button = _randFeed % players.length;
        player2Act = players[button];

        nextStatus();
        nextPlayer();
        emit ButtonPicked(players[button]);
    }

    /// @dev Every player must shuffle the deck.
    function shuffleDeck(bytes[] memory _shuffledDeck, bytes memory _shuffleProof) external {
        require(status == GameStatus.ShuffleDeck, "Game not in ShuffleDeck status");
        require(msg.sender == player2Act, "Not your turn");
        IGameInstance(game).shuffleDeck(msg.sender, _shuffledDeck, _shuffleProof);

        // Once all players have shuffled
        if (msg.sender == players[button]) {
            nextStatus();
        }
        nextPlayer();
    }

    /// @dev 1st player bets the small blind.
    function smallBlindBet() external payable {
        require(status == GameStatus.SmallBlindBet, "Game not in SmallBlindBet status");
        require(msg.sender == player2Act, "Not your turn");
        require(msg.value == SMALL_BLIND, "Invalid small blind bet");

        pot += msg.value;
        playerBets[msg.sender] += msg.value;
        whoRaised = msg.sender;

        nextStatus();
        nextPlayer();
        emit BetSmallBlind(msg.sender, SMALL_BLIND);
    }

    /// @dev 2nd player bets the big blind.
    function bigBlindBet() external payable {
        require(status == GameStatus.BigBlindBet, "Game not in BigBlindBet status");
        require(msg.sender == player2Act, "Not your turn");
        require(msg.value == BIG_BLIND, "Invalid big blind bet");

        pot += msg.value;
        playerBets[msg.sender] += msg.value;
        whoRaised = msg.sender;

        nextStatus();
        nextPlayer();
        emit BetBigBlind(msg.sender, BIG_BLIND);
    }

    /// @dev Players take turns to draw cards.
    function drawCards(bytes[] memory _revealTokens, bytes[] memory _revealProofs) external {
        require(status == GameStatus.DrawCards, "Game not in DrawCards status");
        require(msg.sender == player2Act, "Not your turn");

        uint256[] memory mine = myCards(msg.sender);
        uint256[] memory others = othersCards(msg.sender);
        IOneTimeDraw(game).drawCardsNSubmitRevealTokens(
            msg.sender,
            mine,
            others,
            _revealTokens,
            _revealProofs
        );
        IGameInstance(game).setUsed(mine);

        // Once all players have drawn cards
        if (msg.sender == players[button]) {
            nextStatus();
        }
        nextPlayer();
    }

    /// @dev Call
    function calls() external payable whenBet {
        require(msg.sender == player2Act, "Not your turn");
        playerBets[msg.sender] += msg.value;
        require(playerBets[msg.sender] == playerBets[whoRaised], "Invalid call");

        // Once all players have equal bet
        nextPlayer();
        if (player2Act == whoRaised) {
            player2Act = players[button];
            nextStatus();
            nextPlayer();
            whoRaised = player2Act; // reset whoRaised
        }
        emit PlayerCalled(msg.sender, playerBets[msg.sender]);
    }

    /// @dev Raise
    function raise() external payable whenBet {
        require(msg.sender == player2Act, "Not your turn");
        playerBets[msg.sender] += msg.value;
        require(playerBets[msg.sender] >= playerBets[whoRaised] * MIN_RAISE, "Invalid raise");
        whoRaised = msg.sender;

        nextPlayer();
        emit PlayerRaised(msg.sender, playerBets[msg.sender]);
    }

    /// @dev Check
    function check() external whenBet {
        require(msg.sender == player2Act, "Not your turn");
        require(playerBets[msg.sender] == playerBets[whoRaised], "Invalid check");

        // Once all players have equal bet
        nextPlayer();
        if (player2Act == whoRaised) {
            player2Act = players[button];
            nextStatus();
            nextPlayer();
            whoRaised = player2Act; // reset whoRaised
        }
        emit PlayerChecked(msg.sender, playerBets[msg.sender]);
    }

    /// @dev Fold
    function fold(bytes[] memory _revealTokens, bytes[] memory _revealProofs) external whenBet {
        require(msg.sender == player2Act, "Not your turn");

        uint256[] memory unflipped = unflippedCards();
        IOneTimeDraw(game).foldCards(msg.sender, unflipped, _revealTokens, _revealProofs);
        playerDone[msg.sender] = true;

        emit PlayerFolded(msg.sender);

        if (!tryEndGame()) {
            // Once all players have equal bet
            nextPlayer();
            if (player2Act == whoRaised) {
                player2Act = players[button];
                nextStatus();
                nextPlayer();
                whoRaised = player2Act; // reset whoRaised
            }
        }
    }

    /// @dev Each player flip the Flop, Turn or River.
    function flipCards(
        bytes[] memory _revealTokens,
        bytes[] memory _revealProofs
    ) external whenFlip {
        require(msg.sender == player2Act, "Not your turn");
        uint256[] memory flipIndexes = cardsToFlip();
        IGameInstance(game).addRevealTokens(
            msg.sender,
            false,
            flipIndexes,
            _revealTokens,
            _revealProofs
        );

        nextPlayer();
        if (IGameInstance(game).readyToReveal(flipIndexes)) {
            IGameInstance(game).setUsed(flipIndexes);
            player2Act = players[button];
            nextStatus();
            nextPlayer();
        }
    }

    /// @dev Each player show their cards.
    function showdown(bytes[] memory _revealTokens, bytes[] memory _revealProofs) external {
        require(status == GameStatus.Showdown, "Game not in Showdown status");
        require(msg.sender == player2Act, "Not your turn");

        uint256[] memory mine = myCards(msg.sender);
        IGameInstance(game).addRevealTokens(msg.sender, true, mine, _revealTokens, _revealProofs);
        if (whoShowed == address(0)) {
            whoShowed = msg.sender;
        }

        nextPlayer();
        if (player2Act == whoShowed) {
            decideWinner();
        }
    }

    /// @dev Any player (still on table) can purge other player who has not taken action in time.
    /// @dev Failure to take action in time will result in confiscation (on purge) of the player's bet.
    function purgePlayer(address _other) external gameInProgress inGame whenTimeout(_other) {
        require(msg.sender != _other, "Cannot purge yourself");
        playerDone[_other] = true;
        if (!tryEndGame()) {
            timeoutGame(_other);
        }
    }

    /// @dev Switch to the next game status.
    function nextStatus() private {
        if (status == GameStatus.AwaitPlayers) {
            status = GameStatus.PickButton;
        } else if (status == GameStatus.PickButton) {
            status = GameStatus.ShuffleDeck;
        } else if (status == GameStatus.ShuffleDeck) {
            status = GameStatus.SmallBlindBet;
        } else if (status == GameStatus.SmallBlindBet) {
            status = GameStatus.BigBlindBet;
        } else if (status == GameStatus.BigBlindBet) {
            status = GameStatus.DrawCards;
        } else if (status == GameStatus.DrawCards) {
            status = GameStatus.PreFlopBet;
        } else if (status == GameStatus.PreFlopBet) {
            status = GameStatus.Flop;
        } else if (status == GameStatus.Flop) {
            status = GameStatus.FlopBet;
        } else if (status == GameStatus.FlopBet) {
            status = GameStatus.Turn;
        } else if (status == GameStatus.Turn) {
            status = GameStatus.TurnBet;
        } else if (status == GameStatus.TurnBet) {
            status = GameStatus.River;
        } else if (status == GameStatus.River) {
            status = GameStatus.RiverBet;
        } else if (status == GameStatus.RiverBet) {
            status = GameStatus.Showdown;
        }
    }

    /// @dev Switch to the next player.
    function nextPlayer() private {
        uint256 curPos = 0;
        while (players[curPos] != player2Act) {
            curPos++;
        }

        uint256 next = (curPos + 1) % players.length;
        while (playerDone[players[next]]) {
            next = (next + 1) % players.length;
        }
        player2Act = players[next];
        deadline = block.timestamp + TIMEOUT_ACT; // reset timer
    }

    /// @dev Try to end the game if only one player is left.
    function tryEndGame() private returns (bool success) {
        address lastPlayer;
        uint256 numRemain = 0;
        for (uint256 i = 0; i < players.length; i++) {
            if (!playerDone[players[i]]) {
                numRemain++;
                lastPlayer = players[i];
            }
        }
        if (numRemain == 1) {
            endGame(lastPlayer);
            success = true;
        }
    }

    /// @dev Decide the winner.
    function decideWinner() private {
        winner = address(0);
        // TODO: rules engine comes here to compare hands
        endGame(winner);
    }

    /// @dev End the game.
    function endGame(address _winner) private {
        winner = _winner;
        status = GameStatus.End;

        // Return table fee and distribute pot
        for (uint256 i = 0; i < players.length; i++) {
            payable(players[i]).transfer(tableFee);
        }
        uint256 amtWon = (pot / COMMISSION[1]) * (COMMISSION[1] - COMMISSION[0]);
        pot -= amtWon;
        payable(winner).transfer(amtWon);

        emit GameEnded(_winner, amtWon);
    }

    /// @dev Game timed out (no action taken in time).
    function timeoutGame(address _blame) private {
        // Return table fee except for `_blame`
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] != _blame) {
                payable(players[i]).transfer(tableFee);
            }
        }
        // Return bet to players who are still in the game
        for (uint256 i = 0; i < players.length; i++) {
            if (!playerDone[players[i]]) {
                payable(players[i]).transfer(playerBets[players[i]]);
                pot -= playerBets[players[i]];
            }
        }
        status = GameStatus.Timeout;
        uint256 fine = playerBets[_blame] + tableFee;
        emit GameTimeout(_blame, fine);
    }

    /// @dev Get player relative position to the button.
    /// @dev Example: small blind gets 0, big blind gets 1, etc.
    function myPos(address _player) private view returns (uint256 index) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == _player) {
                index = ((i + players.length - button - 1) % players.length);
            }
        }
        require(false, "Player not found");
    }

    /// @dev Example: small blind gets [0, 1], big blind gets [2, 3], etc.
    function myCards(address _self) private view returns (uint256[] memory) {
        uint256 pos = myPos(_self);
        uint256[] memory myIndexes = new uint256[](2);
        myIndexes[0] = 2 * pos;
        myIndexes[1] = 2 * pos + 1;
        return myIndexes;
    }

    /// @dev Get a full list of other players' cards.
    function othersCards(address _self) private view returns (uint256[] memory) {
        uint256 pos = myPos(_self);
        uint256[] memory othersIndexes = new uint256[](2 * (players.length - 1));
        uint256 j = 0;
        for (uint256 i = 0; i < 2 * players.length; i++) {
            if (i / 2 != pos) {
                othersIndexes[j] = i;
                j++;
            }
        }
        return othersIndexes;
    }

    /// @dev Get a full list of cards to flip according to the current game status.
    function cardsToFlip() private view returns (uint256[] memory) {
        uint256 num2Flip = 0;
        if (status == GameStatus.Flop) {
            num2Flip = 3;
        } else if (status == GameStatus.Turn) {
            num2Flip = 1;
        } else if (status == GameStatus.River) {
            num2Flip = 1;
        }
        uint256[] memory flipIndexes = new uint256[](num2Flip);
        for (uint256 i = 0; i < num2Flip; i++) {
            flipIndexes[i] = IGameInstance(game).numUsed() + i;
        }
        return flipIndexes;
    }

    /// @dev Get a full list of unflipped cards when a player leaves in the middle of the game.
    function unflippedCards() private view returns (uint256[] memory) {
        uint256 numUnflipped = 0;
        if (status == GameStatus.PreFlopBet) {
            numUnflipped = 5;
        } else if (status == GameStatus.FlopBet) {
            numUnflipped = 2;
        } else if (status == GameStatus.TurnBet) {
            numUnflipped = 1;
        }
        uint256[] memory unflippedIndexes = new uint256[](numUnflipped);
        for (uint256 i = 0; i < numUnflipped; i++) {
            unflippedIndexes[i] = IGameInstance(game).numUsed() + i;
        }
        return unflippedIndexes;
    }
}
