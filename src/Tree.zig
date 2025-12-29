const std = @import("std");
const Allocator = std.mem.Allocator;

ptr: *anyopaque,
vtable: *const VTable,

const Sink = @import("render.zig").Sink;

pub const VTable = struct {
    child_count: *const fn (*anyopaque) usize,

    get_nth_child: *const fn (*anyopaque, n: usize) ?Self,

    insert_at: *const fn (*anyopaque, i: usize) bool,

    remove_at: *const fn (*anyopaque, i: usize) RemovalOutcome,

    make_into_hole: *const fn (*anyopaque) void,

    render: ?*const fn (*anyopaque, sink: *Sink) Allocator.Error!void = null,

    replacement_offers: []const Offer,
};

const Self = @This();

pub fn child_count(self: *Self) usize {
    return self.vtable.child_count(self.ptr);
}

pub fn get_nth_child(self: *Self, n: usize) ?Self {
    return self.vtable.get_nth_child(self.ptr, n);
}

pub fn insert_at(self: *Self, i: usize) bool {
    return self.vtable.insert_at(self.ptr, i);
}

pub const RemovalOutcome = union(enum) {
    done: struct { new_index: usize },
    not_possible,
    // "Replaced" means that the removal was performed and resulted in a
    // single-element list that was replaced with the single element directly.
    replaced,
};

pub fn remove_at(self: *Self, i: usize) RemovalOutcome {
    return self.vtable.remove_at(self.ptr, i);
}

pub fn make_into_hole(self: *Self) void {
    self.vtable.make_into_hole(self.ptr);
}

pub fn render(self: *Self, sink: *Sink) Allocator.Error!void {
    if (self.vtable.render) |f| {
        return f(self.ptr, sink);
    }
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

pub fn get_offers(self: *const Self) []const Offer {
    return self.vtable.replacement_offers;
}
