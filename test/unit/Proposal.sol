// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

//solhint-disable
contract Proposal {
    function proposal() public pure returns (SubCall[] memory p, string memory description) {
        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        PART TO MODIFY                                                  
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

        description = "This is a test proposal";

        p = new SubCall[](4);
        p[0] = SubCall({ chainId: 1, target: address(0), value: 0, data: hex"1111" });
        p[1] = SubCall({ chainId: 1, target: address(0), value: 0, data: hex"2222" });
        p[2] = SubCall({ chainId: 137, target: address(0), value: 0, data: hex"3333" });
        p[3] = SubCall({ chainId: 137, target: address(0), value: 0, data: hex"4444" });

        /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                     END OF PART TO MODIFY                                              
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    }
}

struct SubCall {
    uint256 chainId;
    address target;
    uint256 value;
    bytes data;
}
