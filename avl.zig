// Based on code originally written by Julienne Walker in the public domain,
// https://web.archive.org/web/20070212102708/http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_avl.aspx

const std = @import("std");
const avl = @This();

const maxTreeHeight = 36;

// TODO:
//
// I would like some things optional at comptime that has storage or
// compute implications. For example by passing a struct like follows to
// Tree to enable certain features.
//
//     const TreeOptions = struct {
//        withLen: bool = false,
//        withIter: bool = false,
//     };
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
pub fn Tree(comptime D: type, comptime K: type, getKey: fn(*Node(D)) K, cmpKey: fn(lhs: K, rhs: K) std.math.Order) type {
    return struct {
        /// Type of nodes held by tree.
        pub const Node = avl.Node(D);

        const This = @This();

        root: ?*This.Node = null,
        len: usize = 0,

        /// Add node into tree. Returns the added node or one already in the tree with an identical
        /// key. The caller must check the return value to determine if the node was added or a
        /// duplicate was found.
        pub fn add(tree: *This, node: *This.Node) *This.Node {
            // Empty tree case.
            if (tree.root == null) {
                tree.root = node;
                tree.len += 1;
                return node;
            }

            const key = getKey(node);

            // Set up false tree root to ease maintenance
            var head = This.Node{.datum = undefined};
            var t = &head;
            t.links[Right] = tree.root;

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

            const q = s; // Save rebalance point for parent fix

            // Rebalance if necessary
            if (abs(s.balance) > 1) {
                dir = directionOfBool(cmpKey(getKey(s), key) == .lt);
                s = s.adjustBalanceAdd(dir);
            }

            // Fix parent
            if (q == head.links[Right]) {
                tree.root = s;
            } else {
                t.links[directionOfBool(q == t.links[Right])] = s;
            }

            tree.len += 1;
            return node;
        }

        /// Remove node associated with key from tree.
        pub fn remove(tree: *This, key: K) ?*This.Node {
            var curr = tree.root orelse return null;

            var up:  [maxTreeHeight]*This.Node = undefined;
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
                    tree.root = curr.links[dir];
                }
            } else {
                // Find the inorder successor
                var heir = rightNode.?;

                var parent: ?*This.Node = null;
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
                    tree.root = heir;
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
                        tree.root = up[0];
                    }
                }
            }

            curr.deinitLinks();
            tree.len -= 1;
            return curr;
        }

        /// Remove all nodes from the tree.
        /// The release function with supplied context is called on each removed node.
        /// Use {} as context if no release function is supplied.
        pub fn clear(tree: *This, context: anytype, releaseFn: ?fn(@TypeOf(context), *This.Node) void) void {
            var curr = tree.root;

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

            tree.root = null;
            tree.len = 0;
        }

        /// Find node associated with key.
        pub fn find(tree: *This, key: K) ?*This.Node {
            var curr = tree.root;

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
        pub fn findEqualOrLesser(tree: *This, key: K) ?*This.Node {
            var curr = tree.root;
            var lesser: ?*This.Node = null;

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
        pub fn findEqualOrGreater(tree: *This, key: K) ?*This.Node {
            var curr = tree.root;
            var greater: ?*This.Node = null;

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
        pub fn findLowest(tree: *This) ?*This.Node {
            return tree.edgeNode(Left);
        }

        /// Returns the node with the highest key in the tree.
        pub fn findHighest(tree: *This) ?*This.Node {
            return tree.edgeNode(Right);
        }

        fn edgeNode(tree: *This, dir: Direction) ?*This.Node {
            var node = tree.root;
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
        pub fn apply(tree: *This, context: anytype, applyFn: fn(@TypeOf(context), *This.Node) void) void {
            if (tree.root) |root| {
                applyNode(root, context, applyFn);
            }
        }

        fn applyNode(node: *This.Node, context: anytype, applyFn: fn(@TypeOf(context), *This.Node) void) void {
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
        pub fn validate(tree: *This) ValidationResult {
            var result = ValidationResult{};

            if (tree.root) |node| {
                _ = tree.validateNode(node, &result.balanced, &result.sorted, 0);
            }
            return result;
        }

        fn validateNode(tree: *This, node: *This.Node, balanced: *bool, sorted: *bool, depth: i32) i32 {
            const key = getKey(node);
            var depthLink = [DirectionCount]i32{0, 0};

            for ([_]Direction{Left, Right}) |dir| {
                depthLink[dir] = blk: {
                    if (node.links[dir]) |childNode| {
                        const order = cmpKey(getKey(childNode), key);
                        if (order == .eq or dir == directionOfBool(order == .lt)) {
                            sorted.* = false;
                        }
                        break :blk tree.validateNode(childNode, balanced, sorted, depth + 1);
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

            return @max(depthLeft, depthRight);
        }
    };
}

/// Node stored in AVL tree.
///
/// D: Type of datum carried by node.
///
pub fn Node(comptime D: type) type {
    return struct {
        const This = @This();

        links:   [DirectionCount]?*This = [DirectionCount]?*This{null, null},
        balance: i32 = 0,
        datum:   D,

        fn deinitLinks(node: *This) void {
            node.links[0] = null;
            node.links[1] = null;
            node.balance  = 0;
        }

        fn copyLinksFrom(node: *This, other: *This) void {
            node.links   = other.links;
            node.balance = other.balance;
        }

        // Two way single rotation.
        fn single(node: *This, dir: Direction) *This {
            const odir = otherDirection(dir);
            const save = node.links[odir].?;
            node.links[odir] = save.links[dir];
            save.links[dir] = node;
            return save;
        }

        // Two way double rotation.
        fn double(node: *This, dir: Direction) *This {
            const odir = otherDirection(dir);
            const save = node.links[odir].?.links[dir].?;
            node.links[odir].?.links[dir] = save.links[odir];
            save.links[odir] = node.links[odir];
            node.links[odir] = save;

            const save2 = node.links[odir].?;
            node.links[odir] = save2.links[dir];
            save2.links[dir] = node;
            return save;
        }

        // Adjust balance before double rotation.
        fn adjustBalance(node: *This, dir: Direction, bal: i32) void {
            const n1 = node.links[dir].?;
            const n2 = n1.links[otherDirection(dir)].?;

            if (n2.balance == 0) {
                node.balance = 0;
                n1.balance = 0;
            } else if (n2.balance == bal) {
                node.balance = -bal;
                n1.balance = 0;
            } else {
                // n2.balance == -bal
                node.balance = 0;
                n1.balance = bal;
            }
            n2.balance = 0;
        }

        fn adjustBalanceAdd(node: *This, dir: Direction) *This {
            const n = node.links[dir].?;
            const bal = balanceOfDirection(dir);

            return blk: {
                if (n.balance == bal) {
                    node.balance = 0;
                    n.balance = 0;
                    break :blk node.single(otherDirection(dir));
                } else {
                    // n.balance == -bal
                    node.adjustBalance(dir, bal);
                    break :blk node.double(otherDirection(dir));
                }
            };
        }

        fn adjustBalanceRemove(node: *This, dir: Direction, done: *bool) *This {
            const n = node.links[otherDirection(dir)].?;
            const bal = balanceOfDirection(dir);

            return blk: {
                if (n.balance == -bal) {
                    node.balance = 0;
                    n.balance = 0;
                    break :blk node.single(dir);
                } else if (n.balance == bal) {
                    node.adjustBalance(otherDirection(dir), -bal);
                    break :blk node.double(dir);
                } else {
                    // n.balance == 0
                    node.balance = -bal;
                    n.balance = bal;
                    done.* = true;
                    break :blk node.single(dir);
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

// We can do without the error checks of std.math.absInt
inline fn abs(x: anytype) @TypeOf(x) {
    return if (x < 0) -x else x;
}
