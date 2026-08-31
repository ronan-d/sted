const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = std.mem.Allocator.Error;

const gdk = @import("gdk");

const Tree = @import("Tree.zig");
const VTable = Tree.VTable;
const Offer = Tree.Offer;

const Sink = @import("render.zig").Sink;

const Operation = @import("assoc.zig").Operation;

const lists = @import("lists.zig");

const DynamicCommand = @import("commands.zig").DynamicCommand;

const OpType = enum {
    dot,

    pub fn isNotGreaterThan(a: @This(), b: @This()) bool {
        return @intFromEnum(a) <= @intFromEnum(b);
    }

    pub fn render(self: @This(), sink: *Sink) !void {
        try sink.append(switch (self) {
            .dot => ".",
        });
    }
};

const FnProto = struct {
    identifier: Node,
    param_list: Node,
    return_type: Node,
};

const ParamDecl = struct {
    identifier: Node,
    param_type: Node,
};

const Call = struct {
    function: Node,
    args: Node,
};

const Block = lists.List(Node, "{", "}", .break_lines);

const FnDecl = struct {
    proto: Node,
    body: Node,
    is_public: bool,

    fn togglePub(self: *FnDecl) void {
        self.is_public = !self.is_public;
    }

    fn opaqueTogglePub(ptr: *anyopaque) void {
        const node: *Node = @ptrCast(@alignCast(ptr));

        switch (node.*) {
            .fn_decl => |d| d.togglePub(),
            else => unreachable,
        }
    }
};

const ConstDecl = struct {
    identifier: Node,
    type_mark: ?Node,
    expression: Node,
};

