const std = @import("std");
const cator = std.heap.c_allocator;
const Error = std.mem.Allocator.Error;

const Sink = @import("render.zig").Sink;

pub fn Operation(
    OperandType: type,
    OperatorType: type,
) type {
    return struct {
        operator: OperatorType,
        operands: std.ArrayList(OperandType),

        const Self = @This();

        const drop_operand = @field(OperandType, "drop");

        pub fn drop(self: *Self) void {
            for (self.operands.items) |*operand| {
                drop_operand(operand);
            }

            self.operands.deinit(cator);
        }

        pub fn render(self: Self, sink: *Sink, parent_operator: ?OperatorType) Error!void {
            // The absence of {start,end}_node calls is deliberate.

            const is_not_greater_than = @field(OperatorType, "isNotGreaterThan");

            const need_parentheses = if (parent_operator) |po| is_not_greater_than(self.operator, po) else false;

            if (need_parentheses) {
                try sink.appendAscii("(");
            }

            const render_operand = @field(OperandType, "render");
            const render_operator = @field(OperatorType, "render");

            if (0 < self.operands.items.len) {
                try render_operand(&self.operands.items[0], sink, self.operator);

                for (self.operands.items[1..]) |*operand| {
                    try sink.appendAscii(" ");
                    try render_operator(self.operator, sink);
                    try sink.appendAscii(" ");

                    try render_operand(operand, sink, self.operator);
                }
            }

            if (need_parentheses) {
                try sink.appendAscii(")");
            }
        }

        pub fn make_initial_value(operator: OperatorType, hole: OperandType) !Self {
            var operands = try std.ArrayList(OperandType).initCapacity(cator, 2);
            operands.appendAssumeCapacity(hole);
            operands.appendAssumeCapacity(hole);

            return Self{ .operator = operator, .operands = operands };
        }

        pub fn childAt(self: Self, i: usize) *OperandType {
            return &self.operands.items[i];
        }

        pub fn insertAt(self: *Self, i: usize, hole: OperandType) !bool {
            if (i <= self.operands.items.len) {
                try self.operands.insert(cator, i, hole);
                return true;
            }

            return false;
        }

        const RemovalOutcome = union(enum) {
            normal,
            replaced: OperandType,
        };

        pub fn removeAt(self: *Self, i: usize) RemovalOutcome {
            // orderedRemove makes the same assertion, but we keep this one for now.
            std.debug.assert(i < self.operands.items.len);

            var x = self.operands.orderedRemove(i);
            drop_operand(&x);

            // It's an invariant that we should never have fewer than 2 operands.
            // We don't check it everywhere, but we do here.
            std.debug.assert(0 < self.operands.items.len);

            if (self.operands.items.len == 1) {
                const last_operand = self.operands.items[0];
                self.operands.deinit(cator);

                return RemovalOutcome{ .replaced = last_operand };
            }

            return RemovalOutcome.normal;
        }
    };
}
