// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
import"contracts/IERC20.sol";
import "contracts/ISwapRouter.sol";
import "contracts/Price.sol";


interface Loan {
    //存款函数
    function depositMoney(uint256 _Money)external;
   //返回本金和利息收益,存款的区块高度,待领取的利息,存款利息率,邀请人的利息率,下级累计存款金额
    function calculate(address _user)external  view   returns(uint256,uint256,uint256,uint256,uint256,uint256,uint256 );
    //取出利息的外部方法
    function pickInterest()external  returns(uint256);
    //取出本金和利息
    function  withdrawMoney()external returns(bool);
    //返回当前合约地址的USDT和DK数量的外部方法
    function getDkAndUsdtQuantity()external view returns(uint256,uint256);
    //抵押DK获得usdt
    function mortgage_DK(uint256 _usdtQuantity)external returns(uint256);
    //赎回DK
    function redeem_DK()external;
    //返回借usdt数量,质押DK数量,质押的DK区块高度数量,产生的利息
    function getLoanUserInformation(address _loansuer)external view returns(uint256,uint256,uint256,uint256);
    //查看利息外部函数
    function getLoanInterest(address _user)external view returns(uint256) ;
    //获得dk价格 转化后需/ e18;
    function getPrice()external view  returns(uint256);
     //修改存款月化利息   存款利息,邀请利息,借款利息
    function setMoonInterest(uint256 ownInterest,uint256 _inviteInterest,uint256 _moonLoanInterest)external  returns(uint256,uint256,uint256);
    //绑定上级
    function  setSperiorInvitation(address  superior)external returns(bool);
    //返回上级
    function getSperior(address  own)external view  returns(address) ;
    //计算已累计返佣
    function getTotalRebateIncome(address _superior)external   view returns(uint256);
    //返回顶级邀请人下级累计存款金额,以及积累的利息奖励
    function getSuperiorInformation(address _superior)external view  returns(uint256,uint256);
    //获取月化收益,以及返佣月化以及借款利息
    function getLunarization()external view   returns(uint256,uint256,uint256);
    //顶级邀请人领取返佣收益
    function receiveTotalRebateIncome()external  returns(uint256);
    //返回目标地址 邀请的所有人员信息
    function getinviteArray(address  superior)external view  returns(address[] memory);
    //设置最低存款金额
    function setMin(uint256 min)external  ;

    
}

interface DkToken {
  //获取地址的邀请人数
  function getinviteQuantity(address to)external  view returns(uint256);
}

