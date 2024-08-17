// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPositionManager} from "../interfaces/IPositionManager.sol";
import {IReceiver} from "../interfaces/IReceiver.sol";

contract BatchSubmitter {
    function sendData(bytes calldata datas) external {
        IPositionManager.PreProcessData[] memory preDatas = abi.decode(datas, (IPositionManager.PreProcessData[]));
        for (uint256 i; i < preDatas.length; i++) {
            IReceiver(preDatas[i].receiver).receiveData(preDatas[i].data);
        }
    }
}
