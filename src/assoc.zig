const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = std.mem.Allocator.Error;

const Sink = @import("render.zig").Sink;

const Offer = @import("Tree.zig").Offer;

pub fn Operation(
    OperandType: type,
    OperatorType: type,
) type {
    return struct {
        operator: OperatorType,
        operands: std.ArrayList(OperandType),
        offers: []const Offer,

        const Self = @This();

        const drop_operand = @field(OperandType, "drop");

        pub fn drop(self: *Self, gpa: Allocator) void {
            for (self.operands.items) |*operand| {
                drop_operand(operand, gpa);
            }

            self.operands.deinit(gpa);
        }

        pub fn render(self: Self, gpa: Allocator, sink: *Sink, parent_operator: ?OperatorType) Error!void {
            // The absence of {start,end}_node calls is deliberate.

            const is_not_greater_than = @field(OperatorType, "isNotGreaterThan");

            const need_parentheses = if (parent_operator) |po| is_not_greater_than(self.operator, po) else false;

            if (need_parentheses) {
                try sink.append("(");
            }

            const render_operand = @field(OperandType, "render");
            const render_operator = @field(OperatorType, "render");

            if (0 < self.operands.items.len) {
                try render_operand(&self.operands.items[0], gpa, sink, self.operator);

                for (self.operands.items[1..]) |*operand| {
                    try render_operator(self.operator, sink);

                    try render_operand(operand, gpa, sink, self.operator);
                }
            }

            if (need_parentheses) {
                try sink.append(")");
            }
        }

        pub fn make_initial_value(
            gpa: Allocator,
            operator: OperatorType,
            hole: OperandType,
            offers: []const Offer,
        ) !Self {
            var operands = try std.ArrayList(OperandType).initCapacity(gpa, 2);
            operands.appendAssumeCapacity(hole);
            operands.appendAssumeCapacity(hole);

            return Self{ .operator = operator, .operands = operands, .offers = offers };
        }

        pub fn childAt(self: Self, i: usize) *OperandType {
            return &self.operands.items[i];
        }

        pub fn insertAt(self: *Self, gpa: Allocator, i: usize, hole: OperandType) Error!bool {
            if (i <= self.operands.items.len) {
                try self.operands.insert(gpa, i, hole);
                return true;
            }

            return false;
        }

        const RemovalOutcome = union(enum) {
            normal,
            replaced: OperandType,
        };

        pub fn removeAt(self: *Self, gpa: Allocator, i: usize) RemovalOutcome {
            // orderedRemove makes the same assertion, but we keep this one for now.
            std.debug.assert(i < self.operands.items.len);

            var x = self.operands.orderedRemove(i);
            drop_operand(&x, gpa);

            // It's an invariant that we should never have fewer than 2 operands.
            // We don't check it everywhere, but we do here.
            std.debug.assert(0 < self.operands.items.len);

            if (self.operands.items.len == 1) {
                const last_operand = self.operands.items[0];
                self.operands.deinit(gpa);

                return RemovalOutcome{ .replaced = last_operand };
            }

            return RemovalOutcome.normal;
        }
    };
}
