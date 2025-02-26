// SPDX-License-Identifier: MIT

pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;
import "./Ownable.sol";
import './IERC20.sol';
import './SafeMath.sol';
import "./SafeERC20.sol";

interface IDAOMintingPool {
    function getminerVeDao(address who,address lpToken,uint256 poolTypeId) external view returns(uint256);
    function getuserTotalVeDao(address who) external view returns(uint256); //获取用户总抵押veDao
    function getcalculatestakingAmount() external view returns(uint256);
}
/*
 * 投票 合约 
*/
contract idovoteContract is  Ownable {
    using SafeERC20 for IERC20;
    using SafeMath  for uint256;

    IERC20 public DAOToken;

    IDAOMintingPool  public daoMintingPool;
    uint256    private passingRate;         //通过率，默认80/100   
    uint256    private votingRatio;         //投票率，默认50/100  

    uint256    private minVoteVeDao;

    uint256    private totalStaking;
    
    mapping(address=>address []) vote_p_list;   //用户参与投票的列表
    struct votePerson{
        address     who;
        uint256     weight;
    }
    mapping(address => votePerson) voet_p_weight;   //权重：开始1，正确1次，加0.1，错误一次减0.1  : 默认10，每次增加1，最后/10  

    //用户信息
    struct peopleInfo{
        uint256     timestamp;
        uint256     veDao;                  // veDao数量                
        bool        bVoted;                 //是否投过这个币的票
        bool        weightSettled;          //是否统计权重
        bool        bStatus;
        bool        withdrawIncome;         //是否支取过收益
    }
    mapping(address => mapping(address=> peopleInfo )) votePeople;
    //币投票信息
    struct vcoinInfo{
        uint256     timestamp;              //时间戳
        bool        bOpen;                  //是否开始
        uint256     cpassingRate;           //通过率
        uint256     cvotingRatio;           //投票率
        uint256     voteVeDao;              //总投票数
        uint256     pass;                   //通过数量
        uint256     deny;                   //拒绝数量
        bool        bEnd;                   //是否结束
        bool        bSuccessOrFail;         //通过还是失败
        uint256     daoVoteIncome;          //投票要分配的收益
    }
    mapping(address => vcoinInfo) votecoin;
    
    event SetpassingRate(address who,uint256 _passingRate);
    event SetvotingRatio(address who,uint256 _votingRatio);
    event Vote(address who, address coinAddress,bool bStatus);
    event SetVoteCoinEnd(address who,address coinAddress);
    event SetDaoVoteIncome(address who,address coinAddress,uint256 amount);
    event TokeoutVoteIncome(address who,uint256 peopleVoteIncome);



    constructor(IERC20 _DAOToken,IDAOMintingPool _IDAOMintingPool){
        initializeOwner();
        DAOToken            = _DAOToken;
        daoMintingPool = _IDAOMintingPool;
        passingRate = 80;
        votingRatio = 50;
    }
    //设定矿池合约地址
    function setdaoMintingPool(address poolAddr) public onlyOwner {
        require(poolAddr != address(0));
        daoMintingPool = IDAOMintingPool(poolAddr);
    }
    //获取矿池地址
    function getdaoMintingPool() public view returns(address){
        return address(daoMintingPool);
    }
    //设定通过率
    function setpassingRate(uint256 _passingRate) public onlyOwner returns(uint256){
        require(_passingRate>0);
        passingRate = _passingRate;
        emit SetpassingRate(msg.sender,_passingRate);
        return _passingRate;
    }
    //获取通过率
    function getpassingRate() public view returns(uint256){
        return passingRate;
    }
    //设定投票率
    function setvotingRatio(uint256 _votingRatio) public onlyOwner returns(uint256){
        require(_votingRatio>0);
        votingRatio = _votingRatio;
        emit SetvotingRatio(msg.sender,_votingRatio);
        return _votingRatio;
    }
    //获取投票率
    function getvotingRatio() public view returns(uint256){
        return votingRatio;
    }
    //获取币投票信息
    function getvotecoin(address coinAddress) public view returns(vcoinInfo memory){
        require(coinAddress != address(0));
        return votecoin[coinAddress];
    }
    //获取用户投票权重
    function getVoetPeoperWeight(address who) public view returns(uint256){
        require(who != address(0));
        return voet_p_weight[who].weight;
    }
    //投票
    function vote(address coinAddress,bool bStatus) public returns(bool) 
    {
        require(coinAddress != address(0));
        require(daoMintingPool.getuserTotalVeDao(msg.sender) > 0 );
        require(votePeople[msg.sender][coinAddress].bVoted == false); //投过后，就不允许再次投票

        
        peopleInfo memory newpeopleInfo = peopleInfo({
            timestamp:          block.timestamp,
            veDao:              daoMintingPool.getuserTotalVeDao(msg.sender),
            bVoted:             true,
            weightSettled:      false,
            bStatus:            bStatus,
            withdrawIncome:     false
        });
        //开始初始化为权重为 10
        if( voet_p_weight[msg.sender].who == address(0) ){
            voet_p_weight[msg.sender].who       = msg.sender;
            voet_p_weight[msg.sender].weight    = 10;
        }
        votePeople[msg.sender][coinAddress] =  newpeopleInfo;

        vote_p_list[msg.sender].push(coinAddress);

        for(uint256 i = 0;i< vote_p_list[msg.sender].length;i++ ){
            //已经结束的票
            if( votecoin[vote_p_list[msg.sender][i]].bEnd ){
                //如果没有统计过权重的，开始统计用户权重
                if( votePeople[msg.sender][vote_p_list[msg.sender][i]].weightSettled == false ){
                    if( votecoin[vote_p_list[msg.sender][i]].bSuccessOrFail){
                        voet_p_weight[msg.sender].weight = voet_p_weight[msg.sender].weight.add(1);
                    }
                    else{
                        voet_p_weight[msg.sender].weight = voet_p_weight[msg.sender].weight.sub(1);
                    }
                    votePeople[msg.sender][vote_p_list[msg.sender][i]].weightSettled = true;
                }
            }
        }
        //voteVeDao 投票总量
        uint256 voteVeDao = votePeople[msg.sender][coinAddress].veDao;
        voteVeDao = voteVeDao.add(votePeople[msg.sender][coinAddress].veDao.mul(voet_p_weight[msg.sender].weight).div(10));

        vcoinInfo memory newvcoinInfo = vcoinInfo({
            timestamp:          block.timestamp,
            bOpen:              true,
            cpassingRate:       votecoin[coinAddress].cpassingRate,
            cvotingRatio:       votecoin[coinAddress].cvotingRatio,
            pass:               votecoin[coinAddress].pass,
            deny:               votecoin[coinAddress].deny,
            voteVeDao:          voteVeDao,
            bEnd:               votecoin[coinAddress].bEnd,
            bSuccessOrFail:     votecoin[coinAddress].bSuccessOrFail,
            daoVoteIncome:      votecoin[coinAddress].daoVoteIncome
        });
        votecoin[coinAddress] = newvcoinInfo;

        uint256 weight = voet_p_weight[msg.sender].weight;

        if(bStatus){
            votecoin[coinAddress].pass = votecoin[coinAddress].pass.add(voteVeDao.mul(weight).div(10));
        }
        else{
            votecoin[coinAddress].deny = votecoin[coinAddress].deny.add(voteVeDao.mul(weight).div(10));
        }
        totalStaking = daoMintingPool.getcalculatestakingAmount();
        
        votecoin[coinAddress].cpassingRate = votecoin[coinAddress].pass.mul(100).div( votecoin[coinAddress].pass.add(votecoin[coinAddress].deny));
        votecoin[coinAddress].cvotingRatio = votecoin[coinAddress].voteVeDao.mul(100).div(totalStaking);


        emit Vote(msg.sender,coinAddress,bStatus);
        return true;
    }
    //管理员设定否票结束
    function setVoteCoinEnd(address coinAddress) public onlyOwner returns(bool){
        require(votecoin[coinAddress].bOpen);
        votecoin[coinAddress].bOpen = false;
        votecoin[coinAddress].bEnd = true;
        votecoin[coinAddress].timestamp = block.timestamp; 
        if(votecoin[coinAddress].cpassingRate >= passingRate &&  votecoin[coinAddress].cvotingRatio >= votingRatio ){
             votecoin[coinAddress].bSuccessOrFail = true;
        }
        else{
             votecoin[coinAddress].bSuccessOrFail = false;
        }
        emit SetVoteCoinEnd(msg.sender,coinAddress);
        return true;
    }
    // 获取投票是否结束
    function getVoteEnd(address coinAddress) public view returns(bool){
        require(coinAddress != address(0));
        return votecoin[coinAddress].bEnd;
    }
    //获取投票状态
    function getVoteStatus(address coinAddress) public view returns(bool){
        require(coinAddress != address(0));
        require(votecoin[coinAddress].bEnd);
        return votecoin[coinAddress].bSuccessOrFail;
    }
    //管理员设定投票分配收益
    function setDaoVoteIncome(address coinAddress,uint256 amount) public onlyOwner payable returns(address, uint256){
        require(coinAddress != address(0));
        require(votecoin[coinAddress].timestamp != 0);
        require(amount>0);
        votecoin[coinAddress].daoVoteIncome = amount;
        DAOToken.safeTransferFrom(msg.sender, address(this), amount);  
        emit SetDaoVoteIncome(msg.sender,coinAddress,amount);
        return (coinAddress,amount);
    }
    //查看用户投票收益，
    function viewDaoVoteIncome(address coinAddress) public view returns(uint256) {
        require(coinAddress != address(0));
        require(votecoin[coinAddress].timestamp != 0);
        require(votePeople[msg.sender][coinAddress].timestamp != 0);
        require(votecoin[coinAddress].bEnd); //该币已经投票结束
        if(votePeople[msg.sender][coinAddress].withdrawIncome){
            return 0;
        }
        uint256 weight = voet_p_weight[msg.sender].weight ;
        //预估weight
        for(uint256 i = 0;i< vote_p_list[msg.sender].length;i++ ){
            //已经结束的票
            if( votecoin[vote_p_list[msg.sender][i]].bEnd ){
                //如果没有统计过权重的，开始统计用户权重
                if( votePeople[msg.sender][vote_p_list[msg.sender][i]].weightSettled == false ){
                    if( votecoin[vote_p_list[msg.sender][i]].bSuccessOrFail){
                        weight = weight.add(1);
                    }
                    else{
                        weight = weight.sub(1);
                    }
                }
            }
        }
        //开始计算收益
        uint256 peopleVoteIncome  = votePeople[msg.sender][coinAddress].veDao.mul(weight);
        peopleVoteIncome = peopleVoteIncome.div(10);
        if( votePeople[msg.sender][coinAddress].bStatus ){
            peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].pass);
        }
        else{
            peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].deny);
        }
        return peopleVoteIncome;     
    }
    //提取用户投票收益
    function tokeoutVoteIncome(address coinAddress) public returns (uint256){
        require(coinAddress != address(0));
        require(votecoin[coinAddress].timestamp != 0);
        require(votePeople[msg.sender][coinAddress].timestamp != 0);
        require(votecoin[coinAddress].bEnd); //该币已经投票结束
        require(votePeople[msg.sender][coinAddress].withdrawIncome == false);
        //更新weight
        for(uint256 i = 0;i< vote_p_list[msg.sender].length;i++ ){
            //已经结束的票
            if( votecoin[vote_p_list[msg.sender][i]].bEnd ){
                //如果没有统计过权重的，开始统计用户权重
                if( votePeople[msg.sender][vote_p_list[msg.sender][i]].weightSettled == false ){
                    if( votecoin[vote_p_list[msg.sender][i]].bSuccessOrFail){
                        voet_p_weight[msg.sender].weight = voet_p_weight[msg.sender].weight.add(1);
                    }
                    else{
                        voet_p_weight[msg.sender].weight = voet_p_weight[msg.sender].weight.sub(1);
                    }
                    votePeople[msg.sender][vote_p_list[msg.sender][i]].weightSettled = true;
                }
            }
        }
        
        //开始计算收益
        uint256 peopleVoteIncome  = votePeople[msg.sender][coinAddress].veDao.mul(voet_p_weight[msg.sender].weight);
        peopleVoteIncome = peopleVoteIncome.div(10);
        if( votePeople[msg.sender][coinAddress].bStatus ){
            peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].pass);
        }
        else{
            peopleVoteIncome = peopleVoteIncome.div(votecoin[coinAddress].deny);
        }
        votePeople[msg.sender][coinAddress].withdrawIncome = true;
        //提取用户投票收益
        IERC20(DAOToken).safeTransfer(msg.sender,peopleVoteIncome);
        emit TokeoutVoteIncome(msg.sender,peopleVoteIncome);
        return peopleVoteIncome;
    }
}