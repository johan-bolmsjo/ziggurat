const std = @import("std");

const avl = @import("avl.zig");

const runCpuIntensiveTests = true;

test "invariants: permute add" {
    if (!runCpuIntensiveTests) return;

    const N = 10;

    var tree = Test.Tree{};
    const src = Test.valuesInSequence(N);
    var dst: [N]Test.Value = undefined;
    var nodes: [N]Test.Node = undefined;

    var seq: u32 = 0;
    while (Test.permuteValues(&dst, &src, seq)) {
        Test.initNodes(&nodes, &dst);

        for (&nodes, 0..) |*node, i| {
            const rnode = tree.add(node);
            if (rnode != node) {
                std.debug.panic("Failed to add datum={}, index={}, sequence={}, returnedDatum={}",
                                .{node.datum, i, seq, rnode.datum});
            }

            const validation = tree.validate();
            if (!validation.balanced or !validation.sorted) {
                std.debug.panic("Invalid tree invariant: balanced={}, sorted={}, sequence={}",
                                .{validation.balanced, validation.sorted, seq});
            }
        }

        tree.clear({}, null);
        seq += 1;
    }
}

test "invariants: permute remove" {
    if (!runCpuIntensiveTests) return;

    const N = 10;

    var tree = Test.Tree{};
    const src = Test.valuesInSequence(N);
    var dst: [N]Test.Value = undefined;
    var nodes: [N]Test.Node = undefined;

    var seq: u32 = 0;
    while (Test.permuteValues(&dst, &src, seq)) {
        Test.initNodes(&nodes, &dst);

        for (&nodes, 0..) |*node, i| {
            const rnode = tree.add(node);
            if (rnode != node) {
                std.debug.panic("Failed to add datum={}, index={}, sequence={}, returnedDatum={}",
                                .{node.datum, i, seq, rnode.datum});
            }
        }

        for (dst, 0..) |value, i| {
            const rnode = tree.remove(value);
            if (rnode) |node| {
                if (node.datum != value) {
                    std.debug.panic("Failed to remove datum={}, index={}, sequence={}, returnedDatum={}",
                                    .{value, i, seq, node.datum});
                }
            } else {
                std.debug.panic("Failed to remove datum={}, index={}, sequence={}, returnedNode={?}",
                                .{value, i, seq, rnode});
            }

            const validation = tree.validate();
            if (!validation.balanced or !validation.sorted) {
                std.debug.panic("Invalid tree invariant: balanced={}, sorted={}, sequence={}",
                                .{validation.balanced, validation.sorted, seq});
            }
        }

        tree.clear({}, null);
        seq += 1;
    }
}

test "add existing" {
    var tree = Test.Tree{};

    var a = Test.Tree.Node{.datum = 1};
    var b = Test.Tree.Node{.datum = 1};

    try Test.expectEqual(&a, tree.add(&a));
    try Test.expectEqual(&a, tree.add(&b));
}

test "remove from empty tree" {
    var tree = Test.Tree{};
    const node = tree.remove(1);
    try Test.expectEqual(@as(?*Test.Tree.Node, null), node);
}

test "remove non existing" {
    const testValues = [_]Test.Value{1, 2, 3, 5};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    Test.populateTree(&tree, &nodes);

    const node = tree.remove(4);
    try Test.expectEqual(@as(?*Test.Tree.Node, null), node);
}

test "clear" {
    const testValues = [_]Test.Value{1, 2, 3, 4, 5, 6, 7, 8, 9};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    Test.populateTree(&tree, &nodes);

    // TODO: test iterator invalidation (if iterators are added).

    const ReleaseContext = struct {
        testValues: []const Test.Value,
        index: usize = 0,

        fn f(self: *@This(), node: *Test.Tree.Node) void {
            if (node.datum != self.testValues[self.index]) {
                std.debug.panic("Unexpected tree sequence! got node {}; want {}",
                                .{node.datum, self.testValues[self.index]});
            }
            self.index += 1;
        }
    };

    var ctx = ReleaseContext{.testValues = &testValues};
    tree.clear(&ctx, ReleaseContext.f);

    try Test.expectEqual(@as(?*Test.Tree.Node, null), tree.root);
    try Test.expectEqual(@as(usize, 0), tree.len);

    // TODO: test iterator invalidation (if iterators are added).
}