pub const Node = union(enum) {
    hole,
    identifier: []u8,
    call: *Call,
    arg_list: ArgList,
    op: Operation(Self, OpType),
    str_lit: []u8,
    try_expr: *Node,
    expr_stmt: *Node,
    block: Block,
    fn_proto: *FnProto,
    param_list: ParamList,
    param_decl: *ParamDecl,
    any_type,
    fn_decl: *FnDecl,
    const_decl: *ConstDecl,

    pub fn drop(self: *Self, gpa: Allocator) void {
        switch (self.*) {
            .hole => {},
            .identifier => |s| gpa.free(s),
            .call => |c| {
                c.function.drop(gpa);
                c.args.drop(gpa);
                gpa.destroy(c);
            },
            .arg_list => |*x| x.drop(gpa),
            .op => |*x| x.drop(gpa),
            .str_lit => |s| gpa.free(s),
            .try_expr => |x| {
                x.drop(gpa);
                gpa.destroy(x);
            },
            .expr_stmt => |x| {
                x.drop(gpa);
                gpa.destroy(x);
            },
            .block => |*x| x.drop(gpa),
            .fn_proto => |s| {
                s.identifier.drop(gpa);
                s.param_list.drop(gpa);
                s.return_type.drop(gpa);
                gpa.destroy(s);
            },
            .param_list => |*x| {
                x.drop(gpa);
            },
            .param_decl => |s| {
                s.identifier.drop(gpa);
                s.param_type.drop(gpa);
                gpa.destroy(s);
            },
            .any_type => {},
            .fn_decl => |d| {
                d.proto.drop(gpa);
                d.body.drop(gpa);
                gpa.destroy(d);
            },
            .const_decl => |d| {
                d.identifier.drop(gpa);
                if (d.type_mark) |*t| {
                    t.drop(gpa);
                }
                d.expression.drop(gpa);
                gpa.destroy(d);
            },
        }
    }

    pub fn render(self: *Self, gpa: Allocator, sink: *Sink, op: ?OpType) !void {
        sink.startNode(self);

        _ = op;

        switch (self.*) {
            .hole => try sink.appendHole(),
            .identifier => |s| try sink.append(s),
            .call => |c| {
                try c.function.render(gpa, sink, null);
                try c.args.render(gpa, sink, null);
            },
            .arg_list => |*x| try x.render(gpa, sink),
            .op => |*x| try x.render(gpa, sink, null),
            .str_lit => |s| {
                sink.active_tag = .str_lit;
                try sink.append("\"");
                try sink.append(s);
                try sink.append("\"");
                sink.active_tag = null;
            },
            .try_expr => |x| {
                sink.tagged("try", .keyword);
                try sink.append(" ");
                try x.render(gpa, sink, null);
            },
            .expr_stmt => |x| {
                try x.render(gpa, sink, null);
                try sink.append(";");
            },
            .block => |*x| try x.render(gpa, sink),
            .fn_proto => |x| {
                sink.tagged("fn", .keyword);
                try sink.append(" ");
                sink.active_tag = .function;
                try x.identifier.render(gpa, sink, null);
                sink.active_tag = null;
                try x.param_list.render(gpa, sink, null);
                try sink.append(" ");

                sink.active_tag = .type;
                try x.return_type.render(gpa, sink, null);
                sink.active_tag = null;
            },
            .param_list => |*x| {
                try x.render(gpa, sink);
            },
            .param_decl => |x| {
                try x.identifier.render(gpa, sink, null);
                try sink.append(": ");

                sink.active_tag = .type;
                try x.param_type.render(gpa, sink, null);
                sink.active_tag = null;
            },
            .any_type => try sink.append("anytype"),
            .fn_decl => |d| {
                if (d.is_public) {
                    sink.tagged("pub", .keyword);
                    try sink.append(" ");
                }
                try d.proto.render(gpa, sink, null);
                try sink.append(" ");
                try d.body.render(gpa, sink, null);
            },
            .const_decl => |d| {
                sink.tagged("const", .keyword);
                try sink.append(" ");
                try d.identifier.render(gpa, sink, null);
                if (d.type_mark) |*t| {
                    try sink.append(" : ");
                    sink.active_tag = .type;
                    try t.render(gpa, sink, null);
                    sink.active_tag = null;
                }
                try sink.append(" = ");
                try d.expression.render(gpa, sink, null);
                try sink.append(";");
            },
        }

        sink.endNode(self);
    }

    pub fn childCount(self: Self) usize {
        return switch (self) {
            .hole => 0,
            .identifier => 0,
            .call => 2,
            .arg_list => |x| x.elements.items.len,
            .op => |x| x.operands.items.len,
            .str_lit => 0,
            .try_expr => 1,
            .expr_stmt => 1,
            .block => |x| x.elements.items.len,
            .fn_proto => 3,
            .param_list => |x| x.elements.items.len,
            .param_decl => 2,
            .any_type => 0,
            .fn_decl => 2,
            .const_decl => |d| if (d.type_mark) |_| 3 else 2,
        };
    }

    pub fn childAt(self: Self, i: usize) Tree {
        return switch (self) {
            .hole => unreachable,
            .identifier => unreachable,
            .call => |x| switch (i) {
                0 => x.function.to_tree(subtypes.expr),
                1 => x.args.to_tree(subtypes.arg_list),
                else => unreachable,
            },
            .arg_list => |x| x.elements.items[i].to_tree(subtypes.expr),
            .op => |x| x.operands.items[i].to_tree(if (x.operator == .dot and i > 0)
                subtypes.right_of_dot
            else
                x.offers),
            .str_lit => unreachable,
            .try_expr => |e| switch (i) {
                0 => e.to_tree(subtypes.expr),
                else => unreachable,
            },
            .expr_stmt => |e| switch (i) {
                0 => e.to_tree(subtypes.expr),
                else => unreachable,
            },
            .block => |x| x.elements.items[i].to_tree(subtypes.stmt),
            .fn_proto => |p| switch (i) {
                0 => p.identifier.to_tree(subtypes.defining_identifier),
                1 => p.param_list.to_tree(subtypes.param_list),
                2 => p.return_type.to_tree(subtypes.type_expr),
                else => unreachable,
            },
            .param_list => |l| l.elements.items[i].to_tree(subtypes.param_decl),
            .param_decl => |d| switch (i) {
                0 => d.identifier.to_tree(subtypes.defining_identifier),
                1 => d.param_type.to_tree(subtypes.param_type),
                else => unreachable,
            },
            .any_type => unreachable,
            .fn_decl => |d| switch (i) {
                0 => d.proto.to_tree(subtypes.fn_proto),
                1 => d.body.to_tree(subtypes.block),
                else => unreachable,
            },
            .const_decl => |d| switch (i) {
                0 => d.identifier.to_tree(subtypes.defining_identifier),
                1 => if (d.type_mark) |*t| t.to_tree(subtypes.param_type) else d.expression.to_tree(subtypes.expr),
                2 => if (d.type_mark) |_| d.expression.to_tree(subtypes.expr) else unreachable,
                else => unreachable,
            },
        };
    }

    pub fn insertAt(self: *Self, gpa: Allocator, i: usize) Error!bool {
        return switch (self.*) {
            .hole => false,
            .identifier => false,
            .call => false,
            .arg_list => |*x| {
                try x.elements.insert(gpa, i, .hole);
                return true;
            },
            .op => |*x| {
                try x.operands.insert(gpa, i, .hole);
                return true;
            },
            .str_lit => unreachable,
            .try_expr => false,
            .expr_stmt => false,
            .block => |*x| {
                try x.elements.insert(gpa, i, .hole);
                return true;
            },
            .fn_proto => false,
            .param_list => |*l| {
                try l.elements.insert(gpa, i, try atoms.mkParamDecl(gpa));
                return true;
            },
            .param_decl => false,
            .any_type => unreachable,
            .fn_decl => false,
            .const_decl => false,
        };
    }

    pub fn removeAt(self: *Self, gpa: Allocator, i: usize) Tree.RemovalOutcome {
        return switch (self.*) {
            .hole => unreachable,
            .identifier => unreachable,
            .call => .not_possible,
            .arg_list => |*l| blk: {
                var elem = l.elements.orderedRemove(i);
                elem.drop(gpa);
                break :blk .done;
            },
            .op => |*x| switch (x.removeAt(gpa, i)) {
                .normal => .done,
                .replaced => .replaced,
            },
            .str_lit => unreachable,
            .try_expr => .not_possible,
            .expr_stmt => .not_possible,
            .block => |*x| blk: {
                var stmt = x.elements.orderedRemove(i);
                stmt.drop(gpa);
                break :blk .done;
            },
            .fn_proto => .not_possible,
            .param_list => |*l| blk: {
                var elem = l.elements.orderedRemove(i);
                elem.drop(gpa);
                break :blk .done;
            },
            .param_decl => .not_possible,
            .any_type => unreachable,
            .fn_decl => .not_possible,
            .const_decl => .not_possible,
        };
    }

    fn getMask(self: Self) Tree.Mask {
        return switch (self) {
            .hole,
            .identifier,
            .call,
            .str_lit,
            .try_expr,
            .expr_stmt,
            .fn_proto,
            .param_decl,
            .any_type,
            .fn_decl,
            .const_decl,
            => Tree.Mask{ .insert_at = false, .remove_at = false },
            .arg_list,
            .op,
            .block,
            .param_list,
            => Tree.Mask{ .insert_at = true, .remove_at = true },
        };
    }

    pub fn commands(self: Self) []const DynamicCommand {
        return switch (self) {
            .fn_decl => &[_]DynamicCommand{
                .{
                    .display_text = "pub",
                    .func = FnDecl.opaqueTogglePub,
                },
            },
            else => &[_]DynamicCommand{},
        };
    }

    fn opaqueChildCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.childCount();
    }

    fn opaqueChildAt(ptr: *anyopaque, i: usize) Tree {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.childAt(i);
    }

    fn opaqueInsertAt(ptr: *anyopaque, gpa: Allocator, i: usize) Error!bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.insertAt(gpa, i);
    }

    fn opaqueRemoveAt(ptr: *anyopaque, gpa: Allocator, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.removeAt(gpa, i);
    }

    fn opaqueGetMask(ptr: *anyopaque) Tree.Mask {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.getMask();
    }

    fn opaqueCommands(ptr: *anyopaque) []const DynamicCommand {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.commands();
    }

    fn opaqueRender(ptr: *anyopaque, gpa: Allocator, sink: *Sink) Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.render(gpa, sink, null);
    }

    fn opaqueDeinit(ptr: *anyopaque, gpa: Allocator) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.drop(gpa);
        gpa.destroy(self);
    }

    const vtable = VTable{
        .childCount = opaqueChildCount,
        .childAt = opaqueChildAt,
        .insertAt = opaqueInsertAt,
        .removeAt = opaqueRemoveAt,
        .getMask = opaqueGetMask,
        .deinit = opaqueDeinit,
        .commands = opaqueCommands,
        .render = opaqueRender,
    };

    fn to_tree(self: *Self, subtype: subtypes.Subtype) Tree {
        return Tree{
            .ptr = self,
            .vtable = &vtable,
            .replacement_offers = subtype,
        };
    }

    const Self = @This();
};

