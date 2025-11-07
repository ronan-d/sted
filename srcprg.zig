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

fn create_example_expr() !struct { root: *Expr, cursor: *ThreadCursor } {
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

    const p = try cator.create(ThreadCursor);
    p.* = ThreadCursor.init(ep);

    p.start();

    p.perform(.go_down);
    p.perform(.go_right);

    return .{ .root = ep, .cursor = p };
}

fn render_node(e: *const Expr, cursor: usize, parent_op: AssOp, buf: *Buffer, start: *c_int, end: *c_int) !void {
    if (@intFromPtr(e) == cursor) {
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

    if (@intFromPtr(e) == cursor) {
        end.* = @intCast(buf.items.len);
    }
}

fn new_op(op: AssOp) !Expr {
    var args = try OpList.initCapacity(cator, 2);
    args.appendAssumeCapacity(Expr.e_hole);
    args.appendAssumeCapacity(Expr.e_hole);
    return Expr{ .e_assop = .{ .o = op, .args = args } };
}

const Buffer = std.ArrayList(u8);

const Srcprg = struct {
    tree: *Expr,
    cursor: *ThreadCursor,
    buf: Buffer,

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
};

export fn create_srcprg() ?*anyopaque {
    const x = create_example_expr() catch return null;

    const s = cator.create(Srcprg) catch return null;
    s.tree = x.root;
    s.cursor = x.cursor;
    s.buf = .{};

    return @ptrCast(s);
}

fn render(srcprg: *Srcprg) !c_interface.frame {
    srcprg.buf.clearRetainingCapacity();

    var start: c_int = undefined;
    var end: c_int = undefined;
    try render_node(
        srcprg.tree,
        srcprg.cursor.cursor_pos,
        AssOp.add,
        &srcprg.buf,
        &start,
        &end,
    );

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
    free_children(p);
    p.* = v;
}

export fn execute(srcprg_opaque: *anyopaque, instr: c_interface.instruction) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    if (instr == c_interface.go_up) {
        srcprg.cursor.perform(.go_up);
    } else if (instr == c_interface.go_left) {
        srcprg.cursor.perform(.go_left);
    } else if (instr == c_interface.go_right) {
        srcprg.cursor.perform(.go_right);
    } else if (instr == c_interface.go_down) {
        srcprg.cursor.perform(.go_down);
    } else if (instr == c_interface.make_into_hole) {
        srcprg.cursor.perform(.make_into_hole);
    } else if (instr == c_interface.insert_before) {
        srcprg.cursor.perform(.insert_before);
    } else if (instr == c_interface.insert_after) {
        srcprg.cursor.perform(.insert_after);
    } else if (instr == c_interface.remove_cursor_node) {
        srcprg.cursor.perform(.remove_cursor_node);
    }

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_number(srcprg_opaque: *anyopaque, num: c_uint) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    const new_expr = cator.create(Expr) catch std.process.exit(1);
    new_expr.* = .{ .e_const = @intCast(num) };

    srcprg.cursor.perform(.{ .replace_with = .{ .e_const = @intCast(num) } });

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_addition(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    srcprg.cursor.perform(.{ .replace_with = new_op(.add) catch std.process.exit(1) });

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_multiplication(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    srcprg.cursor.perform(.{ .replace_with = new_op(.mul) catch std.process.exit(1) });

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

const ThreadCursor = struct {
    const th = std.Thread;

    mutex: th.Mutex,
    cond: th.Condition,
    pending_instruction: ?instruction,
    root: *Expr,
    cursor_pos: usize,

    const Self = @This();

    pub const instruction = union(enum) {
        go_right,
        go_up,
        go_left,
        go_down,
        insert_before,
        insert_after,
        make_into_hole,
        remove_cursor_node,
        replace_with: Expr,
    };

    pub fn perform(self: *Self, instr: instruction) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pending_instruction = instr;
        self.cond.signal();

        while (true) {
            self.cond.wait(&self.mutex);

            if (self.pending_instruction == null) {
                break;
            }
        }
    }

    fn receive(self: *Self) instruction {
        self.mutex.lock();
        // We won't unlock the mutex before returning since it's all synchronous.

        while (true) {
            if (self.pending_instruction) |instr| {
                return instr;
            } else {
                self.cond.wait(&self.mutex);
            }
        }
    }

    fn report_completion(self: *Self, cursor_pos: usize) void {
        self.pending_instruction = null;
        self.cursor_pos = cursor_pos;
        self.cond.signal();
        self.mutex.unlock();
    }

    pub fn init(root: *Expr) Self {
        return Self{
            .mutex = .{},
            .cond = .{},
            .pending_instruction = null,
            .root = root,
            .cursor_pos = @intFromPtr(root),
        };
    }

    // The different instructions that a call to traverse_dynamically might have
    // to return to its parent call.
    const up_instruction = enum {
        // For the "go up" command.
        do_nothing,
        go_left,
        go_right,
        insert_before,
        insert_after,
        remove_cursor_node,
    };

    const down_instruction = enum {
        none,
        go_down,
    };

    pub fn start(self: *Self) void {
        _ = th.spawn(.{}, thread_main, .{self}) catch std.process.exit(1);
    }

    fn thread_main(self: *Self) void {
        while (true) {
            _ = self.traverse_dynamically(self.root, .none) catch std.process.exit(1);
            self.report_completion(@intFromPtr(self.root));
        }
    }

    fn traverse_dynamically(
        self: *Self,
        node: *Expr,
        down_instr: down_instruction,
    ) !up_instruction {
        switch (down_instr) {
            .none => {},
            .go_down => {
                self.report_completion(@intFromPtr(node));
            },
        }

        while (true) {
            const instr = self.receive();

            switch (instr) {
                .go_right => return .go_right,
                .go_up => return .do_nothing,
                .go_left => return .go_left,
                .go_down => {
                    switch (node.*) {
                        .e_assop => |*op| {
                            std.debug.assert(op.args.items.len != 0);

                            var i: usize = 0;

                            while (true) {
                                const up_instr = try self.traverse_dynamically(&op.args.items[i], .go_down);

                                switch (up_instr) {
                                    .go_left => {
                                        if (0 < i) {
                                            i -= 1;
                                        }
                                    },
                                    .go_right => {
                                        if (i + 1 < op.args.items.len) {
                                            i += 1;
                                        }
                                    },
                                    .do_nothing => {
                                        break;
                                    },
                                    .insert_before => {
                                        try op.args.insert(cator, i, .e_hole);
                                    },
                                    .insert_after => {
                                        i += 1;
                                        try op.args.insert(cator, i, .e_hole);
                                    },
                                    .remove_cursor_node => {
                                        var x = op.args.orderedRemove(i);
                                        free_children(&x);

                                        if (op.args.items.len <= i) {
                                            i -= 1;
                                        }

                                        if (op.args.items.len == 1) {
                                            var v = op.args;
                                            node.* = v.items[0];
                                            v.clearAndFree(cator);
                                            break;
                                        }
                                    },
                                }
                            }
                        },
                        else => {},
                    }
                },
                .insert_before => return .insert_before,
                .insert_after => return .insert_after,
                .make_into_hole => {
                    overwrite_expr(node, .e_hole);
                },
                .remove_cursor_node => return .remove_cursor_node,
                .replace_with => |new_node| {
                    overwrite_expr(node, new_node);
                },
            }

            self.report_completion(@intFromPtr(node));
        }
    }
};
