pragma solidity 0.4.24;

import './safemath.sol';
import './ownable.sol';


contract WordCupBet is Ownable {
    using SafeMath for uint256;

    enum Result {NotEnd, Draw, Home, Away}

    /* Technical variables */
    /* Fee rate of 1% */
    uint8 private constant feeRatePercent = 1;
    uint256 public totalFeeAmount = 0;
    /* Minimum amount: 0.001 ETH = 1 finney */
    uint256 minimumAmount = 1 finney;

    struct Bet {
        uint matchId;
        uint betAmount;
        uint8 betWinner;
        uint8 withdrew;
    }

    struct BetPlayerInfo {
        address betAddress;
        mapping(uint256 => Bet) bets;
    }

    mapping(address => BetPlayerInfo) public allPlayers;
    address[] public playerAddressList;

    struct MatchInfo {
        uint matchId;
        uint8 result;
        bool isOpened;
    }

    mapping(uint => MatchInfo)  public matchesInfo;
    uint[] public matchIdList;

    /* Events */
    event eventBet(address bettor, uint256 amountInWei, uint256 winner);
    event eventCollectEarnings(address bettor, uint256 amountInWei);
    event eventWinnerDefined(uint8 winner);


    /**************************************************/
    /****************** Bet Section *******************/
    /**************************************************/
    //用户下注
    function playerBet(uint256 _matchId, uint256 _winner) payable public {
        require(_winner == uint(Result.Draw) || _winner == uint(Result.Home) || _winner == uint(Result.Away));
        MatchInfo memory matchInfo = matchesInfo[_matchId];
        require(matchInfo.matchId != 0);
        require(matchInfo.isOpened == true);
        require(matchInfo.result == uint(Result.NotEnd));
        require(msg.value >= minimumAmount);

        uint256 amount = msg.value;
        uint256 feeAmount = amount.mul(feeRatePercent) / 100;
        uint betAmount = amount.sub(feeAmount);
        assert(amount == feeAmount.add(betAmount));

        BetPlayerInfo storage playerInfo = allPlayers[msg.sender];
        if (playerInfo.betAddress == 0x00) {
            playerInfo.betAddress = msg.sender;
            playerAddressList.push(playerInfo.betAddress);
        }
        Bet storage bet = playerInfo.bets[_matchId];
        bet.matchId = _matchId;
        bet.betWinner = uint8(_winner);
        bet.betAmount = bet.betAmount + betAmount;

        totalFeeAmount = totalFeeAmount.add(feeAmount);
        emit eventBet(msg.sender, msg.value, _winner);
    }

    function() public {
        require(false, "This end-point is not supported");
    }

    /* Allow user to request the payout of its earnings */
    //  结果出来后用户提现
    function collectEarnings() public {
        BetPlayerInfo storage playerInfo = allPlayers[msg.sender];
        uint256 playerEarnings = 0;
        for (uint idx = 0; idx < matchIdList.length; idx++) {
            uint256 matchId = matchIdList[idx];
            MatchInfo memory matchInfo = matchesInfo[matchId];
            Bet storage bet = playerInfo.bets[matchId];
            if (bet.matchId > 0 && bet.betWinner == matchInfo.result && bet.withdrew == 0) {
                uint256 totalBetsAmount = getTotalBets(matchId);
                uint256 winBetsAmount = getWinBets(matchId);
                assert(totalBetsAmount >= winBetsAmount);
                bet.withdrew = 1;
                playerEarnings += totalBetsAmount.mul(bet.betAmount) / winBetsAmount;
            }
        }
        require(playerEarnings > 0);
        msg.sender.transfer(playerEarnings);
        emit eventCollectEarnings(msg.sender, playerEarnings);
    }

    //获取可提现金额
    function getEarnings() public view returns (uint256) {
        BetPlayerInfo storage playerInfo = allPlayers[msg.sender];
        uint256 playerEarnings = 0;
        for (uint idx = 0; idx < matchIdList.length; idx++) {
            uint256 matchId = matchIdList[idx];
            MatchInfo memory matchInfo = matchesInfo[matchId];
            Bet memory bet = playerInfo.bets[matchId];
            if (bet.matchId > 0 && bet.betWinner == matchInfo.result && bet.withdrew == 0) {
                uint256 totalBetsAmount = getTotalBets(matchId);
                uint256 winBetsAmount = getWinBets(matchId);
                assert(totalBetsAmount >= winBetsAmount);
                playerEarnings += totalBetsAmount.mul(bet.betAmount) / winBetsAmount;
            }
        }
        return playerEarnings;
    }

    /**************************************************/
    /*************** Management Section ***************/
    /**************************************************/
    //更新比赛结果
    function updateWinner(uint256 _matchId, uint8 _winner) onlyOwner public {
        require(_winner == uint(Result.Draw) || _winner == uint(Result.Home) || _winner == uint(Result.Away));
        MatchInfo storage matchInfo = matchesInfo[_matchId];
        require(matchInfo.matchId != 0);
        matchInfo.result = _winner;
        emit eventWinnerDefined(_winner);
    }

    //open or close match,set matchId
    function opMatch(uint256 _matchId, bool op) onlyOwner public {
        MatchInfo storage matchInfo = matchesInfo[_matchId];
        require(matchInfo.isOpened != op);
        if (matchInfo.matchId == 0) {
            matchInfo.matchId = _matchId;
            matchIdList.push(_matchId);
        }
        matchInfo.isOpened = op;
    }

    /* Owner of the contract can collect the fees generated by the betPlayers */
    function collectFees() onlyOwner public {
        owner.transfer(totalFeeAmount);
        totalFeeAmount = 0;
    }

    /**************************************************/
    /***************** Helpers Section ****************/
    /**************************************************/
    //获取是否允许下注
    function getBetAllowed(uint256 _matchId) view public returns (bool) {
        MatchInfo memory matchInfo = matchesInfo[_matchId];
        if (matchInfo.matchId == 0 || matchInfo.isOpened == false || matchInfo.result != uint(Result.NotEnd)) {
            return false;
        }
        return true;
    }

    //获取总的投注额
    function getTotalBets(uint256 _matchId) view public returns (uint256) {
        uint256 totalBets = 0;
        MatchInfo memory matchInfo = matchesInfo[_matchId];
        if (matchInfo.matchId == 0) {
            return totalBets;
        }
        for (uint256 idx = 0; idx < playerAddressList.length; idx++) {
            address playerAddress = playerAddressList[idx];
            BetPlayerInfo storage playerInfo = allPlayers[playerAddress];
            Bet memory bet = playerInfo.bets[_matchId];
            totalBets += bet.betAmount;
        }
        return totalBets;
    }
    //获取单场比赛胜利的投注额
    function getWinBets(uint256 _matchId) view public returns (uint256) {
        uint256 winBets = 0;
        MatchInfo memory matchInfo = matchesInfo[_matchId];
        if (matchInfo.matchId == 0) {
            return winBets;
        }
        for (uint256 idx = 0; idx < playerAddressList.length; idx++) {
            address playerAddress = playerAddressList[idx];
            BetPlayerInfo storage playerInfo = allPlayers[playerAddress];
            Bet memory bet = playerInfo.bets[_matchId];
            if (bet.betWinner == matchInfo.result) {
                winBets += bet.betAmount;
            }
        }
        return winBets;
    }

    //test
    function test1() public {
        opMatch(1, true);
        opMatch(2, true);
    }

    function test2() public {
        opMatch(1, false);
        opMatch(2, false);
        updateWinner(1, 2);
        collectEarnings();
        collectFees();
    }

}