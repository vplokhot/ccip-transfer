// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {BurnMintERC677Helper, IERC20} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {BurnMintTokenPool, TokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/BurnMintTokenPool.sol";

contract CCIPTransferTest is Test{

    string ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
    string AVALANCHE_FUJI_RPC_URL = vm.envString("AVALANCHE_FUJI_RPC_URL");

    address usdcTokenAddressFuji = 0x5425890298aed601595a70AB815c96711a31Bc65;
    address usdcTokenAddressSepolia = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    uint256 sourceFork;
    uint256 destinationFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    IRouterClient sourceRouter;
    uint64 destinationChainSelector;

    IERC20 sourceUSDC;
    IERC20 destinationUSDC;
    IERC20 sourceLinkToken;
    address myAddress = makeAddr('pushkin');


    function setUp() public {
        string memory DESTINATION_RPC_URL = ETHEREUM_SEPOLIA_RPC_URL;
        string memory SOURCE_RPC_URL = AVALANCHE_FUJI_RPC_URL;

        destinationFork = vm.createSelectFork(DESTINATION_RPC_URL);
        sourceFork = vm.createFork(SOURCE_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        Register.NetworkDetails
            memory destinationNetworkDetails = ccipLocalSimulatorFork
                .getNetworkDetails(block.chainid);
        destinationChainSelector = destinationNetworkDetails.chainSelector;        
        destinationUSDC = IERC20(usdcTokenAddressSepolia);

        vm.selectFork(sourceFork);
        
        Register.NetworkDetails
            memory sourceNetworkDetails = ccipLocalSimulatorFork
                .getNetworkDetails(block.chainid);
        sourceRouter = IRouterClient(sourceNetworkDetails.routerAddress);
        sourceUSDC = IERC20(usdcTokenAddressFuji);
        sourceLinkToken = IERC20(sourceNetworkDetails.linkAddress);      
    }

    function prepareScenario()
        public
        returns (
            Client.EVMTokenAmount[] memory tokensToSendDetails,
            uint256 amountToSend
        )
    {
        vm.selectFork(sourceFork);

        deal(address(sourceUSDC), myAddress, 500 ether);

        vm.startPrank(myAddress);

        amountToSend = 100;
        sourceUSDC.approve(address(sourceRouter), amountToSend);

        tokensToSendDetails = new Client.EVMTokenAmount[](1);
        tokensToSendDetails[0] = Client.EVMTokenAmount({
            token: address(sourceUSDC),
            amount: amountToSend
        });

        vm.stopPrank();
    }

    function test_ccipTransfer() external {
        (
            Client.EVMTokenAmount[] memory tokensToSendDetails,
            uint256 amountToSend
        ) = prepareScenario();

        // vm.selectFork(destinationFork);
        // uint256 initialBalanceDestination = destinationUSDC.balanceOf(myAddress);
        
        vm.selectFork(sourceFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(myAddress, 10 ether);

        vm.startPrank(myAddress);
        uint256 initialBalanceSource = sourceUSDC.balanceOf(myAddress);

        // check that there's enough funds
        assertGe(initialBalanceSource, amountToSend);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(myAddress),
            data: "",
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0})
            ),
            feeToken: address(sourceLinkToken)
        });

        uint256 fees = sourceRouter.getFee(destinationChainSelector, message);
        sourceLinkToken.approve(address(sourceRouter), fees);
        
        sourceRouter.ccipSend(destinationChainSelector, message);

        // check that funds were sent
        assertEq(sourceUSDC.balanceOf(myAddress), initialBalanceSource - amountToSend);

        vm.stopPrank();

        ccipLocalSimulatorFork.switchChainAndRouteMessage(destinationFork);

        // vm.selectFork(destinationFork);
        // assertEq(destinationUSDC.balanceOf(myAddress), initialBalanceDestination + amountToSend);

   }

}