test "clearEmpty" {
    var tree = Test.Tree{};
    const ReleaseContext = struct {
        fn f(_: void, _: *Test.Tree.Node) void {
            std.debug.panic("Unexpected callback!", .{});
        }
    };
    tree.clear({}, ReleaseContext.f);
}

test "apply" {
    const testValues = [_]Test.Value{1, 2, 3, 4, 5, 6, 7, 8, 9};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    Test.populateTree(&tree, &nodes);

    const ApplyContext = struct {
        testValues: []const Test.Value,
        index: usize = 0,

        fn f(self: *@This(), node: *Test.Tree.Node) void {
            if (node.datum != self.testValues[self.index]) {
                std.debug.panic("Unexpected tree sequence! got node {}; want {}",
                                .{node.datum, self.testValues[self.index]});
            }
            self.index += 1;
        }
    };

    var ctx = ApplyContext{.testValues = &testValues};
    tree.apply(&ctx, ApplyContext.f);
}

test "applyEmpty" {
    var tree = Test.Tree{};
    const ApplyContext = struct {
        fn f(_: void, _: *Test.Tree.Node) void {
            std.debug.panic("Unexpected callback!", .{});
        }
    };
    tree.apply({}, ApplyContext.f);
}

test "len" {
    const testValues = [_]Test.Value{1, 2, 3};
    const nonExistingValue: Test.Value = 4;

    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    try Test.expectEqual(@as(usize, 0), tree.len);

    var addCount: usize = 0;
    for (&nodes) |*node| {
        const rnode = tree.add(node);
        if (rnode != node) {
            std.debug.panic("Failed to populate tree with datum {}, found existing datum {}",
                            .{node.datum, rnode.datum});
        }
        addCount += 1;
        try Test.expectEqual(addCount, tree.len);
    }

    // Removing non existing value should not modify tree count.
    _ = tree.remove(nonExistingValue);
    try Test.expectEqual(addCount, tree.len);

    var removeCount: usize = 0;
    for (testValues) |v| {
        _ = tree.remove(v);
        removeCount += 1;
        try Test.expectEqual(addCount - removeCount, tree.len);
    }
}

test "find" {
    const testValues = [_]Test.Value{2, 5, 6, 7, 10};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    Test.populateTree(&tree, &nodes);

    const T = struct {
        name:     []const u8,
        lookupFn: *const fn(*Test.Tree, u32) ?u32,
        input:    u32,
        output:   ?u32,
    };

    const F = struct {
        fn find(xtree: *Test.Tree, xvalue: u32) ?u32 {
            if (xtree.find(xvalue)) |node| { return node.datum; } else { return null; }
        }
        fn findLe(xtree: *Test.Tree, xvalue: u32) ?u32 {
            if (xtree.findEqualOrLesser(xvalue)) |node| { return node.datum; } else { return null; }
        }
        fn findGe(xtree: *Test.Tree, xvalue: u32) ?u32 {
            if (xtree.findEqualOrGreater(xvalue)) |node| { return node.datum; } else { return null; }
        }
    };

    const testData = [_]T{
        T{.name = "Find(NonExisting)",   .lookupFn = F.find,   .input =  1, .output = null},
        T{.name = "Find(NonExisting)",   .lookupFn = F.find,   .input =  4, .output = null},
        T{.name = "Find(NonExisting)",   .lookupFn = F.find,   .input =  8, .output = null},
        T{.name = "Find(NonExisting)",   .lookupFn = F.find,   .input = 11, .output = null},
        T{.name = "Find(Existing)",      .lookupFn = F.find,   .input =  2, .output =  2},
        T{.name = "Find(Existing)",      .lookupFn = F.find,   .input =  6, .output =  6},
        T{.name = "Find(Existing)",      .lookupFn = F.find,   .input = 10, .output = 10},
        T{.name = "FindLe(NonExisting)", .lookupFn = F.findLe, .input = 11, .output = 10},
        T{.name = "FindLe(NonExisting)", .lookupFn = F.findLe, .input =  9, .output =  7},
        T{.name = "FindLe(NonExisting)", .lookupFn = F.findLe, .input =  4, .output =  2},
        T{.name = "FindLe(NonExisting)", .lookupFn = F.findLe, .input =  1, .output = null},
        T{.name = "FindLe(Existing)",    .lookupFn = F.findLe, .input =  2, .output =  2},
        T{.name = "FindLe(Existing)",    .lookupFn = F.findLe, .input =  6, .output =  6},
        T{.name = "FindLe(Existing)",    .lookupFn = F.findLe, .input = 10, .output = 10},
        T{.name = "FindGe(NonExisting)", .lookupFn = F.findGe, .input = 11, .output = null},
        T{.name = "FindGe(NonExisting)", .lookupFn = F.findGe, .input =  8, .output = 10},
        T{.name = "FindGe(NonExisting)", .lookupFn = F.findGe, .input =  3, .output =  5},
        T{.name = "FindGe(NonExisting)", .lookupFn = F.findGe, .input =  1, .output =  2},
        T{.name = "FindGe(Existing)",    .lookupFn = F.findGe, .input =  2, .output =  2},
        T{.name = "FindGe(Existing)",    .lookupFn = F.findGe, .input =  6, .output =  6},
        T{.name = "FindGe(Existing)",    .lookupFn = F.findGe, .input = 10, .output = 10},
    };

    for (&testData) |*t| {
        const output = t.lookupFn(&tree, t.input);
        const noneMarker = 99;
        if ((output orelse noneMarker) != (t.output orelse noneMarker)) {
            std.debug.panic("{s}: input={}, output={?}; expect={?}", .{t.name, t.input, output, t.output});
        }
    }
}

