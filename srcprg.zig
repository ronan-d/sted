const std = @import("std");

const cator = std.heap.c_allocator;

const c_interface = @cImport({
    @cInclude("structs.h");
});

const imp = @import("imp.zig");

const Tree = @import("Tree.zig");

const Sink = @import("render.zig").Sink;

const Srcprg = struct {
    tree: Tree,
    cursor: *ThreadCursor,
    sink: Sink,
};

export fn create_srcprg() ?*anyopaque {
    const x = imp.create_sample() catch return null;

    const s = cator.create(Srcprg) catch return null;
    s.tree = x;
    s.cursor = blk: {
        const p = cator.create(ThreadCursor) catch std.process.exit(1);
        p.* = ThreadCursor.init(x);

        p.start();

        p.perform(.go_down);
        p.perform(.go_right);
        p.perform(.go_down);
        p.perform(.go_right);

        break :blk p;
    };

    s.sink = Sink{
        .buf = .{},
        .cursor_start = undefined,
        .cursor_end = undefined,
        .cursor = x.ptr,
    };

    return @ptrCast(s);
}

fn render(srcprg: *Srcprg) !c_interface.frame {
    srcprg.sink.buf.clearRetainingCapacity();

    srcprg.sink.cursor = srcprg.cursor.cursor_pos.ptr;
    try srcprg.tree.render(&srcprg.sink);

    const len: c_int = @intCast(srcprg.sink.buf.items.len);

    try srcprg.sink.buf.append(cator, 0);

    return c_interface.frame{
        .text = srcprg.sink.buf.items.ptr,
        .len = len,
        .start_offset = @intCast(srcprg.sink.cursor_start),
        .end_offset = @intCast(srcprg.sink.cursor_end),
    };
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

    _ = num;
    // switch (srcprg.cursor.cursor_pos) {
    //     .expr => |e| {
    //         overwrite_expr(e, .{ .e_const = @intCast(num) });
    //     },
    //     else => {},
    // }

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_addition(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    // switch (srcprg.cursor.cursor_pos) {
    //     .expr => |e| {
    //         overwrite_expr(e, new_op(.add) catch std.process.exit(1));
    //     },
    //     else => {},
    // }

    return render(srcprg) catch std.process.exit(1);
}

export fn replace_cursor_with_multiplication(srcprg_opaque: *anyopaque) c_interface.frame {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    // switch (srcprg.cursor.cursor_pos) {
    //     .expr => |e| {
    //         overwrite_expr(e, new_op(.mul) catch std.process.exit(1));
    //     },
    //     else => {},
    // }

    return render(srcprg) catch std.process.exit(1);
}

export fn get_offers(srcprg_opaque: ?*anyopaque) [*c]u8 {
    const srcprg: *Srcprg = @ptrCast(@alignCast(srcprg_opaque));

    const t = srcprg.cursor.cursor_pos;

    const offers = t.get_offers();

    const len = blk: {
        var acc: usize = 0;

        for (offers) |o| {
            acc += o.name.len;
            acc += 1; // Trailing NUL.
        }

        acc += 2; // Trailing empty string.

        break :blk acc;
    };

    std.debug.print("{}\n", .{len});

    const mem = cator.alloc(u8, len) catch std.process.exit(1);

    var p = mem.ptr;
    for (offers) |o| {
        std.debug.print("{s}\n", .{o.name});
        @memcpy(p, o.name);
        p += o.name.len;
        p[0] = 0;
        p += 1;
    }

    p[0] = 0;
    p[1] = 1;

    return mem.ptr;
}

const ThreadCursor = @import("ThreadCursor.zig");
