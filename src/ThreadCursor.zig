const std = @import("std");
const th = std.Thread;

const Tree = @import("Tree.zig");
const commands = @import("commands.zig");
const Command = commands.Command;

mutex: th.Mutex,
cond: th.Condition,
pending_command: ?Command,
must_exit: bool,
root: Tree,
cursor_pos: Tree,
amask: AboveMask,
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

pub fn perform(self: *Self, command: Command) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.pending_command = command;
    self.cond.signal();

    while (true) {
        self.cond.wait(&self.mutex);

        if (self.pending_command == null) {
            break;
        }
    }
}

pub fn getMask(self: *Self) Mask {
    return mergeMasks(self.amask, self.cursor_pos);
}

fn receive(self: *Self) ?Command {
    self.mutex.lock();
    // We won't unlock the mutex before returning since it's all synchronous.

    while (true) {
        if (self.must_exit) {
            return null;
        } else if (self.pending_command) |c| {
            return c;
        } else {
            self.cond.wait(&self.mutex);
        }
    }
}

fn report_completion(self: *Self, cursor_pos: Tree, am: AboveMask) void {
    self.pending_command = null;
    self.cursor_pos = cursor_pos;
    self.amask = am;
    self.cond.signal();
    self.mutex.unlock();
}

pub fn init(root: Tree) Self {
    return Self{
        .mutex = .{},
        .cond = .{},
        .pending_command = .go_down,
        .must_exit = false,
        .root = root,
        .cursor_pos = root,
        .amask = undefined,
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

pub fn start(self: *Self) void {
    self.thread = th.spawn(.{}, thread_main, .{self}) catch std.process.exit(1);

    self.mutex.lock();

    while (true) {
        if (self.pending_command == null) {
            self.mutex.unlock();
            return;
        }

        self.cond.wait(&self.mutex);
    }
}

pub fn stop(self: *Self) void {
    self.mutex.lock();
    self.must_exit = true;
    self.cond.signal();
    self.mutex.unlock();
    self.thread.join();
}

fn thread_main(self: *Self) void {
    const am = AboveMask{
        .go_right = false,
        .go_up = false,
        .go_left = false,
        .insert_before = false,
        .insert_after = false,
        .remove_cursor_node = false,
    };
    self.mutex.lock();
    const i = self.traverse_dynamically(self.root, am) catch std.process.exit(1);

    // If our command masks are right, we received up_instruction.exit.
    std.debug.assert(i == .exit);
}

fn traverse_dynamically(
    self: *Self,
    node_on_entry: Tree,
    above_mask: AboveMask,
) !up_instruction {
    self.report_completion(node_on_entry, above_mask);

    var node = node_on_entry;

    while (true) {
        const instr = if (self.receive()) |x| x else return .exit;
        const n = node.childCount();

        switch (instr) {
            .go_right => return .go_right,
            .go_up => return .do_nothing,
            .go_left => return .go_left,
            .go_down => {
                if (0 < n) {
                    var i: usize = 0;

                    while (true) {
                        const m = node.getMask();

                        const am = AboveMask{
                            .go_right = i + 1 < n,
                            .go_up = true,
                            .go_left = 0 < i,
                            .insert_before = m.insert_at,
                            .insert_after = m.insert_at,
                            .remove_cursor_node = m.remove_at,
                        };

                        const up_instr = try self.traverse_dynamically(node.childAt(i), am);

                        switch (up_instr) {
                            .go_left => {
                                if (0 < i) {
                                    i -= 1;
                                }
                            },
                            .go_right => {
                                if (i + 1 < n) {
                                    i += 1;
                                }
                            },
                            .do_nothing => {
                                break;
                            },
                            .insert_before => {
                                _ = try node.insertAt(i);
                            },
                            .insert_after => {
                                if (try node.insertAt(i + 1)) {
                                    i += 1;
                                }
                            },
                            .remove_cursor_node => {
                                switch (node.removeAt(i)) {
                                    .done => {
                                        if (i == n) {
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
                if (n == 0) {
                    _ = try node.insertAt(0);
                }
            },
            .insert_before => return .insert_before,
            .insert_after => return .insert_after,
            .remove => return .remove_cursor_node,
            .replace => unreachable,
        }

        self.report_completion(node, above_mask);
    }
}

pub const Mask = commands.Map(bool);

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

    ret.at_mut(.go_right).* = am.go_right;
    ret.at_mut(.go_up).* = am.go_up;
    ret.at_mut(.go_left).* = am.go_left;
    ret.at_mut(.go_down).* = 0 < node.childCount();
    ret.at_mut(.insert_before).* = am.insert_before;
    ret.at_mut(.insert_after).* = am.insert_after;
    ret.at_mut(.insert_inside).* = node.getMask().insert_at and node.childCount() == 0;
    ret.at_mut(.remove).* = am.remove_cursor_node;
    ret.at_mut(.replace).* = !is_replacing_useless;

    return ret;
}