const ArgList = lists.List(Node, "(", ")", .{ .symbol = ", " });

const ParamList = lists.List(Node, "(", ")", .{ .symbol = ", " });

pub fn get_sample(gpa: Allocator) Error!Tree {
    const dot_chain0 = blk: {
        var x = try std.ArrayList(Node).initCapacity(gpa, 4);

        x.appendAssumeCapacity(Node{ .identifier = try gpa.dupe(u8, "std") });
        x.appendAssumeCapacity(Node{ .identifier = try gpa.dupe(u8, "fs") });
        x.appendAssumeCapacity(Node{ .identifier = try gpa.dupe(u8, "File") });
        x.appendAssumeCapacity(Node{ .identifier = try gpa.dupe(u8, "stdout") });

        break :blk Node{ .op = .{ .operator = .dot, .operands = x, .offers = subtypes.expr } };
    };

    var dot_chain = try std.ArrayList(Node).initCapacity(gpa, 2);

    {
        const p = try gpa.create(Call);
        p.* = .{
            .function = dot_chain0,
            .args = Node{ .arg_list = ArgList.initialValue() },
        };

        dot_chain.appendAssumeCapacity(Node{ .call = p });
    }

    dot_chain.appendAssumeCapacity(Node{ .identifier = try gpa.dupe(u8, "writeAll") });

    const qual_id = Node{ .op = .{ .operator = .dot, .operands = dot_chain, .offers = subtypes.expr } };

    var args = try std.ArrayList(Node).initCapacity(gpa, 1);
    args.appendAssumeCapacity(Node{ .str_lit = try gpa.dupe(u8, "Hello, World!\\n") });

    const call = try gpa.create(Call);
    call.* = .{
        .function = qual_id,
        .args = Node{ .arg_list = ArgList{ .elements = args } },
    };

    const call_node = try gpa.create(Node);
    call_node.* = Node{ .call = call };

    const te = try gpa.create(Node);
    te.* = Node{ .try_expr = call_node };

    const s = Node{ .expr_stmt = te };

    var b = Block.initialValue();

    try b.elements.append(gpa, s);

    const proto = try gpa.create(FnProto);
    proto.* = blk: {
        const id = Node{ .identifier = try gpa.dupe(u8, "main") };

        const plist = Node{ .param_list = ParamList.initialValue() };

        const ret_typ = Node{ .identifier = try gpa.dupe(u8, "void") };

        break :blk FnProto{
            .identifier = id,
            .param_list = plist,
            .return_type = ret_typ,
        };
    };

    const fnd = try gpa.create(FnDecl);
    fnd.* = FnDecl{
        .proto = Node{ .fn_proto = proto },
        .body = Node{ .block = b },
        .is_public = true,
    };

    const ret = try gpa.create(Node);
    ret.* = Node{ .fn_decl = fnd };

    return ret.to_tree(subtypes.decl);
}

