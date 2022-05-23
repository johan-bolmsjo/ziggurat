// Based on code originally written by Julienne Walker in the public domain,
// https://web.archive.org/web/20070212102708/http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_avl.aspx

const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const maxTreeHeight = 36;

// TODO:
//
// I would like some things optional at comptime that has storage or compute
// implications. For example by passing a struct like this to TreeType to enable
// certain features.
//
// const TreeOptions = struct {
//    withLen: bool = false,
//    withIter: bool = false,
// };
//
// At the moment I think Zig lacks the support to implement this fully.

// TODO: Iterator support
//
// This is a port of a Go implementation which in turn is a port of a C
// implementation. The original implementations has iterator support but I have
// not got around to implement it for this version yet. Unfortunately iterators
// requires carrying some state as this AVL tree does not record parent pointers
// in the nodes to save space.
//

/// AVL tree holding nodes.
///
/// This is a low level API where the user is responsible for node resource management. Keys are part
/// of the single data type stored into the tree to reduce memory management. A key must never be
/// mutated as long as the node containing it is stored in the tree.
///
/// Note that D can be set to void if you prefer to store nodes in another struct as opposed to
/// nodes carrying data. In that case use @fieldParentPtr to perform necessary pointer
/// manipulations.
///
/// D:      Type of datum carried by nodes.
/// K:      Type of key in datum.
/// getKey: Obtain key from datum.
/// cmpKey: Compare keys for ordering.
///
pub fn TreeType(comptime D: type, comptime K: type, getKey: fn(*NodeType(D)) K, cmpKey: fn(lhs: K, rhs: K) math.Order) type {
    return struct {
        const Self = @This();
        const Node = NodeType(D);

        root: ?*Node = null,
        len: usize = 0,

        /// Add node into tree. Returns the added node or one already in the tree with an identical
        /// key. The caller must check the return value to determine if the node was added or a
        /// duplicate was found.
        pub fn add(self: *Self, node: *Node) *Node {
            // Empty tree case.
            if (self.root == null) {
                self.root = node;
                self.len += 1;
                return node;
            }

            const key = getKey(node);

            // Set up false tree root to ease maintenance
            var head = Node{.datum = undefined};
            var t = &head;
            t.links[Right] = self.root;

            var dir: Direction = undefined;

            var s = t.links[Right].?; // Place to rebalance and parent
            var p = s;                // Iterator

            // Search down the tree, saving rebalance points
            while (true) {
                const order = cmpKey(getKey(p), key);
                if (order == .eq) {
                    return p;
                }

                dir = directionOfBool(order == .lt);
                if (p.links[dir]) |q| {
                    if (q.balance != 0) {
                        t = p;
                        s = q;
                    }
                    p = q;
                } else {
                    break;
                }
            }

            p.links[dir] = node;

            // Update balance factors
            p = s;
            while (p != node) : (p = p.links[dir].?) {
                dir = directionOfBool(cmpKey(getKey(p), key) == .lt);
                p.balance += balanceOfDirection(dir);
            }

            var q = s; // Save rebalance point for parent fix

            // Rebalance if necessary
            if (abs(s.balance) > 1) {
                dir = directionOfBool(cmpKey(getKey(s), key) == .lt);
                s = s.adjustBalanceAdd(dir);
            }

            // Fix parent
            if (q == head.links[Right]) {
                self.root = s;
            } else {
                t.links[directionOfBool(q == t.links[Right])] = s;
            }

            self.len += 1;
            return node;
        }

        /// Remove node associated with key from tree.
        pub fn remove(self: *Self, key: K) ?*Node {
            var curr = self.root orelse return null;

            var up:  [maxTreeHeight]*Node = undefined;
            var upd: [maxTreeHeight]Direction = undefined;
            var top: usize = 0;

            // Search down tree and save path
            while (true) {
                const order = cmpKey(getKey(curr), key);
                if (order == .eq) {
                    break;
                }

                // Push direction and node onto stack
                const dir = directionOfBool(order == .lt);
                upd[top] = dir;
                up[top] = curr;
                top += 1;

                curr = curr.links[dir] orelse return null;
            }

            // Remove the node
            const leftNode  = curr.links[Left];
            const rightNode = curr.links[Right];

            if (leftNode == null or rightNode == null) {
                // Which child is non-nil?
                const dir = directionOfBool(leftNode == null);

                // Fix parent
                if (top > 0) {
                    up[top-1].links[upd[top-1]] = curr.links[dir];
                } else {
                    self.root = curr.links[dir];
                }
            } else {
                // Find the inorder successor
                var heir = rightNode.?;

                var parent: ?*Node = null;
                var parentDir = Left;

                if (top > 0) {
                    parent    = up[top-1];
                    parentDir = upd[top-1];
                }

                // Save this path too
                upd[top] = Right;
                up[top] = curr;
                const currPos = top;
                top += 1;

                while (heir.links[Left]) |heirLeftNode| {
                    upd[top] = Left;
                    up[top] = heir;
                    top += 1;
                    heir = heirLeftNode;
                }

                const dir = directionOfBool(up[top-1] == curr);
                up[top-1].links[dir] = heir.links[Right];

                if (parent) |xparent| {
                    xparent.links[parentDir] = heir;
                } else {
                    self.root = heir;
                }

                up[currPos] = heir;
                heir.copyLinksFrom(curr);
            }

            // Walk back up the search path
            var done = false;
            while (top > 0 and !done) : (top -= 1) {
                const i = top - 1;

                // Update balance factors
                up[i].balance += inverseBalanceOfDirection(upd[i]);

                // Terminate or rebalance as necessary
                const absBalance = abs(up[i].balance);
                if (absBalance == 1) {
                    break;
                } else if (absBalance > 1) {
                    up[i] = up[i].adjustBalanceRemove(upd[i], &done);

                    // Fix parent
                    if (i > 0) {
                        up[i-1].links[upd[i-1]] = up[i];
                    } else {
                        self.root = up[0];
                    }
                }
            }

            curr.deinitLinks();
            self.len -= 1;
            return curr;
        }

        /// Remove all nodes from the tree.
        /// The release function with supplied context is called on each removed node.
        /// Use {} as context if no release function is supplied.
        pub fn clear(self: *Self, context: anytype, releaseFn: ?fn(@TypeOf(context), *Node) void) void {
            var curr = self.root;

            // Destruction by rotation
            while (curr) |xcurr| {
                curr = blk: {
                    if (xcurr.links[Left]) |left| {
                        // Rotate right
                        xcurr.links[Left] = left.links[Right];
                        left.links[Right] = xcurr;
                        break :blk left;
                    } else {
                        // Remove node
                        const right = xcurr.links[Right];
                        if (releaseFn) |f| {
                            f(context, xcurr);
                        }
                        break :blk right;
                    }
                };
            }

            self.root = null;
            self.len = 0;
        }

        /// Find node associated with key.
        pub fn find(self: *Self, key: K) ?*Node {
            var curr = self.root;

            while (curr) |node| {
                const order = cmpKey(getKey(node), key);
                if (order == .eq) {
                    break;
                }
                curr = node.links[directionOfBool(order == .lt)];
            }

            return curr;
        }

        /// Find node associated with key or one whose key is immediately lesser.
        pub fn findEqualOrLesser(self: *Self, key: K) ?*Node {
            var curr = self.root;
            var lesser: ?*Node = null;

            while (curr) |node| {
                const order = cmpKey(getKey(node), key);
                if (order == .eq) {
                    break;
                }
                if (order == .lt) {
                    lesser = node;
                }
                curr = node.links[directionOfBool(order == .lt)];
            }

            return if (curr != null) curr else lesser;
        }

        /// Find node associated with key or one whose key is immediately greater.
        pub fn findEqualOrGreater(self: *Self, key: K) ?*Node {
            var curr = self.root;
            var greater: ?*Node = null;

            while (curr) |node| {
                const order = cmpKey(getKey(node), key);
                if (order == .eq) {
                    break;
                }
                if (order == .gt) {
                    greater = node;
                }
                curr = node.links[directionOfBool(order == .lt)];
            }

            return if (curr != null) curr else greater;
        }

        /// Returns the node with the lowest key in the tree.
        pub fn findLowest(self: *Self) ?*Node {
            return self.edgeNode(Left);
        }

        /// Returns the node with the highest key in the tree.
        pub fn findHighest(self: *Self) ?*Node {
            return self.edgeNode(Right);
        }

        fn edgeNode(self: *Self, dir: Direction) ?*Node {
            var node = self.root;
            while (node) |xnode| {
                if (xnode.links[dir]) |child| {
                    node = child;
                } else {
                    break;
                }
            }
            return node;
        }

        /// Apply calls the given apply function on all data stored in the tree left to right.
        pub fn apply(self: *Self, context: anytype, applyFn: fn(@TypeOf(context), *Node) void) void {
            if (self.root) |root| {
                applyNode(root, context, applyFn);
            }
        }

        fn applyNode(node: *Node, context: anytype, applyFn: fn(@TypeOf(context), *Node) void) void {
            if (node.links[Left]) |left| {
                applyNode(left, context, applyFn);
            }
            applyFn(context, node);
            if (node.links[Right]) |right| {
                applyNode(right, context, applyFn);
            }
        }

        /// Validate tree invariants.
        /// A valid tree should always be balanced and sorted.
        pub fn validate(self: *Self) ValidationResult {
            var result = ValidationResult{};

            if (self.root) |node| {
                _ = self.validateNode(node, &result.balanced, &result.sorted, 0);
            }
            return result;
        }

        fn validateNode(self: *Self, node: *Node, balanced: *bool, sorted: *bool, depth: i32) i32 {
            const key = getKey(node);
            var depthLink = [DirectionCount]i32{0, 0};

            for ([_]Direction{Left, Right}) |dir| {
                depthLink[dir] = blk: {
                    if (node.links[dir]) |childNode| {
                        const order = cmpKey(getKey(childNode), key);
                        if (order == .eq or dir == directionOfBool(order == .lt)) {
                            sorted.* = false;
                        }
                        break :blk self.validateNode(childNode, balanced, sorted, depth + 1);
                    } else {
                        break :blk depth + 1;
                    }
                };
            }

            const depthLeft  = depthLink[Left];
            const depthRight = depthLink[Right];

            if (abs(depthLeft - depthRight) > 1) {
                balanced.* = false;
            }

            return max(depthLeft, depthRight);
        }
    };
}