test "findLowest" {
    var tree = Test.Tree{};
    const expected: ?*Test.Tree.Node = null;
    try Test.expectEqual(expected, tree.findLowest());

    const testValues = [_]Test.Value{42, 3, 99, 76};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);
    Test.populateTree(&tree, &nodes);

    try Test.expectEqual(@as(Test.Value, 3), tree.findLowest().?.datum);
}

test "findHighest" {
    var tree = Test.Tree{};
    const expected: ?*Test.Tree.Node = null;
    try Test.expectEqual(expected, tree.findHighest());

    const testValues = [_]Test.Value{42, 3, 99, 76};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);
    Test.populateTree(&tree, &nodes);

    try Test.expectEqual(@as(Test.Value, 99), tree.findHighest().?.datum);
}

const Test = struct {
    const assert = std.debug.assert;
    const expectEqual = std.testing.expectEqual;

    const Tree = avl.Tree(u32, u32, getKey, cmpKey);

    fn getKey(node: *avl.Node(u32)) u32 {
        return node.datum;
    }

    fn cmpKey(lhs: u32, rhs: u32) std.math.Order {
        if (lhs < rhs) {
            return .lt;
        } else if (lhs > rhs) {
            return .gt;
        }
        return .eq;
    }

    const Value = u32;
    const Node  = Tree.Node;

    fn valuesInSequence(comptime n: usize) [n]Value {
        var t: [n]Value = undefined;
        for (t, 0..) |_, i| {
            t[i] = @intCast(i);
        }
        return t;
    }

    fn initNodes(nodes: []Node, values: []const Value) void {
        for (values, 0..) |value, i| {
            nodes[i] = Tree.Node{.datum = value};
        }
    }

    fn populateTree(tree: *Tree, nodes: []Node) void {
        for (nodes) |*node| {
            const rnode = tree.add(node);
            if (rnode != node) {
                std.debug.panic("Failed to populate tree with datum {}, found existing datum {}",
                                .{node.datum, rnode.datum});
            }
        }
    }

    fn factorial(n: u32) u32 {
        var r: u32 = 1;
        var i: u32 = 2;
        while (i < n) : (i += 1) {
            r *= i;
        }
        return r;
    }

    fn permuteValues(dst: []Value, src: []const Value, seq: u32) bool {
        assert(src.len == dst.len);
        const alen: u32 = @intCast(src.len);

        var fact = factorial(alen);

        // Out of range?
        if ((seq / alen) >= fact) {
            return false;
        }

        std.mem.copyForwards(u32, dst[0..], src[0..]);

        var i: u32 = 0;
        while (i < (alen - 1)) : (i += 1) {
            const tmpi = (seq / fact) % (alen - i);
            const tmp = dst[i+tmpi];

            var j: u32 = i + tmpi;
            while (j > i) : (j -= 1) {
                dst[j] = dst[j-1];
            }

            dst[i] = tmp;
            fact /= (alen - (i + 1));
        }

        return true;
    }
};
