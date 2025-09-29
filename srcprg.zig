const std = @import("std");

const cator = std.heap.c_allocator;

const c_interface = @cImport({
    @cInclude("structs.h");
});

// Associative operation. We store a list of operands, and not a binary tree.
const AssOp = enum {
    add,
    mul,

    fn le(a: @This(), b: @This()) bool {
        return @intFromEnum(a) <= @intFromEnum(b);
    }
};

const OpList = std.ArrayList(Expr);

const Expr = union(enum) {
    e_const: u64,
    e_assop: struct { o: AssOp, args: OpList },
    e_hole,
};

fn create_example_expr() !struct { root: *Expr, stack: CursorStack } {
    const e3 = try cator.create(Expr);
    e3.* = Expr{ .e_const = 3 };

    const et = blk: {
        var args = try OpList.initCapacity(cator, 2);
        args.appendAssumeCapacity(Expr{ .e_const = 2 });
        args.appendAssumeCapacity(Expr{ .e_const = 3 });
        break :blk Expr{ .e_assop = .{ .o = AssOp.mul, .args = args } };
    };

    const ep = try cator.create(Expr);
    const selected_op, ep.* = blk: {
        var args = try OpList.initCapacity(cator, 3);
        args.appendAssumeCapacity(Expr{ .e_const = 1 });
        args.appendAssumeCapacity(et);
        args.appendAssumeCapacity(Expr{ .e_const = 4 });
        break :blk .{ &args.items[1], Expr{ .e_assop = .{ .o = .add, .args = args } } };
    };

    var stack: CursorStack = .{};
    try stack.append(cator, selected_op);

    return .{ .root = ep, .stack = stack };
}

fn render_node(e: *const Expr, cursor: *Expr, parent_op: AssOp, buf: *Buffer, start: *c_int, end: *c_int) !void {
    if (e == cursor) {
        start.* = @intCast(buf.items.len);
    }

    switch (e.*) {
        .e_const => |n| try buf.print(cator, "{}", .{n}),
        .e_assop => |op| {
            const needs_paren = op.o.le(parent_op);

            if (needs_paren) {
                try buf.append(cator, '(');
            }

            if (op.args.items.len > 0) {
                try render_node(&op.args.items[0], cursor, op.o, buf, start, end);

                for (op.args.items[1..]) |*arg| {
                    try buf.append(cator, ' ');
                    try buf.append(cator, switch (op.o) {
                        .add => '+',
                        .mul => '*',
                    });
                    try buf.append(cator, ' ');
                    try render_node(arg, cursor, op.o, buf, start, end);
                }
            }

            if (needs_paren) {
                try buf.append(cator, ')');
            }
        },
        .e_hole => {
            try buf.appendSlice(cator, "◆");
        },
    }

    if (e == cursor) {
        end.* = @intCast(buf.items.len);
    }
}

const Buffer = std.ArrayList(u8);

const CursorStack = std.ArrayList(*Expr);