/// Node stored in AVL tree.
///
/// D: Type of datum carried by node.
///
pub fn NodeType(comptime D: type) type {
    return struct {
        const Self = @This();

        links:   [DirectionCount]?*Self = [DirectionCount]?*Self{null, null},
        balance: i32 = 0,
        datum:   D,

        fn deinitLinks(self: *Self) void {
            self.links[0] = null;
            self.links[1] = null;
            self.balance  = 0;
        }

        fn copyLinksFrom(self: *Self, other: *Self) void {
            self.links   = other.links;
            self.balance = other.balance;
        }

        // Two way single rotation.
        fn single(self: *Self, dir: Direction) *Self {
            const odir = otherDirection(dir);
            const save = self.links[odir].?;
            self.links[odir] = save.links[dir];
            save.links[dir] = self;
            return save;
        }

        // Two way double rotation.
        fn double(self: *Self, dir: Direction) *Self {
            const odir = otherDirection(dir);
            const save = self.links[odir].?.links[dir].?;
            self.links[odir].?.links[dir] = save.links[odir];
            save.links[odir] = self.links[odir];
            self.links[odir] = save;

            const save2 = self.links[odir].?;
            self.links[odir] = save2.links[dir];
            save2.links[dir] = self;
            return save;
        }

        // Adjust balance before double rotation.
        fn adjustBalance(self: *Self, dir: Direction, bal: i32) void {
            const n1 = self.links[dir].?;
            const n2 = n1.links[otherDirection(dir)].?;

            if (n2.balance == 0) {
                self.balance = 0;
                n1.balance = 0;
            } else if (n2.balance == bal) {
                self.balance = -bal;
                n1.balance = 0;
            } else {
                // n2.balance == -bal
                self.balance = 0;
                n1.balance = bal;
            }
            n2.balance = 0;
        }

        fn adjustBalanceAdd(self: *Self, dir: Direction) *Self {
            const n = self.links[dir].?;
            const bal = balanceOfDirection(dir);

            return blk: {
                if (n.balance == bal) {
                    self.balance = 0;
                    n.balance = 0;
                    break :blk self.single(otherDirection(dir));
                } else {
                    // n.balance == -bal
                    self.adjustBalance(dir, bal);
                    break :blk self.double(otherDirection(dir));
                }
            };
        }

        fn adjustBalanceRemove(self: *Self, dir: Direction, done: *bool) *Self {
            const n = self.links[otherDirection(dir)].?;
            const bal = balanceOfDirection(dir);

            return blk: {
                if (n.balance == -bal) {
                    self.balance = 0;
                    n.balance = 0;
                    break :blk self.single(dir);
                } else if (n.balance == bal) {
                    self.adjustBalance(otherDirection(dir), -bal);
                    break :blk self.double(dir);
                } else {
                    // n.balance == 0
                    self.balance = -bal;
                    n.balance = bal;
                    done.* = true;
                    break :blk self.single(dir);
                }
            };
        }
    };
}

