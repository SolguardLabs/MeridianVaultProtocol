// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library QueueLib {
    struct AddressQueue {
        address[] _items;
        mapping(address => uint256) _positionPlusOne;
    }

    error QueueZeroAddress();
    error QueueDuplicate(address item);
    error QueueItemNotFound(address item);
    error QueueIndexOutOfBounds(uint256 index, uint256 length);

    function length(AddressQueue storage self) internal view returns (uint256) {
        return self._items.length;
    }

    function isEmpty(AddressQueue storage self) internal view returns (bool) {
        return self._items.length == 0;
    }

    function contains(AddressQueue storage self, address item) internal view returns (bool) {
        return self._positionPlusOne[item] != 0;
    }

    function at(AddressQueue storage self, uint256 index) internal view returns (address) {
        uint256 queueLength = self._items.length;
        if (index >= queueLength) revert QueueIndexOutOfBounds(index, queueLength);
        return self._items[index];
    }

    function first(AddressQueue storage self) internal view returns (address) {
        return at(self, 0);
    }

    function last(AddressQueue storage self) internal view returns (address) {
        uint256 queueLength = self._items.length;
        if (queueLength == 0) revert QueueIndexOutOfBounds(0, 0);
        return self._items[queueLength - 1];
    }

    function values(AddressQueue storage self) internal view returns (address[] memory) {
        return self._items;
    }

    function enqueue(AddressQueue storage self, address item) internal {
        if (item == address(0)) revert QueueZeroAddress();
        if (contains(self, item)) revert QueueDuplicate(item);
        self._items.push(item);
        self._positionPlusOne[item] = self._items.length;
    }

    function remove(AddressQueue storage self, address item) internal {
        uint256 positionPlusOne = self._positionPlusOne[item];
        if (positionPlusOne == 0) revert QueueItemNotFound(item);
        _removeAt(self, positionPlusOne - 1);
    }

    function tryRemove(AddressQueue storage self, address item) internal returns (bool removed) {
        uint256 positionPlusOne = self._positionPlusOne[item];
        if (positionPlusOne == 0) return false;
        _removeAt(self, positionPlusOne - 1);
        return true;
    }

    function move(AddressQueue storage self, address item, uint256 newIndex) internal {
        uint256 queueLength = self._items.length;
        if (newIndex >= queueLength) revert QueueIndexOutOfBounds(newIndex, queueLength);

        uint256 positionPlusOne = self._positionPlusOne[item];
        if (positionPlusOne == 0) revert QueueItemNotFound(item);
        uint256 oldIndex = positionPlusOne - 1;
        if (oldIndex == newIndex) return;

        if (oldIndex < newIndex) {
            for (uint256 i = oldIndex; i < newIndex;) {
                address shifted = self._items[i + 1];
                self._items[i] = shifted;
                self._positionPlusOne[shifted] = i + 1;
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i = oldIndex; i > newIndex;) {
                address shifted = self._items[i - 1];
                self._items[i] = shifted;
                self._positionPlusOne[shifted] = i + 1;
                unchecked {
                    --i;
                }
            }
        }

        self._items[newIndex] = item;
        self._positionPlusOne[item] = newIndex + 1;
    }

    function replace(AddressQueue storage self, address[] memory newItems) internal {
        clear(self);
        uint256 newLength = newItems.length;
        for (uint256 i; i < newLength;) {
            enqueue(self, newItems[i]);
            unchecked {
                ++i;
            }
        }
    }

    function clear(AddressQueue storage self) internal {
        uint256 queueLength = self._items.length;
        for (uint256 i; i < queueLength;) {
            delete self._positionPlusOne[self._items[i]];
            unchecked {
                ++i;
            }
        }
        delete self._items;
    }

    function _removeAt(AddressQueue storage self, uint256 index) private {
        address removed = self._items[index];
        uint256 queueLength = self._items.length;
        for (uint256 i = index; i + 1 < queueLength;) {
            address shifted = self._items[i + 1];
            self._items[i] = shifted;
            self._positionPlusOne[shifted] = i + 1;
            unchecked {
                ++i;
            }
        }

        self._items.pop();
        delete self._positionPlusOne[removed];
    }
}
