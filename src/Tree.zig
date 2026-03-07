const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error;

ptr: *anyopaque,
vtable: *const VTable,
replacement_offers: []const Offer,

const Sink = @import("render.zig").Sink;

pub const VTable = struct {
    childCount: *const fn (*anyopaque) usize,

    childAt: *const fn (*anyopaque, i: usize) Self,

    insertAt: *const fn (*anyopaque, i: usize) Error!bool,

    removeAt: *const fn (*anyopaque, i: usize) RemovalOutcome,

    render: *const fn (*anyopaque, sink: *Sink) Allocator.Error!void,
};

const Self = @This();

pub fn childCount(self: *Self) usize {
    return self.vtable.childCount(self.ptr);
}

pub fn childAt(self: *Self, n: usize) Self {
    return self.vtable.childAt(self.ptr, n);
}

pub fn insertAt(self: *Self, i: usize) Error!bool {
    return self.vtable.insertAt(self.ptr, i);
}

pub const RemovalOutcome = union(enum) {
    done,
    not_possible,
    // "Replaced" means that the removal was performed and resulted in a
    // single-element list that was replaced with the single element directly.
    replaced,
};

pub fn removeAt(self: *Self, i: usize) RemovalOutcome {
    return self.vtable.removeAt(self.ptr, i);
}

pub fn render(self: *Self, sink: *Sink) Allocator.Error!void {
    return self.vtable.render(self.ptr, sink);
}

pub const Rewriter = union(enum) {
    from_void: *const fn (*anyopaque) Allocator.Error!void,
    from_string: *const fn (*anyopaque, []const u8) Allocator.Error!void,
    from_int: *const fn (*anyopaque, u64) Allocator.Error!void,
};

pub const Offer = struct {
    name: [:0]const u8,
    rewriter: Rewriter,
};

pub fn getOffers(self: *const Self) []const Offer {
    return self.replacement_offers;
}

pub fn eq(a: Self, b: Self) bool {
    return a.ptr == b.ptr and a.vtable == b.vtable;
}
