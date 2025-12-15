// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.29;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";
import {Vm} from "forge-std/src/Vm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/external/curve/VotingEscrow.sol";
import {ERC20Mock} from "tests/mocks/ERC20Mock.sol";
import {VotingEscrowHarness} from "tests/mocks/VotingEscrowHarness.sol";

abstract contract VotingEscrowTargets is
    BaseTargetFunctions,
    Properties
{
    function _boundValue(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) (min, max) = (max, min);
        uint256 size = max - min + 1;
        return min + (x % size);
    }

    /// CUSTOM TARGET FUNCTIONS ///

    function advanceTime(uint256 seconds_) public {
        uint256 maxTime = votingEscrow.MAXTIME();
        // Allow advancing up to MAXTIME to simulate decay and expiry
        seconds_ = _boundValue(seconds_, 1, maxTime);
        vm.warp(block.timestamp + seconds_);
    }

    /// AUTO GENERATED TARGET FUNCTIONS - ADAPTED FOR FUZZING ///

    // Corresponds to testFuzz_create_lock_variousAmounts and testFuzz_create_lock_variousUnlockTimes
    function votingEscrow_create_lock(uint256 _value, uint256 _unlock_time) public {
        _value = _boundValue(_value, 1e18, 1_000_000e18);

        uint256 minTime = votingEscrow.MINTIME();
        uint256 maxTime = votingEscrow.MAXTIME();

        // Treat _unlock_time as duration to ensure valid future time
        // testFuzz_create_lock_variousUnlockTimes bounds duration to [MINTIME, MAXTIME - WEEK]
        uint256 duration = _boundValue(_unlock_time, minTime, maxTime - 1 weeks);
        // Add 1 week to ensure that after rounding down to the nearest week, it is still >= MINTIME
        uint256 unlockTime = block.timestamp + duration + 1 weeks;

        address actor = address(0x4001);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, _value);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), _value);
        try votingEscrow.create_lock(_value, unlockTime) {} catch {
            // Should not fail given our bounds checks, but safe to catch
            assert(false);
        }
        vm.stopPrank();

        (int128 lockedAmount, uint256 lockedEnd) = votingEscrow.locked(actor);
        assert(uint256(int256(lockedAmount)) == _value);

        // Verify unlock time rounding (corresponds to testFuzz_create_lock_variousUnlockTimes)
        uint256 expectedEnd = (unlockTime / 1 weeks) * 1 weeks;
        assert(lockedEnd == expectedEnd);
    }

    // Corresponds to testFuzz_increase_amount
    function votingEscrow_increase_amount(uint256 initialAmount, uint256 increaseAmount) public {
        // testFuzz_increase_amount bounds amount to [1, INITIAL_BALANCE / 2]
        initialAmount = _boundValue(initialAmount, 1, 500_000e18);
        increaseAmount = _boundValue(increaseAmount, 1, 500_000e18);

        address actor = address(0x3001);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, initialAmount + increaseAmount);

        uint256 unlockTime = block.timestamp + votingEscrow.MAXTIME();

        vm.startPrank(actor);
        token.approve(address(votingEscrow), initialAmount + increaseAmount);
        try votingEscrow.create_lock(initialAmount, unlockTime) {} catch {
            assert(false);
        }

        try votingEscrow.increase_amount(increaseAmount) {} catch {
            assert(false);
        }
        vm.stopPrank();

        (int128 lockedAmount,) = votingEscrow.locked(actor);
        assert(uint256(int256(lockedAmount)) == initialAmount + increaseAmount);
    }

    // Corresponds to testFuzz_withdraw_after_expiry
    function votingEscrow_withdraw_after_expiry(uint256 lockAmount, uint256 extraTime) public {
        lockAmount = _boundValue(lockAmount, 1e18, 1_000_000e18);
        extraTime = _boundValue(extraTime, 1, 365 days);

        uint256 unlockTime = block.timestamp + votingEscrow.MINTIME() + 1 weeks;

        // Use a fresh actor to ensure clean state
        address actor = address(0x1042);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, lockAmount);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), lockAmount);
        try votingEscrow.create_lock(lockAmount, unlockTime) {} catch {
            assert(false);
        }
        vm.stopPrank();

        uint256 balanceBefore = token.balanceOf(actor);

        // Advance time
        vm.warp(unlockTime + extraTime);

        vm.startPrank(actor);
        try votingEscrow.withdraw() {} catch {
             assert(false);
        }
        vm.stopPrank();

        assert(token.balanceOf(actor) == balanceBefore + lockAmount);
    }

    // Corresponds to testFuzz_multiple_users_total_supply
    function votingEscrow_multiple_users_total_supply(
        uint256 aliceAmount,
        uint256 bobAmount,
        uint256 charlieAmount
    ) public {
        uint256 maxAmount = uint256(1_000_000e18) / 3;
        aliceAmount = _boundValue(aliceAmount, 1e18, maxAmount);
        bobAmount = _boundValue(bobAmount, 1e18, maxAmount);
        charlieAmount = _boundValue(charlieAmount, 1e18, maxAmount);

        uint256 unlockTime = block.timestamp + votingEscrow.MAXTIME();

        // Use addresses that won't conflict with main actor
        address alice = address(0x1001);
        address bob = address(0x1002);
        address charlie = address(0x1003);

        votingEscrow.add_to_whitelist(alice);
        votingEscrow.add_to_whitelist(bob);
        votingEscrow.add_to_whitelist(charlie);

        // If they already have locks, we can't create new ones easily without withdrawing
        // Just skip if they have locks to keep it simple and stateless-like
        if (votingEscrow.balanceOf(alice) > 0) return;
        if (votingEscrow.balanceOf(bob) > 0) return;
        if (votingEscrow.balanceOf(charlie) > 0) return;

        token.mint(alice, aliceAmount);
        token.mint(bob, bobAmount);
        token.mint(charlie, charlieAmount);

        uint256 supplyBefore = votingEscrow.totalSupply();

        // Alice
        vm.startPrank(alice);
        token.approve(address(votingEscrow), aliceAmount);
        try votingEscrow.create_lock(aliceAmount, unlockTime) {} catch { vm.stopPrank(); return; }
        vm.stopPrank();

        // Bob
        vm.startPrank(bob);
        token.approve(address(votingEscrow), bobAmount);
        try votingEscrow.create_lock(bobAmount, unlockTime) {} catch { vm.stopPrank(); return; }
        vm.stopPrank();

        // Charlie
        vm.startPrank(charlie);
        token.approve(address(votingEscrow), charlieAmount);
        try votingEscrow.create_lock(charlieAmount, unlockTime) {} catch { vm.stopPrank(); return; }
        vm.stopPrank();

        uint256 supplyAfter = votingEscrow.totalSupply();
        uint256 sumOfBalances = votingEscrow.balanceOf(alice) + votingEscrow.balanceOf(bob) +
            votingEscrow.balanceOf(charlie);

        // supplyAfter should be supplyBefore + sumOfBalances
        uint256 expectedSupply = supplyBefore + sumOfBalances;

        // Check relative error <= 1%
        uint256 diff = supplyAfter > expectedSupply ? supplyAfter - expectedSupply : expectedSupply - supplyAfter;
        if (expectedSupply > 0) {
            assert((diff * 1e18) / expectedSupply <= 0.01e18);
        } else {
             assert(supplyAfter == 0);
        }
    }

    // Corresponds to testFuzz_balanceOf_decaysCorrectly
    function votingEscrow_balanceOf_decaysCorrectly(uint256 lockAmount, uint256 timePassed) public {
        lockAmount = _boundValue(lockAmount, 1e18, 1_000_000e18);
        uint256 maxTime = votingEscrow.MAXTIME();
        uint256 unlockTime = block.timestamp + maxTime;

        address actor = address(0x2001);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, lockAmount);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), lockAmount);
        try votingEscrow.create_lock(lockAmount, unlockTime) {} catch {
            assert(false);
        }
        vm.stopPrank();

        uint256 balanceBefore = votingEscrow.balanceOf(actor);

        timePassed = _boundValue(timePassed, 1, maxTime - 1);
        vm.warp(block.timestamp + timePassed);

        uint256 balanceAfter = votingEscrow.balanceOf(actor);
        assert(balanceAfter <= balanceBefore);
    }

    // Corresponds to testFuzz_totalSupply_decaysCorrectly
    function votingEscrow_totalSupply_decaysCorrectly(uint256 lockAmount, uint256 timePassed) public {
        lockAmount = _boundValue(lockAmount, 1e18, 1_000_000e18);
        uint256 maxTime = votingEscrow.MAXTIME();
        uint256 unlockTime = block.timestamp + maxTime;

        address actor = address(0x2002);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, lockAmount);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), lockAmount);
        try votingEscrow.create_lock(lockAmount, unlockTime) {} catch {
            assert(false);
        }
        vm.stopPrank();

        uint256 supplyBefore = votingEscrow.totalSupply();

        timePassed = _boundValue(timePassed, 1, maxTime - 1);
        vm.warp(block.timestamp + timePassed);

        uint256 supplyAfter = votingEscrow.totalSupply();
        assert(supplyAfter <= supplyBefore);
    }

    // Corresponds to testFuzz_balanceOfAtT_pastTime
    function votingEscrow_balanceOfAtT_pastTime(uint256 lockAmount, uint256 timeOffset) public {
        lockAmount = _boundValue(lockAmount, 1e18, 1_000_000e18);
        uint256 maxTime = votingEscrow.MAXTIME();
        uint256 unlockTime = block.timestamp + maxTime;

        address actor = address(0x2003);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, lockAmount);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), lockAmount);
        try votingEscrow.create_lock(lockAmount, unlockTime) {} catch {
            assert(false);
        }
        vm.stopPrank();

        uint256 lockTime = block.timestamp;

        timeOffset = _boundValue(timeOffset, 1, maxTime - 1);
        vm.warp(block.timestamp + timeOffset);

        uint256 pastBalance = votingEscrow.balanceOfAtT(actor, lockTime);
        uint256 currentBalance = votingEscrow.balanceOf(actor);

        assert(pastBalance >= currentBalance);
    }

    // Corresponds to testFuzz_totalSupplyAtT_pastTime
    function votingEscrow_totalSupplyAtT_pastTime(uint256 lockAmount, uint256 timeOffset) public {
        lockAmount = _boundValue(lockAmount, 1e18, 1_000_000e18);
        uint256 maxTime = votingEscrow.MAXTIME();
        uint256 unlockTime = block.timestamp + maxTime;

        address actor = address(0x2004);
        if (votingEscrow.balanceOf(actor) > 0) return;

        votingEscrow.add_to_whitelist(actor);
        token.mint(actor, lockAmount);

        vm.startPrank(actor);
        token.approve(address(votingEscrow), lockAmount);
        try votingEscrow.create_lock(lockAmount, unlockTime) {} catch {
            assert(false);
        }
        vm.stopPrank();

        uint256 lockTime = block.timestamp;

        timeOffset = _boundValue(timeOffset, 1, maxTime - 1);
        vm.warp(block.timestamp + timeOffset);

        uint256 pastSupply = votingEscrow.totalSupplyAtT(lockTime);
        uint256 currentSupply = votingEscrow.totalSupply();

        assert(pastSupply >= currentSupply);
    }

    // Corresponds to testFuzz_find_timestamp_epoch_matches_linear_scan
    function votingEscrow_find_timestamp_epoch_matches_linear_scan(uint256 tRaw) public {
        uint256 baseTs = 30_000;
        uint256 baseBlk = 2000;
        uint256 numEpochs = 6;

        for (uint256 i = 0; i < numEpochs; ++i) {
            votingEscrow.h_setPointHistory(
                i,
                int128(int256(i + 1)),
                int128(int256(0)),
                baseTs + i * 123,
                baseBlk + i * 13
            );
        }
        votingEscrow.h_setEpoch(numEpochs - 1);

        uint256 minT = baseTs - 500;
        uint256 maxT = baseTs + numEpochs * 123 + 500;
        uint256 t = _boundValue(tRaw, minT, maxT);

        uint256 expected = 0;
        for (uint256 i = 0; i < numEpochs; ++i) {
            (,, uint256 ts,) = votingEscrow.point_history(i);
            if (ts <= t) {
                expected = i;
            }
        }

        uint256 actual = votingEscrow.exposed_find_timestamp_epoch(t, numEpochs - 1);
        assert(actual == expected);
    }

    // Corresponds to testFuzz_find_user_timestamp_epoch_matches_linear_scan
    function votingEscrow_find_user_timestamp_epoch_matches_linear_scan(uint256 tRaw) public {
        address alice = address(0x9999);

        uint256 baseTs = 50_000;
        uint256 baseBlk = 4000;
        uint256 numUserEpochs = 5;

        for (uint256 i = 1; i <= numUserEpochs; ++i) {
            votingEscrow.h_setUserPoint(
                alice, i, int128(int256(i)), int128(int256(0)), baseTs + (i - 1) * 111, baseBlk + (i - 1) * 9
            );
        }
        votingEscrow.h_setUserEpoch(alice, numUserEpochs);

        uint256 minT = baseTs - 300;
        uint256 maxT = baseTs + numUserEpochs * 111 + 300;
        uint256 t = _boundValue(tRaw, minT, maxT);

        uint256 expected = 0;
        for (uint256 i = 1; i <= numUserEpochs; ++i) {
            (,, uint256 ts,) = votingEscrow.user_point_history(alice, i);
            if (ts <= t) {
                expected = i;
            }
        }

        uint256 actual = votingEscrow.exposed_find_user_timestamp_epoch(alice, t);
        assert(actual == expected);
    }
}
