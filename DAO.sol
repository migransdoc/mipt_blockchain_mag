// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

error DaoStudentCouncil__TimeLimit();

contract DaoStudentCouncil {
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed student,
        uint256 creationTimestamp
    );
    event ProposalStateChanged(
        uint256 indexed proposalId,
        ProposalState prev_state,
        ProposalState curr_state,
        uint256 timestamp
    );

    enum ProposalState {
        SPONSORING,
        VOTING,
        CANCEL,
        APPROVED,
        NOT_APPROVED
    }

    struct Proposal {
        uint256 proposalId;
        address student; // Кто предложил предложение
        string description; // Описание предложения
        bytes txData;
        uint256 creationTimestamp; // Таймстемп создания предложения
        ProposalState state;
        uint256 sponsorAmount; // Сумма спонсирования
        uint256 voteForAmount; // Сумма голосования за
        uint256 voteAgainstAmount; // Сумма голосования против
    }
    // Проголосовал ли студент за или против предложения и каким кол-вом токенов
    struct VoteInfo {
        bool isSupportProposal;
        uint256 amount;
    }

    address owner;
    uint256[] public s_proposalIds; // Массив идентификаторов всех предложений
    mapping(uint256 => Proposal) public s_proposals; // Маппинг со всеми предложениями
    mapping(address => mapping(uint256 => VoteInfo)) private s_studentVotes; // Маппинг студента к предложениям к кол-ву токенов
    address[] public s_students; // Заглушка в виде списка адресов студентов
    address[] public s_studentCouncilMember; // Заглушка в виде списка адресов членов студсовета
    uint256 public constant TIMELIMIT = 7 days; // Сколько времени отводится на спонсирование и голосвание
    uint256 public constant SPONSOR_AMOUNT = 1000000; // Требуемое кол-во токенов на спонсирование
    uint256 public constant VOTES_AMOUNT = 100000; // Требуемое кол-во токенов для завершения голосования по предложению

    /**
    Модификатор для некоторых функций, который позволяет использовать их только вызывающему или администрации
     */
    modifier onlyOwnerOrSelf(address student) {
        require(msg.sender == owner || msg.sender == student);
        _;
    }

    /**
    Модификатор проверки, является ли запрашиваемый адрес студентом
     */
    modifier isStudentModifier(address student) {
        require(isStudent(student), "Is not a student");
        _;
    }

    constructor() {
        owner = msg.sender;
        s_students = [
            0x5B38Da6a701c568545dCfcB03FcB875f56beddC4,
            0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,
            0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db,
            0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB,
            0x617F2E2fD72FD9D5503197092aC168c91465E7f2
        ];
        s_studentCouncilMember = [
            0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB,
            0x617F2E2fD72FD9D5503197092aC168c91465E7f2
        ];
    }

    /**
    Создание предложения
     */
    function createProposal(string calldata description, bytes calldata txData)
        public
        isStudentModifier(msg.sender)
    {
        uint256 _proposalId = s_proposalIds.length + 1;
        Proposal memory newProposal = Proposal(
            _proposalId,
            msg.sender,
            description,
            txData,
            block.timestamp,
            ProposalState.SPONSORING,
            0,
            0,
            0
        );
        s_proposals[_proposalId] = newProposal;
        s_proposalIds.push(_proposalId);
        emit ProposalCreated(_proposalId, msg.sender, block.timestamp);
    }

    /**
    Отмена предложения, если это возможно
     */
    function cancelProposal(uint256 proposalId) public {
        require(
            s_proposals[proposalId].student == msg.sender,
            "You are not allowed to cancel someone's else proposal"
        );
        require(
            s_proposals[proposalId].state == ProposalState.SPONSORING,
            "It is not allowed to cancel proposal in active or finished state"
        );
        require(
            s_proposals[proposalId].sponsorAmount == 0,
            "You are allowed to cancel proposal only if nobody has sponsored it yet"
        );
        changeProposalState(proposalId, ProposalState.CANCEL);
    }

    /**
    Спонсирование предложения
     */
    function sponsorProposal(uint256 proposalId) public payable {
        require(s_proposals[proposalId].state == ProposalState.SPONSORING);
        require(msg.value > 0);
        require(
            votable(proposalId, msg.sender),
            "You are not allowed to sponsor this proposal"
        );
        // Если лимит времени на спонсирование истек
        if (
            s_proposals[proposalId].creationTimestamp + TIMELIMIT <
            block.timestamp
        ) {
            changeProposalState(proposalId, ProposalState.CANCEL);
            revert DaoStudentCouncil__TimeLimit();
        }
        s_proposals[proposalId].sponsorAmount += msg.value;
        // Если лимит спонсирования достигнут, переводим предложение в статус голосования
        if (s_proposals[proposalId].sponsorAmount >= SPONSOR_AMOUNT) {
            changeProposalState(proposalId, ProposalState.VOTING);
        }
    }

    /**
    Внутренняя служебная функция для смены статуса предложения
    В целевой реализации будет вызываться через ChainLink Automation при истечении времени на голосование или спонсирование
     */
    function changeProposalState(uint256 proposalId, ProposalState newState)
        internal
    {
        ProposalState oldState = s_proposals[proposalId].state;
        s_proposals[proposalId].state = newState;
        emit ProposalStateChanged(
            proposalId,
            oldState,
            newState,
            block.timestamp
        );
    }

    /**
    Голосование по предложению
     */
    function vote(uint256 proposalId, bool isSupportProposal) public payable {
        require(
            votable(proposalId, msg.sender),
            "You are not allowed to vote on this proposal"
        );
        require(s_proposals[proposalId].state == ProposalState.VOTING);
        require(msg.value > 0);
        // Если лимит времени на голосование истек
        if (
            s_proposals[proposalId].creationTimestamp + TIMELIMIT <
            block.timestamp
        ) {
            changeProposalState(proposalId, ProposalState.CANCEL);
            revert DaoStudentCouncil__TimeLimit();
        }
        if (isSupportProposal) {
            s_proposals[proposalId].voteForAmount += msg.value;
        } else {
            s_proposals[proposalId].voteAgainstAmount += msg.value;
        }
        s_studentVotes[msg.sender][proposalId] = VoteInfo(
            isSupportProposal,
            msg.value
        );
        // Если лимит голосования достигнут, меняем статус у предложения
        if (
            s_proposals[proposalId].voteForAmount >= VOTES_AMOUNT ||
            s_proposals[proposalId].voteAgainstAmount >= VOTES_AMOUNT
        ) {
            s_proposals[proposalId].voteForAmount >
                s_proposals[proposalId].voteAgainstAmount
                ? changeProposalState(proposalId, ProposalState.APPROVED)
                : changeProposalState(proposalId, ProposalState.NOT_APPROVED);
        }
    }

    /**
    Имеет ли право адрес голосовать или спонсировать предложение
    Не имеет права в случае, если не является студентом или уже голосовал за предложение
     */
    function votable(uint256 proposalId, address student)
        public
        view
        returns (bool)
    {
        return (
            (isStudent(student) &&
                s_studentVotes[student][proposalId].amount == 0)
                ? true
                : false
        );
    }

    /**
    Получение статуса предложения
     */
    function getProposalState(uint256 proposalId)
        public
        view
        returns (ProposalState)
    {
        return s_proposals[proposalId].state;
    }

    /**
    Получение предложения по его идентификатору
     */
    function getProposal(uint256 proposalId)
        public
        view
        returns (Proposal memory)
    {
        return s_proposals[proposalId];
    }

    /**
    Получение списка идентификаторов всех предложений
     */
    function getProposals() public view returns (uint256[] memory) {
        return s_proposalIds;
    }

    /**
    Как проголосовал студент по конкретному предложению (за или против и кол-во токенов)
    Имеет право просматривать только владелец контракта, то есть университет, или сам студент информацию о себе
     */
    function getStudentVote(address student, uint256 proposalId)
        public
        view
        onlyOwnerOrSelf(student)
        isStudentModifier(student)
        returns (bool, uint256)
    {
        VoteInfo memory voteInfo = s_studentVotes[student][proposalId];
        return (voteInfo.isSupportProposal, voteInfo.amount);
    }

    /**
    Получение баланса студента
     */
    function getStudentBalance(address student)
        public
        view
        onlyOwnerOrSelf(student)
        isStudentModifier(student)
        returns (uint256)
    {
        return student.balance;
    }

    /**
    Является ли адрес студентом
    В целевой реализации эта функция должна обращаться к оракулу в виде БД университета
    На текущий момент функция всегда выводит True
     */
    function isStudent(address student) public view returns (bool) {
        for (uint256 i = 0; i < s_students.length; i++) {
            if (s_students[i] == student) {
                return true;
            }
        }
        return false;
    }

    /**
    Является ли адрес членом студсовета
     */
    function isStudentCouncilMember(address student)
        public
        view
        returns (bool)
    {
        for (uint256 i = 0; i < s_studentCouncilMember.length; i++) {
            if (s_studentCouncilMember[i] == student) {
                return true;
            }
        }
        return false;
    }
}
