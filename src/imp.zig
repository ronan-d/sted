const std = @import("std");

const Tree = @import("Tree.zig");
const VTable = Tree.VTable;
const Offer = Tree.Offer;

const Sink = @import("render.zig").Sink;

const assoc = @import("assoc.zig");

const Expr = union(enum) {
    e_const: u64,
    e_assop: assoc.Operation(OperandType, OperatorType),
    e_hole,

    pub const OperatorType = enum {
        add,
        mul,

        pub fn is_not_greater_than(a: @This(), b: @This()) bool {
            return @intFromEnum(a) <= @intFromEnum(b);
        }

        pub fn render(self: @This(), sink: *Sink) !void {
            try sink.append_ascii(switch (self) {
                .add => "+",
                .mul => "*",
            });
        }
    };

    const OperandType = Self;

    fn hole() Self {
        return .e_hole;
    }

    const Self = @This();

    pub fn drop(node: *Self) void {
        switch (node.*) {
            .e_const => {},
            .e_assop => |*op| {
                op.drop();
            },
            .e_hole => {},
        }
    }

    pub fn render(
        self: *const Self,
        sink: *Sink,
        parent_op: ?OperatorType,
    ) !void {
        sink.start_node(self);

        switch (self.*) {
            .e_const => |n| {
                const len_before = sink.buf.items.len;
                try sink.buf.print(cator, "{}", .{n});
                sink.code_point_counter += sink.buf.items.len - len_before;
            },
            .e_assop => |op| {
                try op.render(sink, parent_op);
            },
            .e_hole => {
                try sink.append("◆", 1);
            },
        }

        sink.end_node(self);
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_const => 0,
            .e_assop => |op| op.operands.items.len,
            .e_hole => 0,
        };
    }

    fn get_nth_child(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_const => null,
            .e_assop => |op| if (op.get_nth_child(n)) |x| x.to_tree() else null,
            .e_hole => null,
        };
    }

    fn insert_at(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_assop => |*p| {
                return p.insert_at(i, .e_hole) catch unreachable;
            },
            else => return false,
        };
    }

    fn remove_at(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .e_assop => |*p| {
                switch (p.remove_at(i)) {
                    .normal => {
                        const new_index = if (p.operands.items.len == i) i - 1 else i;

                        return .{ .done = .{ .new_index = new_index } };
                    },
                    .replaced => |x| {
                        self.* = x;
                        return .replaced;
                    },
                }
            },
            else => return .not_possible,
        };
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.drop();
        self.* = .e_hole;
    }

    fn rewrite_as_const(ptr: *anyopaque, n: u64) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{ .e_const = n };
    }

    fn rewrite_as_add(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{
            .e_assop = try assoc.Operation(OperandType, OperatorType).make_initial_value(.add, .e_hole),
        };
    }

    fn rewrite_as_mul(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{
            .e_assop = try assoc.Operation(OperandType, OperatorType).make_initial_value(.add, .e_hole),
        };
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

    pub fn render(self: *Self, sink: *Sink) !void {
        sink.start_node(self);

        switch (self.*) {
            .id => |s| {
                try sink.append_ascii(s);
            },
            .hole => {
                try sink.append("◆", 1);
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
    conditional: struct { cond: *BExpr, then_branch: ComSeq, else_branch: ComSeq },
    while_loop: struct { cond: *BExpr, commands: ComSeq },
    hole,

    const Self = @This();

    pub fn drop(self: *Self) void {
        switch (self.*) {
            .skip => {},
            .asgn => |p| p.a.drop(),
            .conditional => |*x| {
                x.cond.drop();
                cator.destroy(x.cond);

                x.then_branch.drop();
                x.else_branch.drop();
            },
            .while_loop => |*x| {
                x.cond.drop();
                cator.destroy(x.cond);

                x.commands.drop();
            },
            .hole => {},
        }
    }

    pub fn render(self: *const Self, sink: *Sink) Allocator.Error!void {
        sink.start_node(self);

        switch (self.*) {
            .skip => {
                try sink.append_ascii("skip");
            },
            .asgn => |asgn| {
                try asgn.x.render(sink);
                try sink.append_ascii(" := ");
                try asgn.a.render(sink, null);
            },
            .conditional => |*x| {
                try sink.append_ascii("if ");

                try x.cond.render(sink, null);

                try sink.append_ascii(" then");

                sink.increase_indentation();

                try sink.break_line();

                try x.then_branch.render(sink);

                sink.decrease_indentation();

                try sink.break_line();

                try sink.append_ascii("else");

                sink.increase_indentation();

                try sink.break_line();

                try x.else_branch.render(sink);

                sink.decrease_indentation();
            },
            .while_loop => |*x| {
                try sink.append_ascii("while ");

                try x.cond.render(sink, null);

                try sink.append_ascii(" do");

                sink.increase_indentation();

                try sink.break_line();

                try x.commands.render(sink);

                sink.decrease_indentation();
            },
            .hole => {
                try sink.append("◆", 1);
            },
        }

        sink.end_node(self);
    }

    pub fn overwrite(p: *Com, c: Com) void {
        p.drop();
        p.* = c;
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .skip => 0,
            .asgn => 2,
            .conditional => 3,
            .while_loop => 2,
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
            .conditional => |*x| switch (n) {
                0 => x.cond.to_tree(),
                1 => x.then_branch.to_tree(),
                2 => x.else_branch.to_tree(),
                else => null,
            },
            .while_loop => |*x| switch (n) {
                0 => x.cond.to_tree(),
                1 => x.commands.to_tree(),
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

        self.drop();
        self.* = .hole;
    }

    fn raw_render(ptr: *anyopaque, sink: *Sink) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.render(sink);
    }

    fn rewrite_as_skip(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = .skip;
    }

    fn rewrite_as_asgn(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const px = try cator.create(Id);
        const pa = try cator.create(Expr);

        px.* = .hole;
        pa.* = .e_hole;

        self.drop();
        self.* = .{ .asgn = .{ .x = px, .a = pa } };
    }

    fn rewrite_as_if(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const cond = try cator.create(BExpr);
        cond.* = .hole;

        self.* = .{
            .conditional = .{
                .cond = cond,
                .then_branch = try ComSeq.initial_value(),
                .else_branch = try ComSeq.initial_value(),
            },
        };
    }

    fn rewrite_as_while(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const cond = try cator.create(BExpr);
        cond.* = .hole;

        self.* = .{
            .while_loop = .{
                .cond = cond,
                .commands = try ComSeq.initial_value(),
            },
        };
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
        Offer{
            .name = "if",
            .rewriter = .{ .from_void = rewrite_as_if },
        },
        Offer{
            .name = "while",
            .rewriter = .{ .from_void = rewrite_as_while },
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
        break :blk Expr{ .e_assop = .{ .operator = .mul, .operands = args } };
    };

    const ep = try cator.create(Expr);
    ep.* = blk: {
        var args = try OpList.initCapacity(cator, 3);
        args.appendAssumeCapacity(Expr{ .e_const = 1 });
        args.appendAssumeCapacity(et);
        args.appendAssumeCapacity(Expr{ .e_const = 4 });
        break :blk Expr{ .e_assop = .{ .operator = .add, .operands = args } };
    };

    const i = try cator.create(Id);
    i.* = .{ .id = "foo" };

    const ibar = try cator.create(Id);
    ibar.* = .{ .id = "bar" };

    const ebar = try cator.create(Expr);
    ebar.* = Expr{ .e_const = 10 };

    const seq = blk: {
        var coms = try std.ArrayList(Com).initCapacity(cator, 2);
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = i, .a = ep } });
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = ibar, .a = ebar } });

        break :blk ComSeq{ .coms = coms };
    };

    const ibaz = try cator.create(Id);
    ibaz.* = .{ .id = "baz" };

    const ebaz = try cator.create(Expr);
    ebaz.* = Expr{ .e_const = 200 };

    const seq2 = blk: {
        var coms = try std.ArrayList(Com).initCapacity(cator, 1);
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = ibaz, .a = ebaz } });

        break :blk ComSeq{ .coms = coms };
    };

    const cond = try cator.create(BExpr);
    cond.* = BExpr{ .@"const" = true };

    const if_stmt = try cator.create(Com);
    if_stmt.* = Com{ .conditional = .{
        .cond = cond,
        .then_branch = seq,
        .else_branch = seq2,
    } };

    return if_stmt.to_tree();
}

