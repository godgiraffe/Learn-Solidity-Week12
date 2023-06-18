// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {CErc20} from "lib/compound-protocol/contracts/CErc20.sol";

import {Unitroller} from "lib/compound-protocol/contracts/Unitroller.sol"; // proxy
import {Comptroller} from "lib/compound-protocol/contracts/Comptroller.sol"; // implementation

import {SimplePriceOracle} from "lib/compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "lib/compound-protocol/contracts/CToken.sol";
import {CTokenInterface} from "lib/compound-protocol/contracts/CTokenInterfaces.sol";

import {WhitePaperInterestRateModel} from "lib/compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegator} from "lib/compound-protocol/contracts/CErc20Delegator.sol"; // proxy
import {CErc20Delegate} from "lib/compound-protocol/contracts/CErc20Delegate.sol"; // implementation

contract ForkCompoundTest is Test {
    /**
      請使用 Foundry 的 fork testing 模式撰寫測試，並使用 AAVE v3 的 Flash loan(https://docs.aave.com/developers/guides/flash-loans) 來清算 User1，請遵循以下細節：

      - [x] Fork Ethereum mainnet at block 17465000(https://book.getfoundry.sh/forge/fork-testing#examples)
      - [x] cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
      - [ ] Close factor 設定為 50%(清算時最高清算 50%)
      - [ ] Liquidation incentive 設為 8% (1.08 * 1e18)
      - [ ] 設定 UNI 的 collateral factor 為 50%(借出最高 50% 價值)
      - [ ] 使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
      - [ ] 在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $5
      - [ ] User1 使用 1000 顆 UNI 作為抵押品借出 2500 顆 USDC
      - [ ] 將 UNI 價格改為 $4 使 User1 產生 Shortfall，並讓 User2 透過 AAVE 的 Flash loan 來借錢清算 User1
      - [ ] 可以自行檢查清算 50% 後是不是大約可以賺 63 USDC
      - [ ] 在合約中如需將 UNI 換成 USDC 可以使用以下程式碼片段：
            ```
            // https://docs.uniswap.org/protocol/guides/swaps/single-swaps

            ISwapRouter.ExactInputSingleParams memory swapParams =
              ISwapRouter.ExactInputSingleParams({
                tokenIn: UNI_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: uniAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
              });

            // The call to `exactInputSingle` executes the swap.
            // swap Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564
            uint256 amountOut = swapRouter.exactInputSingle(swapParams);
            ```
    */

    uint public mainnetFork;
    string public MAINNET_RPC_URL;
    /// Token Contract Address
    address public UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    CErc20Delegator public cUNI;
    CErc20Delegator public cUSDC;

    /// [這個用不到] compound 的相關地址：https://etherscan.io/accounts/label/compound

    /// User Address
    address public _admin = makeAddr("admin");
    address public _user1 = makeAddr("user1");
    address public _user2 = makeAddr("user2");

    /// Contract Address
    Unitroller public unitroller;
    Comptroller public comptroller;
    SimplePriceOracle public priceOracle;

    struct CErc20Config {
        address underlying;
        uint baseRatePerYear;
        uint multiplierPerYear;
        uint initialExchangeRateMantissa;
        string name;
        string symbol;
        uint8 decimals;
    }

    CErc20Config public cUSDConfig;
    CErc20Config public cUNIConfig;

    function setUp() public {
        uint forkBlockNumber = 17_465_000;
        forkToMainnet(forkBlockNumber);
        assertEq(vm.activeFork(), mainnetFork);
        assertEq(block.number, forkBlockNumber);

        vm.startPrank(_admin);
        unitroller = new Unitroller();        // admin = msg.sender
        comptroller = new Comptroller();      // admin = msg.sender
        priceOracle = new SimplePriceOracle();
        require(unitroller._setPendingImplementation(address(comptroller)) == 0, "Unitroller setPendingImplementation failed");
        // 要執行 become, 才能在 depoly cErc20 時, 將 unitroller 設為參數, 不然型態會不過的樣子, 中間就過不了了
        comptroller._become(unitroller);
        comptroller._setPriceOracle(priceOracle);

        // - [x] cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
        cUSDConfig = CErc20Config({
            underlying: USDC,
            baseRatePerYear: 0,
            multiplierPerYear: 0,
            initialExchangeRateMantissa: 1e18,
            name: "Compound USD Coin",
            symbol: "cUSDC",
            decimals: 18
        });
        cUSDC = deploycErc20(cUSDConfig);
        require(comptroller._supportMarket(CToken(address(cUSDC))) == 0, "cUSDC supportMarket failed");

        cUNIConfig = CErc20Config({
            underlying: UNI,
            baseRatePerYear: 0,
            multiplierPerYear: 0,
            initialExchangeRateMantissa: 1e18,
            name: "Compound UNI",
            symbol: "cUNI",
            decimals: 18
        });
        cUNI = deploycErc20(cUNIConfig);
        require(comptroller._supportMarket(CToken(address(cUNI))) == 0, "cUNI supportMarket failed");

        // - [ ] Close factor 設定為 50%(清算時最高清算 50%)
        // - [ ] Liquidation incentive 設為 8% (1.08 * 1e18)
        // - [ ] 設定 UNI 的 collateral factor 為 50%(借出最高 50% 價值)

        vm.stopPrank();
    }

    function testQ1() public {}

    /**
        進階題:
        - [ ] 使用一套治理框架（例如 Governor Bravo 加上 Timelock）完成 Comptroller 中的設置
        - [ ] 賞析 UniswapAnchoredView(https://etherscan.io/address/0x50ce56A3239671Ab62f185704Caedf626352741e#code) 合約並使用其作為 Comptroller 中設置的 oracle 來實現清算
        - [ ] 設計一個能透過 Flash loan 清算多種代幣類型的智能合約
        - [ ] 研究 Aave(https://aave.com/) 協議，比較這些借貸協議在功能上與合約開發上的差異
     */

    //////////////////////////////////
    // helper functions
    //////////////////////////////////
    function forkToMainnet(uint forkBlockNumber) public {
        MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(forkBlockNumber); // fork 是為了 uniswap / usdc / uni, compound 還是用自己佈的
    }

    function deploycErc20(
        CErc20Config memory cErc20Config
    ) public returns (CErc20Delegator) {
        (
            address underlying,
            uint baseRatePerYear,
            uint multiplierPerYear,
            uint initialExchangeRateMantissa,
            string memory name,
            string memory symbol,
            uint8 decimals
        ) = (
                cErc20Config.underlying,
                cErc20Config.baseRatePerYear,
                cErc20Config.multiplierPerYear,
                cErc20Config.initialExchangeRateMantissa,
                cErc20Config.name,
                cErc20Config.symbol,
                cErc20Config.decimals
            );

        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(
                baseRatePerYear,
                multiplierPerYear
            );
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        CErc20Delegator cErc20 = new CErc20Delegator(
            underlying,
            Comptroller(address(unitroller)),
            interestRateModel,
            initialExchangeRateMantissa,
            name,
            symbol,
            decimals,
            payable(msg.sender),
            address(cErc20Delegate),
            new bytes(0)
        );

        return cErc20;
    }
}