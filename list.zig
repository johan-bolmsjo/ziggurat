const std = @import("std");

const Allocator = std.mem.Allocator;

/// A node in a circular double linked list.
//
/// The most useful property is that a node can remove itself from a list without having a referece
/// to it with O(1) time complexity. One node is selected to act as the head of the list. Iteration
/// is performed by following next or previous links from the head node until they point to the head
/// node.
///
/// Note that D can be set to void if you prefer to store nodes in another struct as opposed to
/// nodes carrying data. In that case use @fieldParentPtr to perform necessary pointer
/// manipulations.
///
pub fn NodeType(comptime D: type) type {
    return struct {
        const Self = @This();

        next_: *Self,
        prev_: *Self,
        datum:  D,

        /// Initialize node with the specified datum and next and prev links pointing to itself
        /// thereby forming a single element list.
        pub fn init(self: *Self, datum: D) void {
            self.next_ = self;
            self.prev_ = self;
            self.datum = datum;
        }

        /// Allocate node using the supplied allocator and initialize it the same way init does.
        pub fn new(allocator: *Allocator, datum: D) !*Self {
            var node = try allocator.create(Self);
            init(node, datum);
            return node;
        }

        /// Link other node next to self.
        pub fn linkNext(self: *Self, other: *Self) void {
            const tmp = other.prev_;
            self.next_.prev_ = tmp;
            tmp.next_ = self.next_;
            other.prev_ = self;
            self.next_ = other;
        }

        /// Link other node previous to self.
        pub fn linkPrev(self: *Self, other: *Self) void {
            const tmp = other.prev_;
            self.prev_.next_ = other;
            tmp.next_ = self;
            other.prev_ = self.prev_;
            self.prev_ = tmp;
        }

        /// Unlink node from any list that it's part of.
        /// This function is safe to call on linked and unlinked nodes provided that they has at one
        /// time been initialized properly.
        pub fn unlink(self: *Self) void {
            self.next_.prev_ = self.prev_;
            self.prev_.next_ = self.next_;
            self.next_ = self;
            self.prev_ = self;
        }

        /// Follow the next link of node.
        pub inline fn next(self: *Self) *Self {
            return self.next_;
        }

        /// Follow the previous link of node.
        pub inline fn prev(self: *Self) *Self {
            return self.prev_;
        }

        /// Check if node is linked to another node than itself.
        /// This can be applied to the sentinel list head node to check if the list is empty.
        pub inline fn isLinked(self: *Self) bool {
            return self.next_ != self;
        }
    };
}

test "linkNext" {
    var n: [5]Test.Node = undefined;
    Test.initNodes(n[0..]);

    // Link nodes form a list
    const h1 = &n[0];
    h1.linkNext(&n[1]);
    h1.linkNext(&n[2]);

    // Link two multi node lists together
    const h2 = &n[3];
    h2.linkNext(&n[4]);
    h1.linkNext(h2);

    // Expected node order [0, 3, 4, 2, 1]
    const expectedLinks = [_]Test.VNode{
        Test.VNode{.next = &n[3], .prev = &n[1]},
        Test.VNode{.next = &n[4], .prev = &n[0]},
        Test.VNode{.next = &n[2], .prev = &n[3]},
        Test.VNode{.next = &n[1], .prev = &n[4]},
        Test.VNode{.next = &n[0], .prev = &n[2]},
    };

    Test.checkLinks(h1, expectedLinks[0..]);
}

test "linkPrev" {
    var n: [5]Test.Node = undefined;
    Test.initNodes(n[0..]);

    // Link nodes form a list
    const h1 = &n[0];
    h1.linkPrev(&n[1]);
    h1.linkPrev(&n[2]);

    // Link two multi node lists together
    const h2 = &n[3];
    h2.linkPrev(&n[4]);
    h1.linkPrev(h2);

    // Expected node order [0, 1, 2, 3, 4]
    const expectedLinks = [_]Test.VNode{
        Test.VNode{.next = &n[1], .prev = &n[4]},
        Test.VNode{.next = &n[2], .prev = &n[0]},
        Test.VNode{.next = &n[3], .prev = &n[1]},
        Test.VNode{.next = &n[4], .prev = &n[2]},
        Test.VNode{.next = &n[0], .prev = &n[3]},
    };

    Test.checkLinks(h1, expectedLinks[0..]);
}

test "unlink" {
    var n: [3]Test.Node = undefined;
    Test.initNodes(n[0..]);

    const h1 = &n[0];

    h1.linkPrev(&n[1]);
    h1.linkPrev(&n[2]);

    // Expected node order [0, 2]
    n[1].unlink();
    const expectedLinks = [_]Test.VNode{
        Test.VNode{.next = &n[2], .prev = &n[2]},
        Test.VNode{.next = &n[0], .prev = &n[0]},
    };
    Test.checkLinks(h1, expectedLinks[0..]);

    // Test that the unlinked node point to itself
    const expectedLinks2 = [_]Test.VNode{
        Test.VNode{.next = &n[1], .prev = &n[1]},
    };
    Test.checkLinks(&n[1], expectedLinks2[0..]);

    // Remove last node
    // Expected node order [0]
    //
    // Do it twice to make sure that unlinking an unlinked node has no effect.
    const expectedLinks3 = [_]Test.VNode{
        Test.VNode{.next = &n[0], .prev = &n[0]},
    };
    var i: usize = 0;
    while (i < 2) : (i += 1) {
        n[2].unlink();
        Test.checkLinks(h1, expectedLinks3[0..]);
    }
}

test "isLinked" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    const n0 = try Test.Node.new(allocator, 0);
    const n1 = try Test.Node.new(allocator, 1);

    try Test.expectEqual(false, n0.isLinked());

    n0.linkPrev(n1);
    try Test.expectEqual(true, n0.isLinked());
    try Test.expectEqual(true, n1.isLinked());
}

test "iterate" {
    var n: [5]Test.Node = undefined;
    Test.initNodes(n[0..]);

    const h = &n[0];
    for (n[1..]) |*t| {
        h.linkPrev(t);
    }

    var sum: u32 = 0;
    var it = h.next();
    while (it != h) : (it = it.next()) {
        sum += it.datum;
    }

    try Test.expectEqual(@as(u32, 1+2+3+4), sum);
}

const Test = struct {
    const expectEqual = std.testing.expectEqual;

    const Node = NodeType(u32);

    const VNode = struct {
        next: *Test.Node,
        prev: *Test.Node,
    };

    fn initNodes(nodes: []Test.Node) void {
        for (nodes) |*node, i| {
            node.init(@intCast(u32, i));
        }
    }

    fn checkLinks(firstNode: *Node, expectedLinks: []const VNode) void {
        var n = firstNode;
        for (expectedLinks) |v, i| {
            if (n.next() != v.next) {
                std.debug.panic("expected next node of {} (index {}) to be {}; got {}",
                                .{n.datum, i, v.next.datum, n.next().datum});
            }
            if (n.prev() != v.prev) {
                std.debug.panic("expected previous node of {} (index {}) to be {}; got {}",
                                .{n.datum, i, v.prev.datum, n.prev().datum});
            }
            n = n.next();
        }
    }
};
