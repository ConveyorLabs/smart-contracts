// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}
contract PythonDeployer {
    address constant HEVM_ADDRESS =address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);
    function deployScript(string memory filename, bytes calldata args)
        public
        returns (address)
        {
            string[] memory cmds = new string[](2);
            cmds[0]="python3";
            cmds[1]= string.concat("python_scripts/", filename, ".py");

            bytes memory _bytecode = cheatCodes.ffi(cmds);

            bytes memory bytecode = abi.encodePacked(_bytecode, args);
            address deployedAddress;
            assembly {
                deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
            }

            require(
                deployedAddress != address(0),
                "Could not deploy script"
            );
            return deployedAddress;
        }
}
