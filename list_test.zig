const std = @import("std");

const Allocator = std.mem.Allocator;

const list = @import("list.zig");

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
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const n0 = try Test.Node.new(&allocator, 0);
    const n1 = try Test.Node.new(&allocator, 1);

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

    const Node = list.Node(u32);

    const VNode = struct {
        next: *Test.Node,
        prev: *Test.Node,
    };

    fn initNodes(nodes: []Test.Node) void {
        for (nodes, 0..) |*node, i| {
            node.init(@intCast(i));
        }
    }

    fn checkLinks(firstNode: *Node, expectedLinks: []const VNode) void {
        var n = firstNode;
        for (expectedLinks, 0..) |v, i| {
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
