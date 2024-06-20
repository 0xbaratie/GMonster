// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console2} from "forge-std/console2.sol";

/*//////////////////////////////////////////////////////////////
                            STRUCTS
//////////////////////////////////////////////////////////////*/

struct Challenge {
    uint deposit;
    uint initialChallengeTime;
    uint lastChallengeTime;
    uint8 suceededChallengeCount;
    uint8 continuousSuceededCount;
}
struct Season{
    uint  seasonStartTimestamp;
    uint  seasonEndTimestamp;
    bool  isSeasonFixed;
    uint  fixedBalance;
}

/*//////////////////////////////////////////////////////////////
                            EVENTS
//////////////////////////////////////////////////////////////*/

event Deposited(
    address indexed challenger,
    uint deposit,
    uint initialChallengeTime
);
event Challenged(address indexed challenger, uint challengeTime);
event Fixed(address indexed robber, address indexed target);
event Withdrawn(address indexed challenger, uint withdrawAmount);

contract GMonster is Ownable{
    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/
    string public constant ERROR_DEPOSIT1 = "GMonster: Invalid deposit amount";
    string public constant ERROR_DEPOSIT2 = "GMonster: Already deposited";
    string public constant ERROR_DEPOSIT3 =
        "GMonster: Invalid initial challenge time";
    string public constant ERROR_DEPOSIT4 = "GMonster: Season not started";
    string public constant ERROR_CHALLENGE1 = "GMonster: Not deposited";
    string public constant ERROR_CHALLENGE2 =
        "GMonster: Challenge already finished";
    string public constant ERROR_CHALLENGE3 = "GMonster: Challenge duplicated";
    string public constant ERROR_CHALLENGE4 =
        "GMonster: Challenge already failed";
    string public constant ERROR_CHALLENGE5 = "GMonster: Out challenge span";
    string public constant ERROR_WITHDRAW1 = "GMonster: Not deposited";
    string public constant ERROR_WITHDRAW2 =
        "GMonster: Challenge count not enough";
    string public constant ERROR_WITHDRAW3 =
        "GMonster: Challenge span not finished";
    string public constant ERROR_WITHDRAW4 = "GMonster: Transfer failed";
    string public constant ERROR_WITHDRAW5 = "GMonster: Season not ended";
    string public constant ERROR_ROB1 = "GMonster: Not participated";
    string public constant ERROR_ROB2 = "GMonster: Not robable";
    string public constant ERROR_ROB3 = "GMonster: Transfer failed";

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint public constant DEPOSIT = 0.002 ether;
    uint public constant FIX_FAIL_FEE = 0.0002 ether; //10%
    uint public constant CHALLENGE_COUNT = 21;
    uint public constant LOSTABLE_CHALLENGE_COUNT = 3;
    uint public constant LOST_FEE_RATE = 20; //20%
    uint public constant CHALLENGE_TIME_SPAN = 3 hours;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    Season public season;
    mapping(address => Challenge) public challenges;
    address[] public challengerAddresses;
    uint8 public maxChallengerCount;
    uint8 public fixFailedCount;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(uint _seasonStartTimestamp) Ownable(msg.sender) {
        setSeason(_seasonStartTimestamp);
    }
    /*//////////////////////////////////////////////////////////////
                            OWNER UPDATE
    //////////////////////////////////////////////////////////////*/
    function setSeason(uint _seasonStartTimestamp) public onlyOwner{
        season.seasonStartTimestamp = _seasonStartTimestamp;
        season.seasonEndTimestamp = _seasonStartTimestamp + (CHALLENGE_COUNT * 1 days);
    }

    function fixSeason() public onlyOwner {
        require(block.timestamp > season.seasonEndTimestamp, "GMonster: Season not ended");
        require(!season.isSeasonFixed, "GMonster: Already fixed");
        season.fixedBalance = address(this).balance;
        season.isSeasonFixed = true;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL UPDATE
    //////////////////////////////////////////////////////////////*/
    function deposit(uint _initialChallengeTime) public payable {
        //Validations
        require(_initialChallengeTime >= season.seasonStartTimestamp, ERROR_DEPOSIT4);
        require(block.timestamp < season.seasonStartTimestamp, "GMonster: Season already started");
        require(msg.value == DEPOSIT, ERROR_DEPOSIT1);
        require(challenges[msg.sender].deposit == 0, ERROR_DEPOSIT2);
        require(_initialChallengeTime > block.timestamp, ERROR_DEPOSIT3);

        challenges[msg.sender] = Challenge({
            deposit: msg.value,
            initialChallengeTime: _initialChallengeTime,
            lastChallengeTime: 0,
            suceededChallengeCount: 0,
            continuousSuceededCount: 0
        });

        //Increment challengerAddresses
        challengerAddresses.push(msg.sender);
        maxChallengerCount += 1;

        emit Deposited(msg.sender, msg.value, _initialChallengeTime);
    }

    function challenge() external {
        //Validations
        require(block.timestamp >= season.seasonStartTimestamp, "GMonster: Season not started");
        require(block.timestamp <= season.seasonEndTimestamp, "GMonster: Season ended");
        Challenge memory _challenge = challenges[msg.sender];
        require(_challenge.deposit >= DEPOSIT, ERROR_CHALLENGE1);
        require(
            _challenge.suceededChallengeCount < CHALLENGE_COUNT,
            ERROR_CHALLENGE2
        );
        //Today's challenge is already done
        require(
            block.timestamp >
                _challenge.lastChallengeTime + CHALLENGE_TIME_SPAN,
            ERROR_CHALLENGE3
        );
        (
            uint _lostChallengeCount,
            bool _isChallengeSpan
        ) = _getLostCountAndIsSpan(_challenge, block.timestamp);
        require(
            _lostChallengeCount <= LOSTABLE_CHALLENGE_COUNT,
            ERROR_CHALLENGE4
        );
        require(_isChallengeSpan, ERROR_CHALLENGE5);

        //Judge continuous or not
        uint8 _continuousSuceededCount = _challenge.continuousSuceededCount;
        if (
            block.timestamp <
            _challenge.lastChallengeTime + 1 days + CHALLENGE_TIME_SPAN
        ) {
            _continuousSuceededCount += 1;
        }else{
            _continuousSuceededCount = 1;        
        }

        challenges[msg.sender] = Challenge({
            deposit: _challenge.deposit,
            initialChallengeTime: _challenge.initialChallengeTime,
            lastChallengeTime: block.timestamp,
            suceededChallengeCount: _challenge.suceededChallengeCount + 1,
            continuousSuceededCount: _continuousSuceededCount
        });
        emit Challenged(msg.sender, block.timestamp);
    }

    function withdraw() external {
        //Validations
        //Check season end
        require(block.timestamp > season.seasonEndTimestamp, ERROR_WITHDRAW5);
        Challenge memory _challenge = challenges[msg.sender];
        require(_challenge.deposit >= DEPOSIT, ERROR_WITHDRAW1);
        require(
            _challenge.suceededChallengeCount >=
                CHALLENGE_COUNT - LOSTABLE_CHALLENGE_COUNT,
            ERROR_WITHDRAW2
        );
        require(
            block.timestamp >
                _challenge.initialChallengeTime +
                    ((CHALLENGE_COUNT - 1) * 1 days),
            ERROR_WITHDRAW3
        );

        challenges[msg.sender] = Challenge({
            deposit: 0,
            initialChallengeTime: 0,
            lastChallengeTime: 0,
            suceededChallengeCount: 0,
            continuousSuceededCount: 0
        });

        uint _withdrawAmount = season.fixedBalance / (maxChallengerCount - fixFailedCount);
        (bool success, ) = msg.sender.call{value: _withdrawAmount}("");
        require(success, ERROR_WITHDRAW4);

        emit Withdrawn(msg.sender, _withdrawAmount);
    }

    function fixFail(address _target) external payable {
        require(block.timestamp >= season.seasonStartTimestamp, "GMonster: Season not started");    
        require(!season.isSeasonFixed, "GMonster: Season already fixed");        
        Challenge memory _robberChallenge = challenges[msg.sender];
        //Validations
        require(_robberChallenge.deposit >= DEPOSIT, ERROR_ROB1);

        Challenge memory _targetChallenge = challenges[_target];
        require(_judgeFailOrNot(_targetChallenge, block.timestamp), ERROR_ROB2);

        challenges[_target] = Challenge({
            deposit: 0,
            initialChallengeTime: 0,
            lastChallengeTime: 0,
            suceededChallengeCount: 0,
            continuousSuceededCount: 0
        });

        (bool success, ) = msg.sender.call{value: FIX_FAIL_FEE}("");
        require(success, ERROR_ROB3);

        fixFailedCount++;
        emit Fixed(msg.sender, _target);
    }

    /*//////////////////////////////////////////////////////////////
                             EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    function judgeFailOrNot(address _challenger) external view returns (bool) {
        Challenge memory _challenge = challenges[_challenger];
        return _judgeFailOrNot(_challenge, block.timestamp);
    }

    function getLostCount(address _challenger) external view returns (uint) {
        Challenge memory _challenge = challenges[_challenger];
        (uint _lostChallengeCount, ) = _getLostCountAndIsSpan(
            _challenge,
            block.timestamp
        );
        return _lostChallengeCount;
    }

    function isChallengeSpan(address _challenger) external view returns (bool) {
        Challenge memory _challenge = challenges[_challenger];
        (, bool _isChallengeSpan) = _getLostCountAndIsSpan(
            _challenge,
            block.timestamp
        );
        return _isChallengeSpan;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL UPDATE
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                             INTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    function _getLostCountAndIsSpan(
        Challenge memory _challenge,
        uint _timestamp
    )
        internal
        view
        virtual
        returns (uint8 lostChallengeCount_, bool isChallengeSpan_)
    {
        uint8 _counter;
        for (uint8 i = _challenge.suceededChallengeCount; i < 21; i++) {
            uint _pastDays = i * 1 days;
            if (
                _timestamp <
                _challenge.initialChallengeTime +
                    _pastDays -
                    CHALLENGE_TIME_SPAN
            ) {
                //Todays challenge is not started yet
                _counter = i;
                break;
            } else if (
                _timestamp <= _challenge.initialChallengeTime + _pastDays
            ) {
                //Challenging span
                if (
                    _timestamp <
                    _challenge.lastChallengeTime + CHALLENGE_TIME_SPAN
                ) {
                    //Already challenged
                    _counter = i + 1;
                } else {
                    isChallengeSpan_ = true;
                    _counter = i;
                }

                break;
            }
        }

        //SuceededChallengeCount is updated
        lostChallengeCount_ = _counter - (_challenge.suceededChallengeCount);
    }

    //If failed, return true
    function _judgeFailOrNot(
        Challenge memory _challenge,
        uint _timestamp
    ) internal view returns (bool) {
        if (_challenge.deposit < DEPOSIT) return false;

        (uint _lostChallengeCount, ) = _getLostCountAndIsSpan(
            _challenge,
            _timestamp
        );
        if (_lostChallengeCount > LOSTABLE_CHALLENGE_COUNT) return true;

        return false;
    }
}
