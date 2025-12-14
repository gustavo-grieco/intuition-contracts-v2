// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.29;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

abstract contract MultiVaultTargets is BaseTargetFunctions, Properties {

    function _boundMultiVault(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) (min, max) = (max, min);
        uint256 size = max - min + 1;
        return min + (x % size);
    }

    receive() external payable {}

    function multiVault_redeem_Progressive_DepositThenRedeem(uint96 amt, uint16 redeemBps) public asActor {
        vm.deal(_getActor(), 100_000 ether);

        // Create Atom
        bytes32 atomId = _createSimpleAtom("Progressive fuzz atom", 0, _getActor());

        uint256 PROGRESSIVE_CURVE_ID = 3;

        uint256 depositAmount = _boundMultiVault(uint256(amt), 10e18, 5000e18);
        uint256 bps = _boundMultiVault(uint256(redeemBps), 1, 10_000);

        vm.prank(_getActor());
        try multiVault.deposit{ value: depositAmount }(_getActor(), atomId, PROGRESSIVE_CURVE_ID, 0) {
            // Success
        } catch {
            assert(false);
        }

        uint256 userShares = multiVault.getShares(_getActor(), atomId, PROGRESSIVE_CURVE_ID);
        if (userShares <= 1) return;

        uint256 toRedeem = (userShares * bps) / 10_000;
        if (toRedeem == 0) toRedeem = 1;

        // Leave headroom
        uint256 leave = userShares / 1000; // ~0.1%
        if (leave < 2) leave = 2;
        if (toRedeem >= userShares - leave) {
            toRedeem = userShares - leave;
        }

        vm.prank(_getActor());
        uint256 received;
        try multiVault.redeem(_getActor(), atomId, PROGRESSIVE_CURVE_ID, toRedeem, 0) returns (uint256 r) {
            received = r;
        } catch {
            assert(false);
        }

        assert(received > 0);
        uint256 remaining = multiVault.getShares(_getActor(), atomId, PROGRESSIVE_CURVE_ID);

        uint256 expected = userShares - toRedeem;
        uint256 diff = remaining > expected ? remaining - expected : expected - remaining;
        // 1e16 relative error
        if (expected > 0) {
            assert((diff * 1e18) / expected <= 1e16);
        } else {
            assert(remaining == 0);
        }
    }

    function multiVault_redeem_OffsetProgressive_DepositThenRedeem(uint96 amt, uint16 redeemBps) public asActor {
         vm.deal(_getActor(), 100_000 ether);

         bytes32 atomId = _createSimpleAtom("OffsetProgressive fuzz atom", 0, _getActor());

         uint256 OFFSET_PROGRESSIVE_CURVE_ID = 2;

         uint256 depositAmount = _boundMultiVault(uint256(amt), 10e18, 5000e18);
         uint256 bps = _boundMultiVault(uint256(redeemBps), 1, 10_000);

         vm.prank(_getActor());
         try multiVault.deposit{ value: depositAmount }(_getActor(), atomId, OFFSET_PROGRESSIVE_CURVE_ID, 0) {
             // Success
         } catch {
             assert(false);
         }

         uint256 userShares = multiVault.getShares(_getActor(), atomId, OFFSET_PROGRESSIVE_CURVE_ID);
         if (userShares <= 1) return;

         uint256 toRedeem = (userShares * bps) / 10_000;

        // Leave headroom
        uint256 leave = userShares / 1000; // ~0.1%
        if (leave < 2) leave = 2;
        if (toRedeem >= userShares - leave) {
            toRedeem = userShares - leave;
        }

        if (toRedeem == 0) toRedeem = 1;
        if (toRedeem >= userShares) toRedeem = userShares - 1;

        vm.prank(_getActor());
        uint256 received;
        try multiVault.redeem(_getActor(), atomId, OFFSET_PROGRESSIVE_CURVE_ID, toRedeem, 0) returns (uint256 r) {
             received = r;
        } catch {
             assert(false);
        }

        assert(received > 0);
        uint256 remaining = multiVault.getShares(_getActor(), atomId, OFFSET_PROGRESSIVE_CURVE_ID);

        uint256 expected = userShares - toRedeem;
        uint256 diff = remaining > expected ? remaining - expected : expected - remaining;
        if (expected > 0) {
            assert((diff * 1e18) / expected <= 1e16);
        } else {
             assert(remaining == 0);
        }
    }

    // Helpers
    function _createSimpleAtom(string memory atomString, uint256 depositAmount, address creator) internal returns (bytes32) {
        bytes memory atomData = abi.encodePacked(atomString, block.timestamp, creator, msg.sig);

        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = atomData;
        uint256 cost = multiVault.getAtomCost();
        uint256 totalAmount = depositAmount + cost;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = totalAmount;

        vm.prank(creator);

        try multiVault.createAtoms{ value: totalAmount }(dataArray, amounts) returns (bytes32[] memory atomIds) {
            return atomIds[0];
        } catch {
            assert(false);
            return bytes32(0);
        }
    }
}
