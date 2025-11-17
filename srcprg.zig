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
};

const Com = union(enum) {
    skip,
    asgn: struct { x: *Id, a: *Expr },
    hole,

    pub fn free_children(c: *Com) void {
        switch (c.*) {
            .asgn => |p| p.a.free_children(),
            else => {},
        }
    }

    pub fn render(
        c: *const Com,
        cursor: usize,
        buf: *Buffer,
        start: *c_int,
        end: *c_int,
    ) !void {
        if (@intFromPtr(c) == cursor) {
            start.* = @intCast(buf.items.len);
        }

        switch (c.*) {
            .skip => {
                try buf.appendSlice(cator, "skip");
            },
            .asgn => |asgn| {
                try asgn.x.render(cursor, buf, start, end);
                try buf.appendSlice(cator, " := ");
                try render_expr(asgn.a, cursor, AssOp.add, buf, start, end);
            },
            .hole => {
                try buf.appendSlice(cator, "◆");
            },
        }

        if (@intFromPtr(c) == cursor) {
            end.* = @intCast(buf.items.len);
        }
    }

    pub fn overwrite(p: *Com, c: Com) void {
        p.free_children();
        p.* = c;
    }
};

const ComSeq = std.ArrayList(Com);

fn create_example_tree() !struct { root: *Com, cursor: *ThreadCursor } {
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

    const p = try cator.create(ThreadCursor);
    p.* = ThreadCursor.init(c);

    p.start();

    p.perform(.go_down);
    p.perform(.go_right);

    p.perform(.go_down);
    p.perform(.go_right);

    return .{ .root = c, .cursor = p };
}