/// Tree validation result.
pub const ValidationResult = struct {
    balanced: bool = true,
    sorted:   bool = true,
};

const Direction = u1;
const Left:  Direction = 0;
const Right: Direction = 1;
const DirectionCount = 2;

inline fn otherDirection(dir: Direction) Direction {
    return ~dir;
}

inline fn balanceOfDirection(dir: Direction) i32 {
    return switch (dir) {
        Left  => -1,
        Right =>  1,
    };
}

inline fn inverseBalanceOfDirection(dir: Direction) i32 {
    return switch (dir) {
        Left  =>  1,
        Right => -1,
    };
}

inline fn directionOfBool(b: bool) Direction {
    return if (b) Right else Left;
}

const max = std.math.max;

// We can do without the error checks of std.math.absInt
inline fn abs(x: anytype) @TypeOf(x) {
    return if (x < 0) -x else x;
}

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

        for (nodes) |*node, i| {
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

        for (nodes) |*node, i| {
            const rnode = tree.add(node);
            if (rnode != node) {
                std.debug.panic("Failed to add datum={}, index={}, sequence={}, returnedDatum={}",
                                .{node.datum, i, seq, rnode.datum});
            }
        }

        for (dst) |value, i| {
            const rnode = tree.remove(value);
            if (rnode) |node| {
                if (node.datum != value) {
                    std.debug.panic("Failed to remove datum={}, index={}, sequence={}, returnedDatum={}",
                                    .{value, i, seq, node.datum});
                }
            } else {
                std.debug.panic("Failed to remove datum={}, index={}, sequence={}, returnedNode={}",
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
    var node = tree.remove(1);
    try Test.expectEqual(@as(?*Test.Tree.Node, null), node);
}

test "remove non existing" {
    const testValues = [_]Test.Value{1, 2, 3, 5};
    var nodes: [testValues.len]Test.Tree.Node = undefined;
    Test.initNodes(&nodes, &testValues);

    var tree = Test.Tree{};
    Test.populateTree(&tree, &nodes);

    var node = tree.remove(4);
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
    for (nodes) |*node| {
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
        lookupFn: fn(*Test.Tree, u32) ?u32,
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

    for (testData) |*t| {
        const output = t.lookupFn(&tree, t.input);
        const noneMarker = 99;
        if ((output orelse noneMarker) != (t.output orelse noneMarker)) {
            std.debug.panic("{s}: input={}, output={}; expect={}", .{t.name, t.input, output, t.output});
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
    const expectEqual = std.testing.expectEqual;

    const Tree = TreeType(u32, u32, getKey, cmpKey);

    fn getKey(node: *NodeType(u32)) u32 {
        return node.datum;
    }

    fn cmpKey(lhs: u32, rhs: u32) math.Order {
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
        for (t) |_, i| {
            t[i] = @intCast(Value, i);
        }
        return t;
    }

    fn initNodes(nodes: []Node, values: []const Value) void {
        for (values) |value, i| {
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
        const alen = @intCast(u32, src.len);

        var fact = factorial(alen);

        // Out of range?
        if ((seq / alen) >= fact) {
            return false;
        }

        mem.copy(u32, dst[0..], src[0..]);

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
