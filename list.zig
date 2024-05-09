const std = @import("std");

const Allocator = std.mem.Allocator;

/// A node in a circular double linked list.
//
/// The most useful property is that a node can remove itself from a list without having a reference
/// to it in O(1) time complexity. One node is selected to act as the head of the list. Iteration is
/// performed by following next or previous links from the head node until they point to the head
/// node.
///
/// Note that D can be set to void if you prefer to store nodes in another struct as opposed to
/// nodes carrying data. In that case use @fieldParentPtr to perform necessary pointer
/// manipulations.
///
pub fn Node(comptime D: type) type {
    return struct {
        const This = @This();

        next_: *This,
        prev_: *This,
        datum:  D,

        /// Initialize node with the specified datum and next and prev links pointing to itself
        /// thereby forming a single element list.
        pub fn init(node: *This, datum: D) void {
            node.next_ = node;
            node.prev_ = node;
            node.datum = datum;
        }

        /// Allocate node using the supplied allocator and initialize it the same way init does.
        pub fn new(allocator: *const Allocator, datum: D) !*This {
            const node = try allocator.create(This);
            init(node, datum);
            return node;
        }

        /// Link other node next to itself.
        pub fn linkNext(node: *This, other: *This) void {
            const tmp = other.prev_;
            node.next_.prev_ = tmp;
            tmp.next_ = node.next_;
            other.prev_ = node;
            node.next_ = other;
        }

        /// Link other node previous to itself.
        pub fn linkPrev(node: *This, other: *This) void {
            const tmp = other.prev_;
            node.prev_.next_ = other;
            tmp.next_ = node;
            other.prev_ = node.prev_;
            node.prev_ = tmp;
        }

        /// Unlink node from any list that it's part of.
        /// This function is safe to call on linked and unlinked nodes provided that they has at one
        /// time been initialized properly.
        pub fn unlink(node: *This) void {
            node.next_.prev_ = node.prev_;
            node.prev_.next_ = node.next_;
            node.next_ = node;
            node.prev_ = node;
        }

        /// Follow the next link of node.
        pub inline fn next(node: *This) *This {
            return node.next_;
        }

        /// Follow the previous link of node.
        pub inline fn prev(node: *This) *This {
            return node.prev_;
        }

        /// Check if node is linked to another node than itself.
        /// This can be applied to the sentinel list head node to check if the list is empty.
        pub inline fn isLinked(node: *This) bool {
            return node.next_ != node;
        }
    };
}
