const std = @import("std");

const Allocator = std.mem.Allocator;

/// An element in a circular double linked list.
//
/// The most useful property is that an element can remove itself from a list without having a
/// referece to it with O(1) time complexity. One element is selected to act as the head of the
/// list. Iteration is performed by following next or previous links from the head node until they
/// point to the head node.
pub fn Elem(comptime T: type) type {
    return struct {
        next_: *@This(),
        prev_: *@This(),
        value: T,

        /// Initialize element with the specified value and next and prev links pointing to itself
        /// thereby forming a single element list.
        pub fn init(self: *@This(), value: T) void {
            self.next_ = self;
            self.prev_ = self;
            self.value = value;
        }

        /// Allocate element using the supplied allocator and initialize it the same way init does.
        pub fn new(allocator: *Allocator, value: T) !*@This() {
            var elem = try allocator.create(@This());
            init(elem, value);
            return elem;
        }

        /// Link other element next to self.
        pub fn linkNext(self: *@This(), other: *@This()) void {
            const tmp = other.prev_;
            self.next_.prev_ = tmp;
            tmp.next_ = self.next_;
            other.prev_ = self;
            self.next_ = other;
        }

        /// Link other element previous to self.
        pub fn linkPrev(self: *@This(), other: *@This()) void {
            const tmp = other.prev_;
            self.prev_.next_ = other;
            tmp.next_ = self;
            other.prev_ = self.prev_;
            self.prev_ = tmp;
        }

        /// Unlink element from any list that it's part of.
        /// This function is safe to call on linked and unlinked elements provided that the element
        /// has at one time been initialized properly.
        pub fn unlink(self: *@This()) void {
            self.next_.prev_ = self.prev_;
            self.prev_.next_ = self.next_;
            self.next_ = self;
            self.prev_ = self;
        }

        /// Follow the next link of element.
        pub inline fn next(self: *@This()) *@This() {
            return self.next_;
        }

        /// Follow the previous link of element.
        pub inline fn prev(self: *@This()) *@This() {
            return self.prev_;
        }

        /// Check if element is linked to another element than itself.
        /// This can be applied to the sentinel list head element to check if the list is empty.
        pub inline fn isLinked(self: *@This()) bool {
            return self.next_ != self;
        }
    };
}

const expect = std.testing.expect;

const TestElem = Elem(i32);

const TestLink = struct {
    next: *TestElem,
    prev: *TestElem,
};

fn initTestElems(elems: []TestElem) void {
    for (elems) |*elem, i| {
        elem.init(@intCast(i32, i));
    }
}

fn checkTestLinks(firstElem: *TestElem, expectedLinks: []const TestLink) void {
    var e = firstElem;
    for (expectedLinks) |v, i| {
        if (e.next() != v.next) {
            std.debug.panic("expected next node of {} (index {}) to be {}; got {}",
                            e.value, i, v.next.value, e.next().value);
        }
        if (e.prev() != v.prev) {
            std.debug.panic("expected previous node of {} (index {}) to be {}; got {}",
                            e.value, i, v.prev.value, e.prev().value);            
        }
        e = e.next();
     }
}

test "linkNext" {
    var e: [5]TestElem = undefined;
    initTestElems(e[0..]);

    // Link elements form a list
    const h1 = &e[0];
    h1.linkNext(&e[1]);
    h1.linkNext(&e[2]);

    // Link two multi element lists together
    const h2 = &e[3];
    h2.linkNext(&e[4]);
    h1.linkNext(h2);

    // Expected element order [0, 3, 4, 2, 1]
    const expectedLinks = [_]TestLink{
        TestLink{.next = &e[3], .prev = &e[1]},
        TestLink{.next = &e[4], .prev = &e[0]},
        TestLink{.next = &e[2], .prev = &e[3]},
        TestLink{.next = &e[1], .prev = &e[4]},
        TestLink{.next = &e[0], .prev = &e[2]},
    };
    
    checkTestLinks(h1, expectedLinks[0..]);
}

test "linkPrev" {
    var e: [5]TestElem = undefined;
    initTestElems(e[0..]);

    // Link elements form a list
    const h1 = &e[0];
    h1.linkPrev(&e[1]);
    h1.linkPrev(&e[2]);

    // Link two multi element lists together
    const h2 = &e[3];
    h2.linkPrev(&e[4]);
    h1.linkPrev(h2);

    // Expected element order [0, 1, 2, 3, 4]
    const expectedLinks = [_]TestLink{
        TestLink{.next = &e[1], .prev = &e[4]},
        TestLink{.next = &e[2], .prev = &e[0]},
        TestLink{.next = &e[3], .prev = &e[1]},
        TestLink{.next = &e[4], .prev = &e[2]},
        TestLink{.next = &e[0], .prev = &e[3]},
    };
    
    checkTestLinks(h1, expectedLinks[0..]);
}

test "unlink" {
    var e: [3]TestElem = undefined;
    initTestElems(e[0..]);

    const h1 = &e[0];

    h1.linkPrev(&e[1]);
    h1.linkPrev(&e[2]);

    // Expected element order [0, 2]
    e[1].unlink();
    const expectedLinks = [_]TestLink{
        TestLink{.next = &e[2], .prev = &e[2]},
        TestLink{.next = &e[0], .prev = &e[0]},
    };
    checkTestLinks(h1, expectedLinks[0..]);

    // Test that the unlinked element point to itself
    const expectedLinks2 = [_]TestLink{
        TestLink{.next = &e[1], .prev = &e[1]},
    };
    checkTestLinks(&e[1], expectedLinks2[0..]);

    // Remove last element
    // Expected element order [0]
    //
    // Do it twice to make sure that unlinking an unlinked element has no effect.
    const expectedLinks3 = [_]TestLink{
        TestLink{.next = &e[0], .prev = &e[0]},
    };
    var i = usize(0);
    while (i < 2) : (i += 1) {
        e[2].unlink();
        checkTestLinks(h1, expectedLinks3[0..]);
    }
}

test "isLinked" {
    var buffer: [100]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(&buffer).allocator;

    const e0 = try TestElem.new(allocator, 0);
    const e1 = try TestElem.new(allocator, 1);

    expect(!e0.isLinked());
    
    e0.linkPrev(e1);
    expect(e0.isLinked());
    expect(e1.isLinked());
}

test "iterate" {
    var e: [5]TestElem = undefined;
    initTestElems(e[0..]);

    const h = &e[0];
    for (e[1..]) |*t| {
        h.linkPrev(t);
    }

    var sum = i32(0);
    var it = h.next();
    while (it != h) : (it = it.next()) {
        sum += it.value;
    }

    expect(sum == 1 + 2 + 3 + 4);
}
