const std = @import("std");

const th = std.Thread;

const Tree = @import("Tree.zig");

mutex: th.Mutex,
cond: th.Condition,
pending_instruction: ?instruction,
root: Tree,
cursor_pos: Tree,

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

fn report_completion(self: *Self, cursor_pos: Tree) void {
    self.pending_instruction = null;
    self.cursor_pos = cursor_pos;
    self.cond.signal();
    self.mutex.unlock();
}

pub fn init(root: Tree) Self {
    return Self{
        .mutex = .{},
        .cond = .{},
        .pending_instruction = null,
        .root = root,
        .cursor_pos = root,
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
        self.report_completion(self.root);
    }
}

fn traverse_dynamically(
    self: *Self,
    node_on_entry: Tree,
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
                                switch (node.remove_at(i)) {
                                    .done => |x| i = x.new_index,
                                    .not_possible => {},
                                    .replaced => break,
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
