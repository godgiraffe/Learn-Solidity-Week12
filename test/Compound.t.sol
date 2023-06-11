// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MyErc20} from "src/MyErc20.sol";

import {Unitroller} from "lib/compound-protocol/contracts/Unitroller.sol"; // proxy
import {Comptroller} from "lib/compound-protocol/contracts/Comptroller.sol"; // implementation
import {ComptrollerInterface} from "lib/compound-protocol/contracts/ComptrollerInterface.sol";

import {SimplePriceOracle} from "lib/compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "lib/compound-protocol/contracts/CToken.sol";

import {WhitePaperInterestRateModel} from "lib/compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegator} from "lib/compound-protocol/contracts/CErc20Delegator.sol"; // proxy
import {CErc20Delegate} from "lib/compound-protocol/contracts/CErc20Delegate.sol"; // implementation

contract CompoundTest is Test {
    /**
    * 1. 撰寫一個 Foundry 的 Script，該 Script 要能夠部署一個 CErc20Delegator(CErc20Delegator.sol，以下簡稱 cERC20)
         一個 Unitroller(Unitroller.sol) 以及他們的 Implementation 合約和合約初始化時相關必要合約。請遵循以下細節：
    *    - [x] cERC20 的 decimals 皆為 18
    *    - [x] 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
    *    - [x] 使用 SimplePriceOracle 作為 Oracle
    *    - [x] 使用 WhitePaperInterestRateModel 作為利率模型，利率模型合約中的借貸利率設定為 0%
    *    - [x] 初始 exchangeRate 為 1:1
   */

    /// ===== Compound =====
    Comptroller public _comptroller;
    MyErc20 public _underlyingA;
    MyErc20 public _underlyingB;
    CErc20Delegator public _cTokenA;
    CErc20Delegator public _cTokenB;
    uint8 public _decimals;
    struct RateInfo {
        uint baseRatePerYear;
        uint multiplierPerYear;
    }
    RateInfo public _rateInfoA;
    RateInfo public _rateInfoB;
    SimplePriceOracle public _priceOracle;

    /// ===== User =====
    address public _admin;
    address public _user1;
    address public _user2;

    function setUp() public {
        _admin = makeAddr("admin");
        _user1 = makeAddr("user1");
        _user2 = makeAddr("user2");

        vm.startPrank(_admin);

        _comptroller = new Comptroller();
        _priceOracle = new SimplePriceOracle();
        _decimals = 18;
        _underlyingA = create_ERC20("LL", "LL", _decimals);
        _rateInfoA = RateInfo(0, 0);
        _cTokenA = create_cERC20(
            _comptroller,
            _underlyingA,
            _rateInfoA,
            1e18,
            _decimals,
            "0x0",
            _priceOracle
        );
        require(_comptroller._supportMarket(CToken(address(_cTokenA))) == 0, "add cTokenA to market, got error");
        // CToken[] memory tokens = new CToken[](1);
        // tokens[0] = CToken(address(_cTokenA));
        // uint[] memory borrowCaps = new uint[](1);
        // borrowCaps[0] = 0;
        // _comptroller._setMarketBorrowCaps(tokens, borrowCaps);  // 設定 TokenA 無借出上限
        vm.stopPrank();
    }

    /*
     * 2. 讓 User1 mint/redeem cERC20，請透過 Foundry test case (你可以繼承上題的 script 或是用其他方式實現部署) 實現以下場景：
     *    - [x] User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token
     *    - [x] 再用 100 cERC20 token redeem 回 100 顆 ERC20
     */

    function testMint() public {
        vm.startPrank(_user1);
        uint amount = 100 * 10 ** _decimals;
        // mint underlying token
        assertEq(_underlyingA.balanceOf(_user1), 0);
        assertEq(_cTokenA.balanceOf(_user1), 0);
        _underlyingA.mint(amount);
        assertEq(_underlyingA.balanceOf(_user1), amount);
        assertEq(_cTokenA.balanceOf(_user1), 0);

        // mint cToken
        _underlyingA.approve(address(_cTokenA), amount);
        _cTokenA.mint(amount);
        assertEq(_underlyingA.balanceOf(_user1), 0);
        assertEq(_cTokenA.balanceOf(_user1), amount);

        // redeem cToken to underlying token
        _cTokenA.approve(address(_cTokenA), amount);
        _cTokenA.redeem(amount);
        assertEq(_underlyingA.balanceOf(_user1), amount);
        assertEq(_cTokenA.balanceOf(_user1), 0);
        vm.stopPrank();
    }

    /**
     * 3. 讓 User1 borrow/repay
     *    - [x] 部署第二份 cERC20 合約，以下稱它們的 underlying tokens 為 token A 與 token B
     *    - [x] 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
     *    - [x] Token B 的 collateral factor(抵押品能借出幾成價值) 為 50%
     *    - [x] User1 使用 1 顆 token B 來 mint cToken
     *    - [x] User1 使用 token B 作為抵押品來借出 50 顆 token A
     */
    function testBorrow() public {
      borrowEnvSetUp();
    }

    function borrowEnvSetUp() public {
        uint priceTokenA = 1;
        uint priceTokenB = 100;
        uint depositTokenB_amount = 1 * 10 ** _decimals;
        uint borrowTokenA_amount = 50 * 10 ** _decimals;

        vm.startPrank(_admin);
        // - [x] 部署第二份 cERC20 合約，以下稱它們的 underlying tokens 為 token A 與 token B
        // 1. deploy tokenB & cTokenB
        _underlyingB = create_ERC20("MM", "MM", _decimals);
        _rateInfoB = RateInfo(0, 0);
        _cTokenB = create_cERC20(
            _comptroller,
            _underlyingB,
            _rateInfoB,
            1e18,
            _decimals,
            "0x0",
            _priceOracle
        );

        // 2. list cTokenB to market
        uint addMarketResponse = _comptroller._supportMarket(CToken(address(_cTokenB)));
        assertEq(addMarketResponse, 0);

        // - [x] 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
        _priceOracle.setUnderlyingPrice(CToken(address(_cTokenA)), priceTokenA);
        _priceOracle.setUnderlyingPrice(CToken(address(_cTokenB)), priceTokenB);
        assertEq(_priceOracle.getUnderlyingPrice(CToken(address(_cTokenA))), priceTokenA);
        assertEq(_priceOracle.getUnderlyingPrice(CToken(address(_cTokenB))), priceTokenB);


        // - [x] 設定 Token B 的 collateral factor(抵押品能借出幾成價值) 為 50%
        // - 聽說在 solidity 的世界裡, 有乘除一起的話，一律先乘再除，避免有除不盡的奇怪問題
        // - 別的同學有使用：5e16
        uint setCollateralFactorResponse = _comptroller._setCollateralFactor(CToken(address(_cTokenB)), 50 * 10 ** _decimals / 100);
        assertEq(setCollateralFactorResponse, 0);


        // 放一些 token A 進去，準備給 user1 借
        _underlyingA.mint(borrowTokenA_amount * 10);
        _underlyingA.approve(address(_cTokenA), borrowTokenA_amount * 10);
        _cTokenA.mint(borrowTokenA_amount * 10);
        vm.stopPrank();


        vm.startPrank(_user1);
        // - [x] User1 使用 1 顆 token B 來 mint cToken
        //  1. mint underlying token & approve for cToken
        _underlyingB.mint(depositTokenB_amount);
        _underlyingB.approve(address(_cTokenB), depositTokenB_amount);
        //  2. mint cToken
        uint user1HoldUnderlyingB_Amount = _underlyingB.balanceOf(_user1);
        _cTokenB.mint(depositTokenB_amount);
        assertEq(_underlyingB.balanceOf(_user1), user1HoldUnderlyingB_Amount - depositTokenB_amount);

        // - [x] User1 使用 token B 作為抵押品來借出 50 顆 token A
        //  1. user1 先將 token B enter market, 才算把 tokenB 當作抵押品
        uint user1HoldUnderlyingA_Amount = _underlyingA.balanceOf(_user1);
        address[] memory cTokens= new address[](1);
        cTokens[0] = address(_cTokenB);
        _comptroller.enterMarkets(cTokens);
        //  2. user1 來去借錢
        _cTokenA.borrow(borrowTokenA_amount);
        assertEq(_underlyingA.balanceOf(_user1), user1HoldUnderlyingA_Amount + borrowTokenA_amount);
        // CErc20.sol : function borrow(uint borrowAmount) external returns (uint)
        //   CToken.sol : function borrowInternal(uint borrowAmount) internal nonReentrant
        //   CToken.sol : function borrowFresh(address payable borrower, uint borrowAmount) internal
        //     Comptroller.sol : function borrowAllowed(address cToken, address borrower, uint borrowAmount) override external returns (uint)
        vm.stopPrank();
    }

    /** Comptroller.sol
        user 能做的：
        將該資產加入抵押品：function enterMarkets(address[] memory cTokens) override public returns (uint[] memory)

        admin 能做的：
        設定多少 %數能被清算：function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint)
        抵押品能借出幾成價值: function _setCollateralFactor(CToken cToken, uint newCollateralFactorMantissa) external returns (uint)
        設定清算獎勵：function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint)
        讓 cToken 上市場：function _supportMarket(CToken cToken) external returns (uint)
        設定池子能被借出的上限：function _setMarketBorrowCaps(CToken[] calldata cTokens, uint[] calldata newBorrowCaps) external
        function _setBorrowCapGuardian(address newBorrowCapGuardian) external
     */

    /**
     * 4. 清算
     *    - [ ] 延續 (3.) 的借貸場景，調整 token B 的 collateral factor，讓 User1 被 User2 清算
     */


    /**
     * 5. 清算
     *    - [ ] 延續 (3.) 的借貸場景，調整 oracle 中 token B 的價格，讓 User1 被 User2 清算
     */





    //////////////////////////////////
    // helper functions
    //////////////////////////////////

    function create_ERC20(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public returns (MyErc20) {
        MyErc20 _erc20 = new MyErc20(name, symbol, decimals);
        return _erc20;
    }

    function create_cERC20(
        Comptroller comptroller,
        MyErc20 underlyingToken,
        RateInfo memory rateInfo,
        uint initialExchangeRateMantissa,
        uint8 decimals,
        bytes memory becomeImplementationData,
        SimplePriceOracle priceOracle
    ) public returns (CErc20Delegator) {
        // depoly rate model & set rate
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(
                rateInfo.baseRatePerYear,
                rateInfo.multiplierPerYear
            );

        CErc20Delegate cERC20Delegate = new CErc20Delegate();
        CErc20Delegator cERC20 = new CErc20Delegator(
            address(underlyingToken),
            comptroller,
            interestRateModel,
            initialExchangeRateMantissa,
            string.concat("c", underlyingToken.name()),
            string.concat("c", underlyingToken.symbol()),
            decimals,
            payable(msg.sender),
            address(cERC20Delegate),
            becomeImplementationData
        );

        Unitroller unitroller = new Unitroller();
        // set unitroller's implementation to comptroller
        unitroller._setPendingImplementation(address(comptroller));
        // _become 裡面會 1. 驗證 msg.sender 是否為 admin, 2. 執行 _acceptImplementation
        // 有打算把 _become 裡的東西，拆出來這邊執行，但是失敗 XD
        // 發現是 https://github.com/foundry-rs/foundry/issues/4556 問題
        // 但先搞作業ㄅ
        comptroller._become(unitroller);

        // set price oracle to comptroller
        // 注意：function 是要對 implementation contract 執行，不是對 proxy contract 執行
        // 設定 Oracle price
        comptroller._setPriceOracle(priceOracle);

        return cERC20;
    }
}