const atoms = struct {
    fn rwv(comptime f: fn (Allocator) Error!Node) Tree.Rewriter {
        const local_module = struct {
            fn g(ptr: *anyopaque, gpa: Allocator) Error!void {
                const node: *Node = @ptrCast(@alignCast(ptr));

                node.* = try f(gpa);
            }
        };

        return .{ .from_void = local_module.g };
    }
    fn rws(comptime f: fn (Allocator, []const u8) Error!Node) Tree.Rewriter {
        const local_module = struct {
            fn g(ptr: *anyopaque, gpa: Allocator, s: []const u8) Error!void {
                const node: *Node = @ptrCast(@alignCast(ptr));

                node.* = try f(gpa, s);
            }
        };

        return .{ .from_string = local_module.g };
    }
    fn rwi(comptime f: fn (u64) Node) Tree.Rewriter {
        const local_module = struct {
            fn g(ptr: *anyopaque, n: u64) void {
                const node: *Node = @ptrCast(@alignCast(ptr));

                node.* = try f(n);
            }
        };

        return .{ .from_int = local_module.g };
    }

    fn mkIdentifier(gpa: Allocator, s: []const u8) Error!Node {
        return Node{ .identifier = try gpa.dupe(u8, s) };
    }

    const identifier = Offer{
        .name = "identifier",
        .rewriter = rws(mkIdentifier),
    };

    fn mkCall(gpa: Allocator) Error!Node {
        const alist = ArgList.initialValue();

        const p = try gpa.create(Call);
        p.* = Call{ .function = .hole, .args = Node{ .arg_list = alist } };
        return .{ .call = p };
    }

    const call = Offer{
        .name = "call",
        .rewriter = rwv(mkCall),
    };

    fn op(comptime name: [:0]const u8, comptime o: OpType, comptime offers: []Offer) Offer {
        const local_module = struct {
            fn mkOp() Error!Node {
                return Operation(Node, OpType).make_initial_value(o, .hole, offers);
            }
        };

        return Offer{ .name = name, .rewriter = rwv(local_module.mkOp) };
    }

    fn rwDot(ptr: *anyopaque, gpa: Allocator) Error!void {
        const self: *Node = @ptrCast(@alignCast(ptr));

        self.* = Node{ .op = try Operation(Node, OpType).make_initial_value(gpa, .dot, .hole, subtypes.expr) };
    }

    const dot = Offer{
        .name = ".",
        .rewriter = .{ .from_void = rwDot },
    };

    fn mkStrLit(gpa: Allocator, s: []const u8) Error!Node {
        return Node{ .str_lit = try gpa.dupe(u8, s) };
    }

    const str_lit = Offer{
        .name = "\"…\"",
        .rewriter = rws(mkStrLit),
    };

    fn mkTryExpr(gpa: Allocator) Error!Node {
        const p = try gpa.create(Node);
        p.* = .hole;

        return Node{ .try_expr = p };
    }

    const try_expr = Offer{
        .name = "try",
        .rewriter = rwv(mkTryExpr),
    };

    fn mkExprStmt(gpa: Allocator) Error!Node {
        const p = try gpa.create(Node);
        p.* = .hole;

        return Node{ .expr_stmt = p };
    }

    const expr_stmt = Offer{
        .name = ";",
        .rewriter = rwv(mkExprStmt),
    };

    fn mkBlock(_: Allocator) Error!Node {
        return Node{ .block = Block.initialValue() };
    }

    const block = Offer{
        .name = "{…}",
        .rewriter = rwv(mkBlock),
    };

    fn mkFnProto(gpa: Allocator) Error!Node {
        const p = try gpa.create(FnProto);
        p.identifier = .hole;
        p.param_list = Node{ .param_list = ParamList.initialValue() };
    }

    const fn_proto = Offer{
        .name = "fn",
        .rewriter = rwv(mkFnProto),
    };

    fn mkParamDecl(gpa: Allocator) Error!Node {
        const p = try gpa.create(ParamDecl);
        p.* = .{ .identifier = .hole, .param_type = .hole };

        return Node{ .param_decl = p };
    }

    const param_decl = Offer{
        .name = "param decl",
        .rewriter = rwv(mkParamDecl),
    };

    fn mkAnyType(_: Allocator) Error!Node {
        return Node.any_type;
    }

    const any_type = Offer{
        .name = "anytype",
        .rewriter = rwv(mkAnyType),
    };

    fn mkFnDecl(gpa: Allocator) Error!Node {
        const p = try gpa.create(FnProto);
        p.* = FnProto{
            .identifier = .hole,
            .param_list = Node{ .param_list = ParamList.initialValue() },
            .return_type = .hole,
        };

        const p0 = try gpa.create(FnDecl);
        p0.* = FnDecl{
            .proto = Node{ .fn_proto = p },
            .body = Node{ .block = Block.initialValue() },
            .is_public = false,
        };

        return Node{ .fn_decl = p0 };
    }

    const fn_decl = Offer{
        .name = "fn",
        .rewriter = rwv(mkFnDecl),
    };

    fn mkConstDecl(gpa: Allocator) Error!Node {
        const p = try gpa.create(ConstDecl);

        p.* = ConstDecl{
            .identifier = .hole,
            .type_mark = .hole,
            .expression = .hole,
        };

        return Node{ .const_decl = p };
    }

    const const_decl = Offer{
        .name = "const",
        .rewriter = rwv(mkConstDecl),
    };
};

const subtypes = struct {
    const Subtype = []const Offer;

    const expr: Subtype = &[_]Offer{
        atoms.identifier,
        atoms.call,
        atoms.dot,
        atoms.str_lit,
        atoms.try_expr,
    };

    const stmt: Subtype = &[_]Offer{
        atoms.expr_stmt,
        atoms.block,
        atoms.const_decl,
    };

    const defining_identifier: Subtype = &[_]Offer{
        atoms.identifier,
    };

    const param_type: Subtype = &[_]Offer{
        atoms.identifier,
        atoms.any_type,
    };

    const type_expr: Subtype = &[_]Offer{
        atoms.identifier,
    };

    const right_of_dot: Subtype = &[_]Offer{
        atoms.identifier,
    };

    const decl: Subtype = &[_]Offer{
        atoms.fn_decl,
    };

    // One possible value, so no choice to make and therefore an empty array.
    const arg_list: Subtype = &[_]Offer{};

    const param_list: Subtype = &[_]Offer{};

    const param_decl: Subtype = &[_]Offer{};

    const fn_proto: Subtype = &[_]Offer{};

    const block: Subtype = &[_]Offer{};

    const fn_decl: Subtype = &[_]Offer{};
};