const Srcprg = struct {
    tree: *Expr,
    cursor_stack: CursorStack,
    buf: Buffer,

    fn cursor(self: @This()) *Expr {
        if (self.cursor_stack.getLastOrNull()) |e| {
            return e;
        } else {
            return self.tree;
        }
    }

    fn go_left_or_right(self: *@This(), dir: c_interface.instruction) !void {
        const ls = struct {
            fn edit(args: *OpList, idx: usize) std.mem.Allocator.Error!usize {
                _ = args;
                return if (idx == 0) 0 else idx - 1;
            }
        };
        const rs = struct {
            fn edit(args: *OpList, idx: usize) std.mem.Allocator.Error!usize {
                return if (idx + 1 < args.items.len) idx + 1 else idx;
            }
        };

        try self.list_edit(if (dir == c_interface.go_left) ls.edit else rs.edit);
    }

    fn insert_before_or_after(self: *@This(), instr: c_interface.instruction) !void {
        const ls = struct {
            fn edit(args: *OpList, idx: usize) std.mem.Allocator.Error!usize {
                const i = idx;

                try args.insert(cator, i, Expr.e_hole);

                return i;
            }
        };
        const rs = struct {
            fn edit(args: *OpList, idx: usize) std.mem.Allocator.Error!usize {
                const i = idx + 1;

                try args.insert(cator, i, Expr.e_hole);

                return i;
            }
        };

        try self.list_edit(if (instr == c_interface.insert_before) ls.edit else rs.edit);
    }

    fn replace_cursor_with_number(self: *@This(), num: u64) void {
        overwrite_expr(self.cursor(), Expr{ .e_const = num });
    }

    fn replace_cursor_with_op(self: @This(), op: AssOp) !void {
        var args = try OpList.initCapacity(cator, 2);
        args.appendAssumeCapacity(Expr.e_hole);
        args.appendAssumeCapacity(Expr.e_hole);
        overwrite_expr(self.cursor(), Expr{ .e_assop = .{ .o = op, .args = args } });
    }

    fn list_edit(self: *@This(), f: *const fn (*OpList, usize) std.mem.Allocator.Error!usize) !void {
        if (self.cursor_stack.pop()) |c| {
            const p = self.cursor();

            switch (p.*) {
                .e_assop => |*assop| {
                    const idx = c - assop.args.items.ptr;

                    const i = try f(&assop.args, idx);

                    self.cursor_stack.appendAssumeCapacity(&assop.args.items[i]);
                },
                else => unreachable,
            }
        }
    }

    fn remove_cursor_node(self: *@This()) !void {
        const t = struct {
            fn edit(args: *OpList, idx: usize) std.mem.Allocator.Error!usize {
                var x = args.orderedRemove(idx);
                free_children(&x);
                return if (idx < args.items.len) idx else idx - 1;
            }
        };

        try self.list_edit(t.edit);

        // If we have an operation with just one operand, we replace it with the
        // operand itself.

        if (self.cursor_stack.pop()) |c| {
            const p = self.cursor();

            switch (p.*) {
                .e_assop => |*assop| {
                    if (assop.args.items.len == 1) {
                        overwrite_expr(p, c.*);
                        return;
                    }
                },
                else => {},
            }

            self.cursor_stack.appendAssumeCapacity(c);
        }
    }
};

export fn create_srcprg() ?*anyopaque {
    const x = create_example_expr() catch return null;

    const s = cator.create(Srcprg) catch return null;
    s.tree = x.root;
    s.cursor_stack = x.stack;
    s.buf = .{};

    return @ptrCast(s);
}

fn render(srcprg: *Srcprg) !c_interface.frame {
    srcprg.buf.clearRetainingCapacity();

    var start: c_int = undefined;
    var end: c_int = undefined;
    try render_node(srcprg.tree, srcprg.cursor(), AssOp.add, &srcprg.buf, &start, &end);

    const len: c_int = @intCast(srcprg.buf.items.len);

    try srcprg.buf.append(cator, 0);

    return c_interface.frame{
        .text = srcprg.buf.items.ptr,
        .len = len,
        .start_offset = start,
        .end_offset = end,
    };
}

fn overwrite_expr(p: *Expr, v: Expr) void {
    switch (p.*) {
        .e_const, .e_hole => {},
        .e_assop => |*op| {
            op.args.clearAndFree(cator);
        },
    }

    p.* = v;
}

export fn execute(srcprg_opaque: *anyopaque, instr: c_interface.instruction) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    if (instr == c_interface.go_up) {
        _ = srcprg.cursor_stack.pop();
    } else if (instr == c_interface.go_left or instr == c_interface.go_right) {
        srcprg.go_left_or_right(instr) catch std.process.exit(1);
    } else if (instr == c_interface.go_down) {
        switch (srcprg.cursor().*) {
            .e_assop => |op| {
                std.debug.assert(op.args.items.len != 0);
                srcprg.cursor_stack.append(cator, &op.args.items[0]) catch std.process.exit(1);
            },
            else => {},
        }
    } else if (instr == c_interface.make_into_hole) {
        const top = srcprg.cursor();
        overwrite_expr(top, .e_hole);
    } else if (instr == c_interface.insert_before or instr == c_interface.insert_after) {
        srcprg.insert_before_or_after(instr) catch std.process.exit(1);
    } else if (instr == c_interface.remove_cursor_node) {
        srcprg.remove_cursor_node() catch std.process.exit(1);
    }
    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_number(srcprg_opaque: *anyopaque, num: c_uint) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    srcprg.replace_cursor_with_number(@intCast(num));

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_addition(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    srcprg.replace_cursor_with_op(.add) catch std.process.exit(1);

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_multiplication(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    srcprg.replace_cursor_with_op(.mul) catch std.process.exit(1);

    return render(srcprg) catch std.process.exit(1);
}

fn free_children(node: *Expr) void {
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