const ComSeq = struct {
    coms: std.ArrayList(Com),

    const Self = @This();

    fn drop(self: *Self) void {
        for (self.coms.items) |*com| {
            com.drop();
        }

        self.coms.deinit(cator);
    }

    pub fn render(self: *const Self, sink: *Sink) !void {
        sink.start_node(self);

        if (0 < self.coms.items.len) {
            var i: usize = 0;
            while (true) {
                try self.coms.items[i].render(sink);
                i += 1;
                if (i == self.coms.items.len) {
                    break;
                }

                try sink.break_line();
            }
        }

        sink.end_node(self);
    }

    pub fn initial_value() !Self {
        var coms = try std.ArrayList(Com).initCapacity(cator, 1);
        coms.appendAssumeCapacity(.hole);

        return Self{ .coms = coms };
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.coms.items.len;
    }

    fn get_nth_child(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return if (n < self.coms.items.len) self.coms.items[n].to_tree() else null;
    }

    fn insert_at(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (i <= self.coms.items.len) {
            self.coms.insert(cator, i, Com.hole) catch unreachable;
            return true;
        }

        return false;
    }

    fn remove_at(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (i < self.coms.items.len) {
            if (self.coms.items.len == 1) {
                return .not_possible;
            }

            var x = self.coms.orderedRemove(i);
            x.drop();

            const new_index = if (i == self.coms.items.len) i - 1 else i;
            return .{ .done = .{ .new_index = new_index } };
        }

        @panic("Invalid remove_at call");
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // TODO Maybe demote that method, it seems really inappropriate for
        // ComSeq.
        _ = self;
    }

    fn raw_render(ptr: *anyopaque, sink: *Sink) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.render(sink);
    }

    const replacement_offers = &[_]Offer{};

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