contract loan{

 
   uint256 moon_block=86400*10;  //测试 1200个区块 3600秒 1个小时

   uint256 week_block=28800*10;  //20分钟
 
   
   //最小存款金额100e18
   uint256 minDeposit=100e18;

   //最大存款金额 4000e18
   uint256 maxDeposit=4000e18;

   //用户最大存款 30000e18
   uint256 accumulatedHighest=30000e18;

   //最大借出数量 20000e18
   uint256 maximumLoan=20000e18;



   //存款月化收益
   uint256 private  ownMoondepositInterest=380;
   
   //邀请收益
   uint256 private invitationIncome=100;

   //利息管理地址
   address manageraddress=0x4F58820EE4dcEF313E1eBc5416acB5E9e2bcbb00;
 
   //月化贷款利息
   uint256 moonLoanInterest=380;

   
   //重置的借款区块
   uint256 public  resetBorrowBlock;
   //24小时累积借款金额
   uint256 skyAccumulationLoan;


   //天存款最大  50000e18
   uint256 skyMaxLoan=50000e18;


   
   mapping (address=>address[]) inviteArray;

  //路由地址 用于swap交易
  ISwapRouter _swapRouter = ISwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
   //
  //链上usdt=>0x55d398326f99059fF775485246999027B3197955 
  IERC20 USDT=IERC20(0x55d398326f99059fF775485246999027B3197955);
  //链上DK=>0xB5f6e4236591D1e68d93A40E24Ebfe9E7CEe7F7b
  IERC20 DK_TOKEN=IERC20(0x0372b387d8259BF160C491B0f8539fa6F12c4196);
  DkToken DK=DkToken(0x0372b387d8259BF160C491B0f8539fa6F12c4196);
  //链上=0x5AA7eCa887219424DE61C6A7fbb5ccab7742C04B
  Price  price=Price(0x9d10FeB63CA40199d80CA458051FeF9d7b18382B);
  

  //重入锁
  uint private reenter = 1;

  //防止重入攻击
  modifier withdraw() {
        require(reenter == 1,"withdraw");
        reenter = 0;
        _;
        reenter = 1;
    }
  //存钱用户信息
  struct DepositUserInfo{
      uint256 depositMoney;//存入金额
      uint256 depositBlock;//存入区块
      uint256 deposit_Interest;//存款利息
      //累积的收益
      uint256 weekBlockIncome;

      //邀请利息
      uint256 depositInvitationIncome;
      
      //下级累积的存款金额
      uint256 subordinateAccumulationDeposit;

      //最新计算返佣的区块差
      uint256 superiorCommissionBlock;
   
      //待返佣的存款
      uint256 CommissionToBeRepaid;

  }
  //事件 存入
  event  userDeposit(address indexed from,uint256 Amount);
  //用户 取出
  event  userWithdraw(address indexed from,uint256 Amount);
  //用户取利息
  event userPickInterest(address indexed from,uint256 Amount);


  //借款结构体
  struct DorrowUserInfo{
      uint256 dorrowUsdtMoney;   //借的usdt数量
      uint256 mortgageDkoney;    //低于的dk数量
      uint256 dorrowBlock;       //借钱时区块高度
      bool repeat;               //是否借过
      uint256 dorrowMoonLoanInterest; //借款利率
    
  }
  //存钱
  mapping (address=>DepositUserInfo) depositUserInfo;

  //借钱
  mapping (address=>DorrowUserInfo) dorrowUserInfo;

  //上级邀请人
  mapping (address=>address) superiorInvitation;
 
    //存款函数
   function depositMoney(uint256 _Money)external withdraw{   

     require(minDeposit<=_Money&&_Money<=maxDeposit,"Deposit amount exceeds limit");

      //上级不为0 才能存款
       require(superiorInvitation[msg.sender] != address(0), "Superior does not exist");

  
     //将钱存入当前合约池
     require(USDT.transferFrom(msg.sender, address(this), _Money),"Transfer failed");
     emit  userDeposit(msg.sender,_Money);
      //获得用户信息
     DepositUserInfo storage UserInfo=depositUserInfo[msg.sender];
       uint256 userAccumulatedHighest=UserInfo.depositMoney+_Money;
       //限制用户累积金额超过3wu
       require(userAccumulatedHighest<=accumulatedHighest,"The accumulated amount exceeds");

      //如果是首次存款
      if(UserInfo.depositMoney==0){ 
      //保存存入金额
      UserInfo.depositMoney=_Money;
      //保存用户存款利息
      UserInfo.deposit_Interest=ownMoondepositInterest;
      //首次保存用户邀请人的利息
      UserInfo.depositInvitationIncome=invitationIncome;
      
      }else {
      //非首次 先取出利息
      _pickInterest(msg.sender);
      //增加存款
       UserInfo.depositMoney=UserInfo.depositMoney+_Money;
      
      }
      //保存当前区块
      UserInfo.depositBlock=block.number;
      
      //判断是否有上级邀请人
      if(superiorInvitation[msg.sender]!=address(0)){
         //有上级邀请人 先计算一次返佣收益
         //获取上级信息
         DepositUserInfo storage SuperiorUserInfo=depositUserInfo[superiorInvitation[msg.sender]];
         //计算更新一次返佣
         SuperiorUserInfo.CommissionToBeRepaid=getTotalRebateIncome(superiorInvitation[msg.sender]);
         //更新返佣计算区块
         SuperiorUserInfo.superiorCommissionBlock=block.number;
         //累积下级的存款金额
         SuperiorUserInfo.subordinateAccumulationDeposit=SuperiorUserInfo.subordinateAccumulationDeposit+_Money;
      }
      

    } 

   //返回本金和利息收益,下级累计存款,待领取的利息,存款利息率,邀请人的利息率
   function calculate(address _user)external  view   returns(uint256,uint256,uint256,uint256,uint256,uint256,uint256 ){
        DepositUserInfo storage UserInfo=depositUserInfo[_user];
        //参数 存入金额,存款利息，上次变动区块,以及累积的利息
        return (UserInfo.depositMoney,_calculateInterest(_user,UserInfo.deposit_Interest),UserInfo.depositBlock,UserInfo.depositBlock,UserInfo.deposit_Interest,UserInfo.depositInvitationIncome,UserInfo.subordinateAccumulationDeposit);
   }
    //计算利息的内部方法
   function _calculateInterest(address _user,uint256 _depositInterest)internal view    returns(uint256){
    DepositUserInfo storage UserInfo=depositUserInfo[_user];
    //距离上次计算利息的区块差
    uint256  blockDifference=block.number-UserInfo.depositBlock;
    //获得区块差获取利息
    uint256 _interest=UserInfo.depositMoney*blockDifference*_depositInterest/moon_block/10000;
    return _interest;  
   }

   //取出利息的外部方法
   function pickInterest()external withdraw returns(uint256){
      return  _pickInterest(msg.sender);
   }
   //取出利息的内部方法
   function _pickInterest(address _user)internal  returns(uint256) {
       //1、获得用户信息
       //2、将利息转给用户
       //3、重置利息最新计算区块
      DepositUserInfo storage UserInfo=depositUserInfo[_user];
      
      //计算一遍利息
      uint256 _interest=_calculateInterest(_user,UserInfo.deposit_Interest);

      //获取待领取的利息金额
      uint256 treatWeekBlockIncome=UserInfo.weekBlockIncome;
      //获取当前合约内usdt数量
      (uint256 _usdtQuantity,)=_getDkAndUsdtQuantity();
      //当用户没有存款但是有未领取利息时,用户直接领取完利息返回
      if(_interest==0){
         //当用户有未领取的利息时
         if(UserInfo.weekBlockIncome>0){
           //获得池子USDT数量
         if(_usdtQuantity<UserInfo.weekBlockIncome){
             //卖出DK成usdt
             swapTokenForFund(buyUsdtSpendDk(UserInfo.weekBlockIncome*13/10),address(DK_TOKEN),address(USDT));
         }
          
          require(USDT.transfer(_user,UserInfo.weekBlockIncome),"Transfer failed");  
          emit userPickInterest(_user,UserInfo.weekBlockIncome);
          UserInfo.weekBlockIncome=0;
          return treatWeekBlockIncome;
         }
         return 0;
      }
   
      uint256  blockDifference=block.number-UserInfo.depositBlock;
      //低于7天直接累积的利息
      if(blockDifference<week_block){
         return _interest+UserInfo.weekBlockIncome;
      }
      
      if(_usdtQuantity<_interest+UserInfo.weekBlockIncome){
          //卖出DK成usdt
          swapTokenForFund(buyUsdtSpendDk((_interest+UserInfo.weekBlockIncome)*13/10),address(DK_TOKEN),address(USDT));
      }
      

      //取出的利息的时候
      require(USDT.transfer(msg.sender, _interest+UserInfo.weekBlockIncome),"Transfer failed"); 
      emit userPickInterest(msg.sender, _interest+UserInfo.weekBlockIncome);
      UserInfo.depositBlock=block.number;
      UserInfo.weekBlockIncome=0;
      return _interest+treatWeekBlockIncome; 
   }
   //取出本金
   function  withdrawMoney()external withdraw returns(bool) {
    //获取用户信息
    //取出利息
    //取出本金
    //再讲存款金额以及区块高度改为0
    DepositUserInfo storage UserInfo=depositUserInfo[msg.sender];
    //获取当前合约地址usdt数量
    (uint256 usdtQuantity,)=_getDkAndUsdtQuantity();
    //当usdt不够则卖出dk 
    if(usdtQuantity<UserInfo.depositMoney){
      //先计算出购买
      uint256 DkQuantity=buyUsdtSpendDk(UserInfo.depositMoney);
      swapTokenForFund(DkQuantity*13/10, address(DK_TOKEN), address(USDT));
    }
    uint256  blockDifference=block.number-UserInfo.depositBlock;
    //超过7天也不提取利息只是记录到待领取的利息内
    if(blockDifference>week_block){
      UserInfo.weekBlockIncome=UserInfo.weekBlockIncome+_calculateInterest(msg.sender,UserInfo.deposit_Interest);
    }
    
    require(USDT.transfer(msg.sender, UserInfo.depositMoney),"Transfer failed");
    //取钱事件
    emit  userWithdraw(msg.sender, UserInfo.depositMoney);
    UserInfo.depositBlock=0;
    //变量存储用户取出本金的数值
    uint256 _depositMoney=UserInfo.depositMoney;
    //跟新用户存款
    UserInfo.depositMoney=0;
    //取出来利率要重新为0
    UserInfo.deposit_Interest=0;

    //用户取出资产要重新计算一下邀请人返佣
    //判断是否有上级邀请人
    if(superiorInvitation[msg.sender]!=address(0)){
         //有上级邀请人 先计算一次返佣收益
         //获取上级信息
         DepositUserInfo storage SuperiorUserInfo=depositUserInfo[superiorInvitation[msg.sender]];
         //计算更新一次返佣
         SuperiorUserInfo.CommissionToBeRepaid=getTotalRebateIncome(superiorInvitation[msg.sender]);
         //更新返佣计算区块
         SuperiorUserInfo.superiorCommissionBlock=block.number;
         SuperiorUserInfo.subordinateAccumulationDeposit=SuperiorUserInfo.subordinateAccumulationDeposit-_depositMoney;
         
      }

    return true;
    
   }
   //返回当前合约地址的USDT和DK数量的外部方法
   function getDkAndUsdtQuantity()external view returns(uint256,uint256){
     return _getDkAndUsdtQuantity();
   }

   //返回当前合约地址中USDT和DK数量的内部方法
   function _getDkAndUsdtQuantity()internal  view returns(uint256,uint256){
      uint256 USDT_Quantity=USDT.balanceOf(address(this));
      uint256 DK_Quantity=DK_TOKEN.balanceOf(address(this));
      return (USDT_Quantity,DK_Quantity);
   }  

   //抵押DK获得usdt
   function mortgage_DK(uint256 _usdtQuantity)external withdraw returns(uint256){
       //限制最大借款金额
       require(_usdtQuantity<=maximumLoan,"Exceeded lending limit");

       DorrowUserInfo storage UserInfo=dorrowUserInfo[msg.sender];
       //重复借出
       require(UserInfo.repeat==false, "Repeat borrowing");
       //短时间内借出金额超出5wu
       require(limitBorrowing(_usdtQuantity),"In a short period of time, the loan amount exceeds");
        
       //计算购买指定数量usdt所需的DK数量 ,
       uint256  spendDkQuantity=buyUsdtSpendDk(_usdtQuantity);
       //从用户身上转DK到合约地址
       require(DK_TOKEN.transferFrom(msg.sender, address(this), spendDkQuantity*10/4),"Transfer failed");
       //获取当前合约usdt数量,判断是否足够给用户借贷，如果不够卖出kd给用户借钱
       (uint256  thisUsdtQuantity,)=_getDkAndUsdtQuantity();
       if (thisUsdtQuantity<_usdtQuantity){
        //
        swapTokenForFund(spendDkQuantity*13/10,address(DK_TOKEN),address(USDT));
       }
       //将借的USDT转给用户
       require(USDT.transfer(msg.sender, _usdtQuantity),"Transfer failed");
      
       //记录用户借款金额，质押金额，借款区块,借款利息,以及更新借款状态
       UserInfo.dorrowUsdtMoney=_usdtQuantity;
       UserInfo.mortgageDkoney=spendDkQuantity*10/4;
       UserInfo.dorrowBlock=block.number;
       UserInfo.dorrowMoonLoanInterest=moonLoanInterest;
       UserInfo.repeat=true;
       return UserInfo.mortgageDkoney;
   }

   //赎回DK
   function redeem_DK()external withdraw{
      DorrowUserInfo storage UserInfo=dorrowUserInfo[msg.sender];
      //没有借钱
      require(UserInfo.repeat,"Didn't borrow money");
      //获取区块差
      uint256 blockDifference=block.number-UserInfo.dorrowBlock;
      //大于30天则将用户抵押的DK卖出成U存到池子里
      if(blockDifference>moon_block){
        swapTokenForFund(UserInfo.mortgageDkoney,address(DK_TOKEN),address(USDT));
      }else {
      //没有超过30天 减去利息返还给用户
      //计算利息,
        uint256 loanInterest=_getLoanInterest(msg.sender);
        //计算一下合约DK数量是否充足
       (,uint256 thisDkQuantity)=_getDkAndUsdtQuantity();
          if(thisDkQuantity<UserInfo.mortgageDkoney){
            //不够也卖出一部分usdt数量
            swapTokenForFund(UserInfo.dorrowUsdtMoney*3,address(USDT),address(DK_TOKEN));
          }
        //用户将USDT转回来
        require( USDT.transferFrom(msg.sender, address(this), UserInfo.dorrowUsdtMoney+loanInterest),"Transfer failed");
       
        //将抵押的DK转回给用户
        require(DK_TOKEN.transfer(msg.sender, UserInfo.mortgageDkoney),"Transfer failed");
        
      }
      //更新用户状态
       UserInfo.dorrowUsdtMoney=0;
       UserInfo.mortgageDkoney=0;
       UserInfo.dorrowBlock=0;
       UserInfo.dorrowMoonLoanInterest=0;
       UserInfo.repeat=false;      
   }

   //返回借usdt数量,质押DK数量,质押的DK区块高度数量,产生的利息
   function getLoanUserInformation(address _loansuer)external view returns(uint256,uint256,uint256,uint256){
      DorrowUserInfo storage UserInfo=dorrowUserInfo[_loansuer];
      return (UserInfo.dorrowUsdtMoney,UserInfo.mortgageDkoney,UserInfo.dorrowBlock,_getLoanInterest(_loansuer));
   }


   //查看用户自己积累的利息
   function getLoanInterest(address _user)external view returns(uint256) {
    return  _getLoanInterest(_user);
   }

   //查看借款利息内部函数,
   //质押的是DK 到时候扣除对应DK即可
   function _getLoanInterest(address _user)internal view returns(uint256){
     DorrowUserInfo storage UserInfo=dorrowUserInfo[_user];
     if(UserInfo.repeat==false){
      return 0;
     }
      //获取借贷的usdt数量
     uint256 loanUsdtQuantity=UserInfo.dorrowUsdtMoney;
     //区块差
     uint256 blockDifference=block.number-UserInfo.dorrowBlock;
     //大于30天利息也空
     if(blockDifference>moon_block){
      return 0;
     }
      
     //借贷DK数量*区块差*月化利息/月化区块
     uint256 interestDkQuantity=loanUsdtQuantity*blockDifference*UserInfo.dorrowMoonLoanInterest/moon_block/10000;
     return interestDkQuantity;
   }
   //计算购买指定数量usdt所需的DK数量
   function buyUsdtSpendDk(uint256 _usdtQuantity)internal view returns(uint256){
      return _usdtQuantity*1e18/price.getPrice();
   }

   //计算购买指定数量Dk所需的usdt数量
   function buyDkSpendUsdt(uint256 _dkQuantity)internal view returns(uint256){
      return _dkQuantity*price.getPrice()/1e18;
   }

   //获取当前合约地址邀请人数的内部函数
   function _getInviterQuantity(address _user)internal view   returns(uint256)  {
       return DK.getinviteQuantity(_user);
   }

   //修改存款月化利息   存款利息,邀请利息,借款利息
   function setMoonInterest(uint256 ownInterest,uint256 _inviteInterest,uint256 _moonLoanInterest)external  returns(uint256,uint256,uint256) {

       require(msg.sender==manageraddress,"No =manageraddress");
       //下列为限制值的输入
       require(ownInterest>=0&&ownInterest<=3,"ownMoondepositInterest beyond");
       if(ownInterest==0){
         ownMoondepositInterest=0;
       }else if(ownInterest==1){
         ownMoondepositInterest=80;
       }else if(ownInterest==2){
         ownMoondepositInterest=100;
       }else if(ownInterest==3){
         ownMoondepositInterest=380;
       }

       require(_inviteInterest>=1&&_inviteInterest<=2,"invitationIncome beyond");
       if(_inviteInterest==1){
         invitationIncome=80;
       }else if(_inviteInterest==2){
         invitationIncome=100;
       }


       require(_moonLoanInterest>=1&&_moonLoanInterest<=2,"moonLoanInterest beyond");
        if(moonLoanInterest==1){
         moonLoanInterest=380;
       }else if(moonLoanInterest==2){
         moonLoanInterest=10000;
       }
       
       


       return  (ownMoondepositInterest,invitationIncome,moonLoanInterest);
   
   } 

   //返回顶级邀请人下级累计存款,和当前累计的返佣（可领取的）
   function getSuperiorInformation(address _superior)external view  returns(uint256,uint256) {
      DepositUserInfo storage superiorUserInfo=depositUserInfo[_superior];
      return (superiorUserInfo.subordinateAccumulationDeposit,getTotalRebateIncome(_superior));
   }
   

   //顶级邀请人领取返佣收益
   function receiveTotalRebateIncome()public returns(uint256) {
         require(_getInterestRate(msg.sender),"Not eligible");
         DepositUserInfo storage UserInfo=depositUserInfo[msg.sender];
         //计算总累计的返佣
         uint256  _commissionToBeRepaid=getTotalRebateIncome(msg.sender);
         //返佣为0
         if(_commissionToBeRepaid==0){
            return 0;
         }
         //获得池子USDT数量
         (uint256 usdtQuantity,)=_getDkAndUsdtQuantity();
         //当合约池的usdt不够奖励,则要卖出DK 买U
         if(usdtQuantity<_commissionToBeRepaid){
           swapTokenForFund(buyUsdtSpendDk(_commissionToBeRepaid*13/10),address(DK_TOKEN),address(USDT));
         }
         //给顶级邀请人发放奖励
         require(USDT.transfer(msg.sender, _commissionToBeRepaid),"Transfer failed");
         
         
         //更新返佣区块
         UserInfo.superiorCommissionBlock=block.number;
         
         UserInfo.CommissionToBeRepaid=0;
         return _commissionToBeRepaid;

   }
    //绑定上级
   function  setSperiorInvitation(address  superior)external returns(bool) {
      require(!isContract(superior),"superior Contract address");

      require(_getInterestRate(superior)==true,"Non-top-level inviters cannot be bound");
      //不等于自己才行
      require(superior!=msg.sender,"");
      //先判断上级为空才可以绑定
      require(superiorInvitation[msg.sender]==address(0),"Repeat superior");
      
      //绑定地址
      superiorInvitation[msg.sender]=superior;
      //给当前顶级邀请人增加下级
      inviteArray[superior].push(msg.sender);
      return true;
   }

   //返回上级
   function getSperior(address  own)external view  returns(address) {
      require(superiorInvitation[own] != address(0), "Superior does not exist");
      return  superiorInvitation[own] ;
   }
   //返回目标地址 邀请的所有人员信息
   function getinviteArray(address  superior)external view  returns(address[] memory) {
      return  inviteArray[superior];
   }


   //计算这段区块差内产生的返佣收益的内部方法
   function _getRebateIncome(address _superior)internal view  returns(uint256) {
    //获取用户信息
    DepositUserInfo storage UserInfo=depositUserInfo[_superior];
   
    //下级累积存款金额
    uint256 downMoney=UserInfo.subordinateAccumulationDeposit;
    if(downMoney==0){
      return 0;
    }
    //获取产生收益的区块差
    uint256 rebateBlock=block.number-UserInfo.superiorCommissionBlock;
    //计算返佣            存款金额*存款区块差*返佣利息
    uint256 rebateMoney=downMoney*rebateBlock*UserInfo.depositInvitationIncome/moon_block/10000;

    //返回当前产生的返佣
    return  rebateMoney;
   }



   //计算已累计返佣
   function getTotalRebateIncome(address _superior)public  view returns(uint256) {
      DepositUserInfo storage UserInfo=depositUserInfo[_superior];
      //计算返佣
      return  UserInfo.CommissionToBeRepaid+_getRebateIncome(_superior);
   } 

   //获取月化收益,以及返佣月化，借款利率
   function getLunarization()external view   returns(uint256,uint256,uint256) {
         return (ownMoondepositInterest,invitationIncome,moonLoanInterest);
   }
   
   
   //获得获得用户邀请人数是否超过5个人的内部函数
   function _getInterestRate(address _user)internal view   returns(bool) {
      uint256 inviteQuantity=_getInviterQuantity(_user);
      if(inviteQuantity>=5){
         return true;
      }else {
         return false;
      }
   }
   //获得dk价格 转化后需/ e18;
   function getPrice()external view  returns(uint256) {
     return  price.getPrice();
   }
   //usdt和dk的交易函数  token1卖出成token2 再放到合约池子中
   function swapTokenForFund(uint256 tokenAmount,address token1,address token2)internal{
     address[] memory path = new address[](2);
        path[0] =token1;
        path[1] = token2;
        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
   }
    //增加一个授权的方法
    function authorizeUsdtDK()external  {
      //先取消权限管理
      //require(msg.sender==manageraddress,"No =manageraddress");
      uint MAX = ~uint256(0);
      USDT.approve( address(_swapRouter), MAX);
      DK_TOKEN.approve(address(_swapRouter), MAX);
    }
    //验证是否是合约地址
    function isContract(address addr) internal view returns (bool) {
    uint256 size;
    assembly { size := extcodesize(addr) }
    return size > 0;
  }

  //限制24小时借款
  function limitBorrowing(uint256 amount)public  returns(bool) {
   if(resetBorrowBlock==0){
      //如果是首次借款区块就是
      resetBorrowBlock=block.number;
      //将借款金额累计一下
      skyAccumulationLoan=skyAccumulationLoan+amount;
      if(skyAccumulationLoan>skyMaxLoan){
         return false;
      }
      return true;
   }
    //如果非首次，先获得一下区块差
    uint256 accumulatedTime=block.number-resetBorrowBlock;
      //如果小于一天  一天的区块
    if(accumulatedTime<28800){
       //叠加一下借款金额 
      skyAccumulationLoan=skyAccumulationLoan+amount;
      //大于24小时最大借出则返回false
      if(skyAccumulationLoan>skyMaxLoan){
         return false;
      }
      return true;
      //如果超过24小时
    }else {
      //判断一下借出金额是否超过
      if(amount>skyMaxLoan){
        return false; 
      }
      resetBorrowBlock=block.number;
      //更新本次重新
      skyAccumulationLoan=amount;
      return true;
    }
   
  }
  function setMin(uint256 min)external  {
     require(msg.sender==0x4F58820EE4dcEF313E1eBc5416acB5E9e2bcbb00);
    minDeposit=min;
  }

/*

  //重置的借款区块
   uint256 resetBorrowBlock;
   //24小时累积借款金额
   uint256 skyAccumulationLoan;
*/





 
}
