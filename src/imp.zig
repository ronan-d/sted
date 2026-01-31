const std = @import("std");

const Tree = @import("Tree.zig");
const VTable = Tree.VTable;
const Offer = Tree.Offer;

const Sink = @import("render.zig").Sink;

const assoc = @import("assoc.zig");

const AExp = union(enum) {
    // "lit" stands for "integer *lit*eral".
    lit: u64,
    assop: assoc.Operation(OperandType, OperatorType),
    hole,

    pub const OperatorType = enum {
        add,
        mul,

        pub fn isNotGreaterThan(a: @This(), b: @This()) bool {
            return @intFromEnum(a) <= @intFromEnum(b);
        }

        pub fn render(self: @This(), sink: *Sink) !void {
            try sink.appendAscii(switch (self) {
                .add => "+",
                .mul => "*",
            });
        }
    };

    const OperandType = Self;

    const Self = @This();

    pub fn drop(node: *Self) void {
        switch (node.*) {
            .lit => {},
            .assop => |*op| {
                op.drop();
            },
            .hole => {},
        }
    }

    pub fn render(
        self: *const Self,
        sink: *Sink,
        parent_op: ?OperatorType,
    ) !void {
        sink.startNode(self);

        switch (self.*) {
            .lit => |n| {
                const len_before = sink.buf.items.len;
                try sink.buf.print(cator, "{}", .{n});
                sink.code_point_counter += sink.buf.items.len - len_before;
            },
            .assop => |op| {
                try op.render(sink, parent_op);
            },
            .hole => {
                try sink.append("◆", 1);
            },
        }

        sink.endNode(self);
    }

    fn childCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .lit => 0,
            .assop => |op| op.operands.items.len,
            .hole => 0,
        };
    }

    fn childAt(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .lit => null,
            .assop => |op| if (op.childAt(n)) |x| x.to_tree() else null,
            .hole => null,
        };
    }

    fn insertAt(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .assop => |*p| {
                return p.insertAt(i, .hole) catch unreachable;
            },
            else => return false,
        };
    }

    fn removeAt(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .assop => |*p| {
                switch (p.removeAt(i)) {
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

    fn rewrite_as_const(ptr: *anyopaque, n: u64) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{ .lit = n };
    }

    fn rewrite_as_add(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{
            .assop = try assoc.Operation(OperandType, OperatorType).make_initial_value(.add, .hole),
        };
    }

    fn rewrite_as_mul(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        self.* = Self{
            .assop = try assoc.Operation(OperandType, OperatorType).make_initial_value(.add, .hole),
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
        .childCount = childCount,
        .childAt = childAt,
        .insertAt = insertAt,
        .removeAt = removeAt,
        .replacementOffers = replacement_offers,
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
        sink.startNode(self);

        switch (self.*) {
            .id => |s| {
                try sink.appendAscii(s);
            },
            .hole => {
                try sink.append("◆", 1);
            },
        }

        sink.endNode(self);
    }

    fn childCount(_: *anyopaque) usize {
        return 0;
    }

    fn childAt(_: *anyopaque, _: usize) ?Tree {
        return null;
    }

    fn insertAt(_: *anyopaque, _: usize) bool {
        return false;
    }

    fn removeAt(_: *anyopaque, _: usize) Tree.RemovalOutcome {
        return .not_possible;
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
        .childCount = childCount,
        .childAt = childAt,
        .insertAt = insertAt,
        .removeAt = removeAt,
        .replacementOffers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const Buffer = std.ArrayList(u8);

const Com = union(enum) {
    skip,
    asgn: struct { x: *Id, a: *AExp },
    conditional: struct { cond: *BExp, then_branch: ComSeq, else_branch: ComSeq },
    while_loop: struct { cond: *BExp, commands: ComSeq },
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
        sink.startNode(self);

        switch (self.*) {
            .skip => {
                try sink.appendAscii("skip");
            },
            .asgn => |asgn| {
                try asgn.x.render(sink);
                try sink.appendAscii(" := ");
                try asgn.a.render(sink, null);
            },
            .conditional => |*x| {
                try sink.appendAscii("if ");

                try x.cond.render(sink, null);

                try sink.appendAscii(" ");

                sink.startNode(&x.then_branch);

                try sink.appendAscii("then");

                sink.increaseIndentation();

                try sink.breakLine();

                try x.then_branch.render(sink);

                sink.decreaseIndentation();

                try sink.breakLine();

                sink.startNode(&x.else_branch);

                try sink.appendAscii("else");

                sink.increaseIndentation();

                try sink.breakLine();

                try x.else_branch.render(sink);

                sink.decreaseIndentation();
            },
            .while_loop => |*x| {
                try sink.appendAscii("while ");

                try x.cond.render(sink, null);

                try sink.appendAscii(" ");

                sink.startNode(&x.commands);

                try sink.appendAscii("do");

                sink.increaseIndentation();

                try sink.breakLine();

                try x.commands.render(sink);

                sink.decreaseIndentation();
            },
            .hole => {
                try sink.append("◆", 1);
            },
        }

        sink.endNode(self);
    }

    pub fn overwrite(p: *Com, c: Com) void {
        p.drop();
        p.* = c;
    }

    fn childCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .skip => 0,
            .asgn => 2,
            .conditional => 3,
            .while_loop => 2,
            .hole => 0,
        };
    }

    fn childAt(ptr: *anyopaque, n: usize) ?Tree {
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

    fn insertAt(_: *anyopaque, _: usize) bool {
        return false;
    }

    fn removeAt(_: *anyopaque, _: usize) Tree.RemovalOutcome {
        return .not_possible;
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
        const pa = try cator.create(AExp);

        px.* = .hole;
        pa.* = .hole;

        self.drop();
        self.* = .{ .asgn = .{ .x = px, .a = pa } };
    }

    fn rewrite_as_if(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const cond = try cator.create(BExp);
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

        const cond = try cator.create(BExp);
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
        .childCount = childCount,
        .childAt = childAt,
        .insertAt = insertAt,
        .removeAt = removeAt,
        .render = raw_render,
        .replacementOffers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const OpList = std.ArrayList(AExp);

const cator = std.heap.c_allocator;
const Allocator = std.mem.Allocator;

pub fn create_sample() Allocator.Error!Tree {
    const e3 = try cator.create(AExp);
    e3.* = AExp{ .lit = 3 };

    const et = blk: {
        var args = try OpList.initCapacity(cator, 2);
        args.appendAssumeCapacity(AExp{ .lit = 2 });
        args.appendAssumeCapacity(AExp{ .lit = 3 });
        break :blk AExp{ .assop = .{ .operator = .mul, .operands = args } };
    };

    const ep = try cator.create(AExp);
    ep.* = blk: {
        var args = try OpList.initCapacity(cator, 3);
        args.appendAssumeCapacity(AExp{ .lit = 1 });
        args.appendAssumeCapacity(et);
        args.appendAssumeCapacity(AExp{ .lit = 4 });
        break :blk AExp{ .assop = .{ .operator = .add, .operands = args } };
    };

    const i = try cator.create(Id);
    i.* = .{ .id = "foo" };

    const ibar = try cator.create(Id);
    ibar.* = .{ .id = "bar" };

    const ebar = try cator.create(AExp);
    ebar.* = AExp{ .lit = 10 };

    const seq = blk: {
        var coms = try std.ArrayList(Com).initCapacity(cator, 2);
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = i, .a = ep } });
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = ibar, .a = ebar } });

        break :blk ComSeq{ .coms = coms };
    };

    const ibaz = try cator.create(Id);
    ibaz.* = .{ .id = "baz" };

    const ebaz = try cator.create(AExp);
    ebaz.* = AExp{ .lit = 200 };

    const seq2 = blk: {
        var coms = try std.ArrayList(Com).initCapacity(cator, 1);
        coms.appendAssumeCapacity(.{ .asgn = .{ .x = ibaz, .a = ebaz } });

        break :blk ComSeq{ .coms = coms };
    };

    const cond = try cator.create(BExp);
    cond.* = BExp{ .@"const" = true };

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
        if (0 < self.coms.items.len) {
            var i: usize = 0;
            while (true) {
                try self.coms.items[i].render(sink);
                i += 1;
                if (i == self.coms.items.len) {
                    break;
                }

                try sink.breakLine();
            }
        }

        sink.endNode(self);
    }

    pub fn initial_value() !Self {
        var coms = try std.ArrayList(Com).initCapacity(cator, 1);
        coms.appendAssumeCapacity(.hole);

        return Self{ .coms = coms };
    }

    fn childCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.coms.items.len;
    }

    fn childAt(ptr: *anyopaque, n: usize) ?Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return if (n < self.coms.items.len) self.coms.items[n].to_tree() else null;
    }

    fn insertAt(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (i <= self.coms.items.len) {
            self.coms.insert(cator, i, Com.hole) catch unreachable;
            return true;
        }

        return false;
    }

    fn removeAt(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
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

        @panic("Invalid removeAt call");
    }

    fn raw_render(ptr: *anyopaque, sink: *Sink) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        sink.startNode(self);
        return self.render(sink);
    }

    const replacement_offers = &[_]Offer{};

    pub const vt = VTable{
        .childCount = childCount,
        .childAt = childAt,
        .insertAt = insertAt,
        .removeAt = removeAt,
        .render = raw_render,
        .replacementOffers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};

