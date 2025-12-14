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
    function votingEscrow_create_lock(uint256 _value, uint256 _unlock_time) public asActor {
        _value = _boundValue(_value, 1e18, 1_000_000e18);

        uint256 minTime = votingEscrow.MINTIME();
        uint256 maxTime = votingEscrow.MAXTIME();

        // Treat _unlock_time as duration to ensure valid future time
        // testFuzz_create_lock_variousUnlockTimes bounds duration to [MINTIME, MAXTIME - WEEK]
        uint256 duration = _boundValue(_unlock_time, minTime, maxTime - 1 weeks);
        // Add 1 week to ensure that after rounding down to the nearest week, it is still >= MINTIME
        uint256 unlockTime = block.timestamp + duration + 1 weeks;

        // Ensure we don't have a lock (create_lock reverts if lock exists)
        (int128 lockedAmount, ) = votingEscrow.locked(_getActor());
        if (lockedAmount > 0) return;

        token.mint(_getActor(), _value);
        token.approve(address(votingEscrow), _value);
        try votingEscrow.create_lock(_value, unlockTime) {} catch {
            // Should not fail given our bounds checks, but safe to catch
            assert(false);
        }
    }

    // Corresponds to testFuzz_deposit_for_variousAmounts
    function votingEscrow_deposit_for(address _addr, uint256 _value) public asActor {
        // testFuzz_deposit_for_variousAmounts bounds amount to [1, INITIAL_BALANCE / 2]
        // INITIAL_BALANCE is 1_000_000e18, so max is 500_000e18
        _value = _boundValue(_value, 1, 500_000e18);

        // Ensure target has a lock
        (int128 lockedAmount, uint256 lockedEnd) = votingEscrow.locked(_addr);
        if (lockedAmount == 0) return;
        if (lockedEnd <= block.timestamp) return; // Expired

        token.mint(_getActor(), _value);
        token.approve(address(votingEscrow), _value);

        try votingEscrow.deposit_for(_addr, _value) {} catch {
            assert(false);
        }
    }

    // Corresponds to testFuzz_increase_amount
    function votingEscrow_increase_amount(uint256 _value) public asActor {
        // testFuzz_increase_amount bounds amount to [1, INITIAL_BALANCE / 2]
        _value = _boundValue(_value, 1, 500_000e18);

        (int128 lockedAmount, uint256 lockedEnd) = votingEscrow.locked(_getActor());
        if (lockedAmount == 0) return;
        if (lockedEnd <= block.timestamp) return; // Expired

        token.mint(_getActor(), _value);
        token.approve(address(votingEscrow), _value);

        try votingEscrow.increase_amount(_value) {} catch {
            assert(false);
        }
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
}
