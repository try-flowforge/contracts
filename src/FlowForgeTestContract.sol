// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FlowForgeTestContract
 * @notice Target for end-to-end tests: Safe creates Safe via factory, module runs execTask to this contract.
 * @dev Spending policy is enforced at execTask(declaredUsdValue); this contract just exposes increment/getCount for assertions.
 */
contract FlowForgeTestContract {
    uint256 private _count;

    event CounterIncremented(uint256 previousValue, uint256 newValue, uint256 incrementAmount);

    // Function to increment the counter by 1
    function increment() public {
        uint256 previousValue = _count;
        _count += 1;
        emit CounterIncremented(previousValue, _count, 1);
    }

    // Function to increment the counter by a specified amount
    function incrementBy(uint256 amount) public {
        uint256 previousValue = _count;
        _count += amount;
        emit CounterIncremented(previousValue, _count, amount);
    }

    function getCount() public view returns (uint256) {
        return _count;
    }
}