const BExp = union(enum) {
    @"const": bool,
    comparison: struct { left: *AExp, op: ComparisonOperator, right: *AExp },
    not: *BExp,
    operation: assoc.Operation(OperandType, OperatorType),
    hole,

    pub const OperatorType = enum {
        @"or",
        @"and",

        pub fn isNotGreaterThan(a: @This(), b: @This()) bool {
            return @intFromEnum(a) <= @intFromEnum(b);
        }

        pub fn render(self: @This(), sink: *Sink) !void {
            try sink.appendAscii(switch (self) {
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
        sink.startNode(self);

        switch (self.*) {
            .@"const" => |b0| try sink.appendAscii(switch (b0) {
                true => "true",
                false => "false",
            }),
            .comparison => |x| {
                try x.left.render(sink, null);

                try sink.appendAscii(" ");
                try sink.appendAscii(switch (x.op) {
                    .is_less_than => "<",
                    .equals => "=",
                });
                try sink.appendAscii(" ");

                try x.right.render(sink, null);
            },
            .not => |be0| {
                try sink.appendAscii("not ");
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

        sink.endNode(self);
    }

    fn childCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .@"const" => 0,
            .comparison => 2,
            .not => 1,
            .operation => |op| op.operands.items.len,
            .hole => 0,
        };
    }

    fn childAt(ptr: *anyopaque, n: usize) ?Tree {
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
            .operation => |op| if (op.childAt(n)) |x| x.to_tree() else null,
            .hole => null,
        };
    }

    fn insertAt(ptr: *anyopaque, i: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .@"const" => false,
            .comparison => false,
            .not => false,
            .operation => |*op| op.insertAt(i, .hole) catch unreachable,
            .hole => false,
        };
    }

    fn removeAt(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return switch (self.*) {
            .@"const" => .not_possible,
            .comparison => .not_possible,
            .not => .not_possible,
            .operation => |*p| blk: {
                switch (p.removeAt(i)) {
                    .normal => {
                        const new_index = if (p.operands.items.len == i) i - 1 else i;
                        break :blk .{ .done = .{ .new_index = new_index } };
                    },
                    .replaced => |x| {
                        self.* = x;
                        break :blk .replaced;
                    },
                }
            },
            .hole => .not_possible,
        };
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

        const b0 = try cator.create(BExp);
        b0.* = .hole;

        self.* = .{ .not = b0 };
    }

    fn rewrite_as_lt(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const l = try cator.create(AExp);
        l.* = .hole;

        const r = try cator.create(AExp);
        r.* = .hole;

        self.* = .{ .comparison = .{ .left = l, .op = .is_less_than, .right = r } };
    }

    fn rewrite_as_eq(ptr: *anyopaque) Allocator.Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.drop();

        const l = try cator.create(AExp);
        l.* = .hole;

        const r = try cator.create(AExp);
        r.* = .hole;

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
        .childCount = childCount,
        .childAt = childAt,
        .insertAt = insertAt,
        .removeAt = removeAt,
        .replacementOffers = replacement_offers,
    };

    pub fn to_tree(self: *Self) Tree {
        return .{ .ptr = self, .vtable = &vt };
    }
};