fn render_expr(
    e: *const Expr,
    cursor: usize,
    parent_op: AssOp,
    buf: *Buffer,
    start: *c_int,
    end: *c_int,
) !void {
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
                try render_expr(&op.args.items[0], cursor, op.o, buf, start, end);

                for (op.args.items[1..]) |*arg| {
                    try buf.append(cator, ' ');
                    try buf.append(cator, switch (op.o) {
                        .add => '+',
                        .mul => '*',
                    });
                    try buf.append(cator, ' ');
                    try render_expr(arg, cursor, op.o, buf, start, end);
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
    tree: *Com,
    cursor: *ThreadCursor,
    buf: Buffer,
};

export fn create_srcprg() ?*anyopaque {
    const x = create_example_tree() catch return null;

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
    try srcprg.tree.render(
        srcprg.cursor.cursor_pos.to_int(),
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
    p.free_children();
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

    switch (srcprg.cursor.cursor_pos) {
        .expr => |e| {
            overwrite_expr(e, .{ .e_const = @intCast(num) });
        },
        else => {},
    }

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_addition(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    switch (srcprg.cursor.cursor_pos) {
        .expr => |e| {
            overwrite_expr(e, new_op(.add) catch std.process.exit(1));
        },
        else => {},
    }

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_multiplication(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    switch (srcprg.cursor.cursor_pos) {
        .expr => |e| {
            overwrite_expr(e, new_op(.mul) catch std.process.exit(1));
        },
        else => {},
    }

    return render(srcprg) catch std.process.exit(1);
}

const ThreadCursor = struct {
    const th = std.Thread;

    mutex: th.Mutex,
    cond: th.Condition,
    pending_instruction: ?instruction,
    root: *Com,
    cursor_pos: NodePtr,

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

    fn report_completion(self: *Self, cursor_pos: NodePtr) void {
        self.pending_instruction = null;
        self.cursor_pos = cursor_pos;
        self.cond.signal();
        self.mutex.unlock();
    }

    pub fn init(root: *Com) Self {
        return Self{
            .mutex = .{},
            .cond = .{},
            .pending_instruction = null,
            .root = root,
            .cursor_pos = .{ .com = root },
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
            _ = self.traverse_dynamically(.{ .com = self.root }, .none) catch std.process.exit(1);
            self.report_completion(.{ .com = self.root });
        }
    }

    fn traverse_dynamically(
        self: *Self,
        node_on_entry: NodePtr,
        down_instr: down_instruction,
    ) !up_instruction {
        switch (down_instr) {
            .none => {},
            .go_down => {
                self.report_completion(node_on_entry);
            },
        }

        var node = node_on_entry;

        while (true) {
            const instr = self.receive();

            switch (instr) {
                .go_right => return .go_right,
                .go_up => return .do_nothing,
                .go_left => return .go_left,
                .go_down => {
                    if (0 < node.child_count()) {
                        var i: usize = 0;

                        while (true) {
                            const up_instr = try self.traverse_dynamically(
                                node.get_nth_child(i) orelse std.process.exit(1),
                                .go_down,
                            );

                            switch (up_instr) {
                                .go_left => {
                                    if (0 < i) {
                                        i -= 1;
                                    }
                                },
                                .go_right => {
                                    if (i + 1 < node.child_count()) {
                                        i += 1;
                                    }
                                },
                                .do_nothing => {
                                    break;
                                },
                                .insert_before => {
                                    _ = node.insert_at(i);
                                },
                                .insert_after => {
                                    if (node.insert_at(i + 1)) {
                                        i += 1;
                                    }
                                },
                                .remove_cursor_node => {
                                    switch (node.remove(i)) {
                                        .was_replaced => break,
                                        .now_empty => break,
                                        .new_index => |j| i = j,
                                    }
                                },
                            }
                        }
                    }
                },
                .insert_before => return .insert_before,
                .insert_after => return .insert_after,
                .make_into_hole => {
                    node.make_into_hole();
                },
                .remove_cursor_node => return .remove_cursor_node,
            }

            self.report_completion(node);
        }
    }
};

const Id = union(enum) {
    id: []const u8,
    hole,

    pub fn render(
        i: *const Id,
        cursor: usize,
        buf: *Buffer,
        start: *c_int,
        end: *c_int,
    ) !void {
        if (@intFromPtr(i) == cursor) {
            start.* = @intCast(buf.items.len);
        }

        switch (i.*) {
            .id => |s| {
                try buf.appendSlice(cator, s);
            },
            .hole => {
                try buf.appendSlice(cator, "◆");
            },
        }

        if (@intFromPtr(i) == cursor) {
            end.* = @intCast(buf.items.len);
        }
    }
};

const NodePtr = union(enum) {
    expr: *Expr,
    com: *Com,
    com_seq: *ComSeq,
    id: *Id,

    const Self = @This();

    pub fn child_count(self: Self) usize {
        return switch (self) {
            .expr => |e| switch (e.*) {
                .e_assop => |p| p.args.items.len,
                else => 0,
            },
            .com => |c| switch (c.*) {
                .asgn => 2,
                else => 0,
            },
            .com_seq => |s| s.items.len,
            .id => 0,
        };
    }

    pub fn get_nth_child(self: Self, n: usize) ?Self {
        return switch (self) {
            .expr => |e| switch (e.*) {
                .e_assop => |p| if (n < p.args.items.len) .{ .expr = &p.args.items[n] } else null,
                else => null,
            },
            .com => |c| switch (c.*) {
                .asgn => |*p| switch (n) {
                    0 => .{ .id = p.x },
                    1 => .{ .expr = p.a },
                    else => null,
                },
                else => null,
            },
            .com_seq => |s| if (n < s.items.len) .{ .com = &s.items[n] } else null,
            .id => null,
        };
    }

    pub fn to_int(self: Self) usize {
        return switch (self) {
            .expr => |p| @intFromPtr(p),
            .com => |p| @intFromPtr(p),
            .com_seq => |s| @intFromPtr(s),
            .id => |i| @intFromPtr(i),
        };
    }

    // When the operation is not possible because of the structure of the AST,
    // does nothing and returns false.
    pub fn insert_at(self: Self, i: usize) bool {
        switch (self) {
            .expr => |e| switch (e.*) {
                .e_assop => |*p| {
                    if (i <= p.args.items.len) {
                        p.args.insert(cator, i, .e_hole) catch std.process.exit(1);
                        return true;
                    } else {
                        return false;
                    }
                },
                else => return false,
            },
            .com => return false,
            .com_seq => |s| {
                if (i <= s.items.len) {
                    s.insert(cator, i, .hole) catch std.process.exit(1);
                }
                return true;
            },
            .id => return false,
        }
    }

    pub const RemoveRet = union(enum) {
        was_replaced,
        now_empty,
        new_index: usize,
    };

    pub fn remove(self: Self, i: usize) RemoveRet {
        switch (self) {
            .expr => |e| switch (e.*) {
                .e_assop => |*p| {
                    var x = p.args.orderedRemove(i);
                    x.free_children();

                    if (p.args.items.len == 1) {
                        var v = p.args;
                        const c = v.items[0];
                        v.clearAndFree(cator);
                        e.* = c;
                        return .was_replaced;
                    } else if (p.args.items.len <= i) {
                        return .{ .new_index = i - 1 };
                    } else {
                        return .{ .new_index = i };
                    }
                },
                else => return .{ .new_index = i },
            },
            .com => return .{ .new_index = i },
            .com_seq => |s| {
                var x = s.orderedRemove(i);
                x.free_children();

                return if (s.items.len == 0) .now_empty else .{ .new_index = if (s.items.len <= i) i - 1 else i };
            },
            .id => return .{ .new_index = i },
        }
    }

    pub fn make_into_hole(self: Self) void {
        switch (self) {
            .expr => |e| overwrite_expr(e, .e_hole),
            .com => |c| c.overwrite(.hole),
            .com_seq => {},
            .id => |i| i.* = .hole,
        }
    }
};