const BExpr = union(enum) {
    @"const": bool,
    comparison: struct { left: *Expr, op: ComparisonOperator, right: *Expr },
    not: *BExpr,
    operation: assoc.Operation(OperandType, OperatorType),
    hole,

    pub const OperatorType = enum {
        @"or",
        @"and",

        pub fn is_not_greater_than(a: @This(), b: @This()) bool {
            return @intFromEnum(a) <= @intFromEnum(b);
        }

        pub fn render(self: @This(), sink: *Sink) !void {
            try sink.append_ascii(switch (self) {
                .@"or" => "or",
                .@"and" => "and",
            });
        }
    };

    const OperandType = Self;

    const ComparisonOperator = enum {
        is_less_than,
        equals,
    };

    const Self = @This();

    pub fn drop(self: *Self) void {
        switch (self.*) {
            .@"const" => {},
            .comparison => |x| {
                x.left.drop();
                cator.destroy(x.left);

                x.right.drop();
                cator.destroy(x.right);
            },
            .not => |b0| {
                b0.drop();
                cator.destroy(b0);
            },
            .operation => |*op| {
                op.drop();
            },
            .hole => {},
        }
    }

    pub fn render(self: *const Self, sink: *Sink, parent_op: ?OperatorType) !void {
        sink.start_node(self);

        switch (self.*) {
            .@"const" => |b0| try sink.append_ascii(switch (b0) {
                true => "true",
                false => "false",
            }),
            .comparison => |x| {
                try x.left.render(sink, null);

                try sink.append_ascii(" ");
                try sink.append_ascii(switch (x.op) {
                    .is_less_than => "<",
                    .equals => "=",
                });
                try sink.append_ascii(" ");

                try x.right.render(sink, null);
            },
            .not => |be0| {
                try sink.append_ascii("not ");
                // The value for `parent_op` is a hack that should make parentheses
                // work correctly. TODO clean up.
                try be0.render(sink, .@"and");
            },
            .operation => |op| {
                try op.render(sink, parent_op);
            },
            .hole => {
                try sink.append("◆", 1);
            },
        }

        sink.end_node(self);
    }

    fn child_count(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .@"const" => 0,
            .comparison => 2,
            .not => 1,
            .operation => |op| op.operands.items.len,
            .hole => 0,
        };
    }

    fn get_nth_child(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .@"const" => null,
            .comparison => |x| switch (n) {
                0 => x.left.to_tree(),
                1 => x.right.to_tree(),
                else => null,
            },
            .not => |b0| switch (n) {
                0 => b0.to_tree(),
                else => null,
            },
            .operation => |op| if (op.get_nth_child(n)) |x| x.to_tree() else null,
            .hole => null,
        };
    }

    fn insert_at(ptr: *anyopaque, i: usize) bool {
        _ = ptr;
        _ = i;
        return false;
    }

    fn remove_at(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        _ = ptr;
        _ = i;
        return .not_possible;
    }

    fn make_into_hole(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.drop();
        self.* = .hole;
    }

    fn rewrite_as_false(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = .{ .@"const" = false };
    }

    fn rewrite_as_true(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = .{ .@"const" = true };
    }

    fn rewrite_as_not(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const b0 = try cator.create(BExpr);
        b0.* = .hole;

        self.* = .{ .not = b0 };
    }

    fn rewrite_as_lt(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const l = try cator.create(Expr);
        l.* = .e_hole;

        const r = try cator.create(Expr);
        r.* = .e_hole;

        self.* = .{ .comparison = .{ .left = l, .op = .is_less_than, .right = r } };
    }

    fn rewrite_as_eq(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const l = try cator.create(Expr);
        l.* = .e_hole;

        const r = try cator.create(Expr);
        r.* = .e_hole;

        self.* = .{ .comparison = .{ .left = l, .op = .equals, .right = r } };
    }

    fn rewrite_as_and(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = .{
            .operation = try assoc.Operation(OperandType, OperatorType).make_initial_value(.@"and", .hole),
        };
    }

    fn rewrite_as_or(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = .{
            .operation = try assoc.Operation(OperandType, OperatorType).make_initial_value(.@"or", .hole),
        };
    }

    const replacement_offers = &[_]Offer{
        .{
            .name = "false",
            .rewriter = .{ .from_void = rewrite_as_false },
        },
        .{
            .name = "true",
            .rewriter = .{ .from_void = rewrite_as_true },
        },
        .{
            .name = "less than",
            .rewriter = .{ .from_void = rewrite_as_lt },
        },
        .{
            .name = "equals",
            .rewriter = .{ .from_void = rewrite_as_eq },
        },
        .{
            .name = "not",
            .rewriter = .{ .from_void = rewrite_as_not },
        },
        .{
            .name = "and",
            .rewriter = .{ .from_void = rewrite_as_and },
        },
        .{
            .name = "or",
            .rewriter = .{ .from_void = rewrite_as_or },
        },
    };

    const vt = VTable{
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
