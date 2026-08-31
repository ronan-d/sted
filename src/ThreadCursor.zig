const std = @import("std");
const th = std.Thread;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const commands = @import("commands.zig");
const Command = commands.Command;
const Mask = commands.Mask;
const DynamicCommand = commands.DynamicCommand;
const Tree = @import("Tree.zig");

mutex: Io.Mutex,
cond: Io.Condition,
pending_command: ?Command,
must_exit: bool,
root: Tree,
cursor_pos: Tree,
amask: AboveMask,
cmds: []const DynamicCommand,
thread: std.Thread,

const Self = @This();

pub const instruction = enum {
    go_right,
    go_up,
    go_left,
    go_down,
    insert_before,
    insert_after,
    insert_inside,
    remove_cursor_node,
};

pub fn perform(self: *Self, io: Io, command: Command) !void {
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    self.pending_command = command;
    self.cond.signal(io);

    while (true) {
        try self.cond.wait(io, &self.mutex);

        if (self.pending_command == null) {
            break;
        }
    }
}

pub fn getMask(self: *Self) Mask {
    return mergeMasks(self.amask, self.cursor_pos);
}

fn receive(self: *Self, io: Io) !?Command {
    try self.mutex.lock(io);
    // We won't unlock the mutex before returning since it's all synchronous.

    while (true) {
        if (self.must_exit) {
            return null;
        } else if (self.pending_command) |c| {
            return c;
        } else {
            try self.cond.wait(io, &self.mutex);
        }
    }
}

fn report_completion(self: *Self, io: Io, cursor_pos: Tree, am: AboveMask) void {
    self.pending_command = null;
    self.cursor_pos = cursor_pos;
    self.amask = am;
    self.cmds = cursor_pos.commands();
    self.cond.signal(io);
    self.mutex.unlock(io);
}

pub fn init(root: Tree) Self {
    return Self{
        .mutex = .init,
        .cond = .init,
        .pending_command = .go_down,
        .must_exit = false,
        .root = root,
        .cursor_pos = root,
        .amask = undefined,
        .cmds = &[_]DynamicCommand{},
        .thread = undefined,
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
    exit,
};

pub fn start(self: *Self, io: Io, gpa: Allocator) !void {
    self.thread = th.spawn(.{}, thread_main, .{ self, io, gpa }) catch std.process.exit(1);

    try self.mutex.lock(io);

    while (true) {
        if (self.pending_command == null) {
            self.mutex.unlock(io);
            return;
        }

        try self.cond.wait(io, &self.mutex);
    }
}

pub fn stop(self: *Self, io: Io) !void {
    try self.mutex.lock(io);
    self.must_exit = true;
    self.cond.signal(io);
    self.mutex.unlock(io);
    self.thread.join();
}

fn thread_main(self: *Self, io: Io, gpa: Allocator) !void {
    const am = AboveMask{
        .go_right = false,
        .go_up = false,
        .go_left = false,
        .insert_before = false,
        .insert_after = false,
        .remove_cursor_node = false,
    };
    try self.mutex.lock(io);
    const i = self.traverse_dynamically(io, gpa, self.root, am) catch unreachable;

    // If our command masks are right, we received up_instruction.exit.
    std.debug.assert(i == .exit);
}

fn traverse_dynamically(
    self: *Self,
    io: Io,
    gpa: Allocator,
    node_on_entry: Tree,
    above_mask: AboveMask,
) !up_instruction {
    self.report_completion(io, node_on_entry, above_mask);

    var node = node_on_entry;

    while (true) {
        const instr = if (try self.receive(io)) |x| x else return .exit;

        switch (instr) {
            .go_right => return .go_right,
            .go_up => return .do_nothing,
            .go_left => return .go_left,
            .go_down => {
                if (0 < node.childCount()) {
                    var i: usize = 0;

                    while (true) {
                        const m = node.getMask();

                        const am = AboveMask{
                            .go_right = i + 1 < node.childCount(),
                            .go_up = true,
                            .go_left = 0 < i,
                            .insert_before = m.insert_at,
                            .insert_after = m.insert_at,
                            .remove_cursor_node = m.remove_at,
                        };

                        const up_instr = try self.traverse_dynamically(io, gpa, node.childAt(i), am);

                        switch (up_instr) {
                            .go_left => {
                                if (0 < i) {
                                    i -= 1;
                                }
                            },
                            .go_right => {
                                if (i + 1 < node.childCount()) {
                                    i += 1;
                                }
                            },
                            .do_nothing => {
                                break;
                            },
                            .insert_before => {
                                _ = try node.insertAt(gpa, i);
                            },
                            .insert_after => {
                                if (try node.insertAt(gpa, i + 1)) {
                                    i += 1;
                                }
                            },
                            .remove_cursor_node => {
                                switch (node.removeAt(gpa, i)) {
                                    .done => {
                                        if (node.childCount() == 0) {
                                            break;
                                        }

                                        if (i == node.childCount()) {
                                            i = i - 1;
                                        }
                                    },
                                    .not_possible => {},
                                    .replaced => break,
                                }
                            },
                            .exit => return .exit,
                        }
                    }
                }
            },
            .insert_inside => {
                if (node.childCount() == 0) {
                    _ = try node.insertAt(gpa, 0);
                }
            },
            .insert_before => return .insert_before,
            .insert_after => return .insert_after,
            .remove => return .remove_cursor_node,
            .replace => unreachable,
        }

        self.report_completion(io, node, above_mask);
    }
}

// The part of the command mask for which we need to look at the parent of the
// node that's under the cursor, and not the node itself. "Above" because the
// values of the fields come from the parent, which is above.
const AboveMask = struct {
    go_right: bool,
    go_up: bool,
    go_left: bool,
    insert_before: bool,
    insert_after: bool,
    remove_cursor_node: bool,
};

fn mergeMasks(am: AboveMask, node: Tree) Mask {
    const offers = node.replacement_offers;
    const is_replacing_useless = offers.len == 0 or offers.len == 1 and offers[0].rewriter == .from_void;

    var ret: Mask = undefined;

    ret.getPtr(.go_right).* = am.go_right;
    ret.getPtr(.go_up).* = am.go_up;
    ret.getPtr(.go_left).* = am.go_left;
    ret.getPtr(.go_down).* = 0 < node.childCount();
    ret.getPtr(.insert_before).* = am.insert_before;
    ret.getPtr(.insert_after).* = am.insert_after;
    ret.getPtr(.insert_inside).* = node.getMask().insert_at and node.childCount() == 0;
    ret.getPtr(.remove).* = am.remove_cursor_node;
    ret.getPtr(.replace).* = !is_replacing_useless;

    return ret;
}
