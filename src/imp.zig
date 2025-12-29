const std = @import("std");

const Tree = @import("Tree.zig");
const VTable = Tree.VTable;
const Offer = Tree.Offer;

const Sink = @import("render.zig").Sink;

// Associative operation. We store a list of operands, and not a binary tree.
const AssOp = enum {
    add,
    mul,

    fn le(a: @This(), b: @This()) bool {
        return @intFromEnum(a) <= @intFromEnum(b);
    }
};

const Expr = union(enum) {
    e_const: u64,
    e_assop: struct { o: AssOp, args: OpList },
    e_hole,

    const Self = @This();

    fn free_children(node: *Self) void {
        switch (node.*) {
            .e_assop => |*op| {
                for (op.args.items) |*arg| {
                    free_children(arg);
                }
                op.args.clearAndFree(cator);
            },
            else => {},
        }
    }

    pub fn render(
        self: *Self,
        sink: *Sink,
        parent_op: AssOp,
    ) !void {
        sink.start_node(self);

        switch (self.*) {
            .e_const => |n| try sink.buf.print(cator, "{}", .{n}),
            .e_assop => |op| {
                const needs_paren = op.o.le(parent_op);

                if (needs_paren) {
                    try sink.buf.append(cator, '(');
                }

                if (op.args.items.len > 0) {
                    try op.args.items[0].render(sink, op.o);

                    for (op.args.items[1..]) |*arg| {
                        try sink.buf.append(cator, ' ');
                        try sink.buf.append(cator, switch (op.o) {
                            .add => '+',
                            .mul => '*',
                        });
                        try sink.buf.append(cator, ' ');
                        try arg.render(sink, op.o);
                    }
                }

                if (needs_paren) {
                    try sink.buf.append(cator, ')');
                }
            },
            .e_hole => {
                try sink.buf.appendSlice(cator, "◆");
            },
        }

        sink.end_node(self);
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_const => 0,
            .e_assop => |op| op.args.items.len,
            .e_hole => 0,
        };
    }

    fn get_nth_child(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_const => null,
            .e_assop => |op| if (n < op.args.items.len) op.args.items[n].to_tree() else null,
            .e_hole => null,
        };
    }

    fn insert_at(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_assop => |*p| {
                if (i < p.args.items.len) {
                    p.args.insert(cator, i, .e_hole) catch std.process.exit(1);
                    return true;
                } else {
                    return false;
                }
            },
            else => return false,
        };
    }

    fn remove_at(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_assop => |*p| {
                if (i < p.args.items.len) {
                    var x = p.args.orderedRemove(i);
                    x.free_children();

                    if (p.args.items.len == 1) {
                        var v = p.args;
                        const c = v.items[0];
                        v.clearAndFree(cator);
                        self.* = c;

                        return .replaced;
                    }

                    const new_index = if (p.args.items.len == i) i - 1 else i;

                    return .{ .done = .{ .new_index = new_index } };
                } else {
                    @panic("Invalid remove_at call");
                }
            },
            else => return .not_possible,
        };
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.free_children();
        self.* = .e_hole;
    }

    fn rewrite_as_const(ptr: *anyopaque, n: u64) Allocator.Error!void {
        const p: *Self = @ptrCast(@alignCast(ptr));
        p.* = Self{ .e_const = n };
    }

    fn rewrite_as_add(ptr: *anyopaque) Allocator.Error!void {
        std.debug.print("hehe\n", .{});

        const p: *Self = @ptrCast(@alignCast(ptr));

        var args = try OpList.initCapacity(cator, 2);

        args.appendAssumeCapacity(.e_hole);
        args.appendAssumeCapacity(.e_hole);

        p.* = Expr{ .e_assop = .{ .o = .add, .args = args } };
    }

    fn rewrite_as_mul(ptr: *anyopaque) Allocator.Error!void {
        const p: *Self = @ptrCast(@alignCast(ptr));

        var args = try OpList.initCapacity(cator, 2);

        args.appendAssumeCapacity(.e_hole);
        args.appendAssumeCapacity(.e_hole);

        p.* = Expr{ .e_assop = .{ .o = .mul, .args = args } };
    }

    const replacement_offers = &[_]Offer{
        Offer{
            .name = "constant",
            .rewriter = .{ .from_int = rewrite_as_const },
        },
        Offer{
            .name = "addition",
            .rewriter = .{ .from_void = rewrite_as_add },
        },
        Offer{
            .name = "multiplication",
            .rewriter = .{ .from_void = rewrite_as_mul },
        },
    };

    pub const vt = VTable{
        .child_count = child_count,
        .get_nth_child = get_nth_child,
        .insert_at = insert_at,
        .remove_at = remove_at,
        .make_into_hole = make_into_hole,
        .replacement_offers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const Id = union(enum) {
    id: []const u8,
    hole,

    const Self = @This();

    pub fn render(
        self: *Self,
        sink: *Sink,
    ) !void {
        sink.start_node(self);

        switch (self.*) {
            .id => |s| {
                try sink.buf.appendSlice(cator, s);
            },
            .hole => {
                try sink.buf.appendSlice(cator, "◆");
            },
        }

        sink.end_node(self);
    }

    fn child_count(_: *anyopaque) usize {
        return 0;
    }

    fn get_nth_child(_: *anyopaque, _: usize) ?Tree {
        return null;
    }

    fn insert_at(_: *anyopaque, _: usize) bool {
        return false;
    }

    fn remove_at(_: *anyopaque, _: usize) Tree.RemovalOutcome {
        return .not_possible;
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.* = .hole;
    }

    fn rewrite_id(ptr: *anyopaque, s: []const u8) Allocator.Error!void {
        const p: *Self = @ptrCast(@alignCast(ptr));

        p.* = .{ .id = try cator.dupe(u8, s) };
    }

    const replacement_offers = &[_]Offer{
        Offer{
            .name = "name",
            .rewriter = .{ .from_string = rewrite_id },
        },
    };

    pub const vt = VTable{
        .child_count = child_count,
        .get_nth_child = get_nth_child,
        .insert_at = insert_at,
        .remove_at = remove_at,
        .make_into_hole = make_into_hole,
        .replacement_offers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const Buffer = std.ArrayList(u8);

const Com = union(enum) {
    skip,
    asgn: struct { x: *Id, a: *Expr },
    hole,

    const Self = @This();

    pub fn free_children(self: *Self) void {
        switch (self.*) {
            .asgn => |p| p.a.free_children(),
            else => {},
        }
    }

    pub fn render(
        self: *Self,
        sink: *Sink,
    ) !void {
        sink.start_node(self);

        switch (self.*) {
            .skip => {
                try sink.buf.appendSlice(cator, "skip");
            },
            .asgn => |asgn| {
                try asgn.x.render(sink);
                try sink.buf.appendSlice(cator, " := ");
                try asgn.a.render(sink, AssOp.add);
            },
            .hole => {
                try sink.buf.appendSlice(cator, "◆");
            },
        }

        sink.end_node(self);
    }

    pub fn overwrite(p: *Com, c: Com) void {
        p.free_children();
        p.* = c;
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .skip => 0,
            .asgn => 2,
            .hole => 0,
        };
    }

    fn get_nth_child(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .skip => null,
            .asgn => |s| switch (n) {
                0 => s.x.to_tree(),
                1 => s.a.to_tree(),
                else => null,
            },
            .hole => null,
        };
    }

    fn insert_at(_: *anyopaque, _: usize) bool {
        return false;
    }

    fn remove_at(_: *anyopaque, _: usize) Tree.RemovalOutcome {
        return .not_possible;
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.free_children();
        self.* = .hole;
    }

    fn raw_render(ptr: *anyopaque, sink: *Sink) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.render(sink);
    }

    fn rewrite_as_skip(ptr: *anyopaque) Allocator.Error!void {
        const p: *Self = @ptrCast(@alignCast(ptr));

        p.* = .skip;
    }

    fn rewrite_as_asgn(ptr: *anyopaque) Allocator.Error!void {
        const p: *Self = @ptrCast(@alignCast(ptr));

        const px = try cator.create(Id);
        const pa = try cator.create(Expr);

        px.* = .hole;
        pa.* = .e_hole;

        p.* = .{ .asgn = .{ .x = px, .a = pa } };
    }

    const replacement_offers = &[_]Offer{
        Offer{
            .name = "skip",
            .rewriter = .{ .from_void = rewrite_as_skip },
        },
        Offer{
            .name = "assignment",
            .rewriter = .{ .from_void = rewrite_as_asgn },
        },
    };

    pub const vt = VTable{
        .child_count = child_count,
        .get_nth_child = get_nth_child,
        .insert_at = insert_at,
        .remove_at = remove_at,
        .make_into_hole = make_into_hole,
        .render = raw_render,
        .replacement_offers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const OpList = std.ArrayList(Expr);

const cator = std.heap.c_allocator;
const Allocator = std.mem.Allocator;

pub fn create_sample() Allocator.Error!Tree {
    const e3 = try cator.create(Expr);
    e3.* = Expr{ .e_const = 3 };

    const et = blk: {
        var args = try OpList.initCapacity(cator, 2);
        args.appendAssumeCapacity(Expr{ .e_const = 2 });
        args.appendAssumeCapacity(Expr{ .e_const = 3 });
        break :blk Expr{ .e_assop = .{ .o = AssOp.mul, .args = args } };
    };

    const ep = try cator.create(Expr);
    ep.* = blk: {
        var args = try OpList.initCapacity(cator, 3);
        args.appendAssumeCapacity(Expr{ .e_const = 1 });
        args.appendAssumeCapacity(et);
        args.appendAssumeCapacity(Expr{ .e_const = 4 });
        break :blk Expr{ .e_assop = .{ .o = .add, .args = args } };
    };

    const i = try cator.create(Id);
    i.* = .{ .id = "foo" };

    const c = try cator.create(Com);
    c.* = .{ .asgn = .{ .x = i, .a = ep } };

    return c.to_tree();
}
