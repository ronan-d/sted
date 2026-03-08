const std = @import("std");
const cator = std.heap.c_allocator;
const Error = std.mem.Allocator.Error;

const Tree = @import("Tree.zig");
const VTable = Tree.VTable;
const Offer = Tree.Offer;

const Sink = @import("render.zig").Sink;

const Operation = @import("assoc.zig").Operation;

const lists = @import("lists.zig");

const OpType = enum {
    dot,

    pub fn isNotGreaterThan(a: @This(), b: @This()) bool {
        return @intFromEnum(a) <= @intFromEnum(b);
    }

    pub fn render(self: @This(), sink: *Sink) !void {
        try sink.appendAscii(switch (self) {
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
};

const Node = union(enum) {
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

    pub fn drop(self: *Self) void {
        switch (self.*) {
            .hole => {},
            .identifier => |s| cator.free(s),
            .call => |c| {
                c.function.drop();
                c.args.drop();
                cator.destroy(c);
            },
            .arg_list => |*x| x.drop(),
            .op => |*x| x.drop(),
            .str_lit => |s| cator.free(s),
            .try_expr => |x| {
                x.drop();
                cator.destroy(x);
            },
            .expr_stmt => |x| {
                x.drop();
                cator.destroy(x);
            },
            .block => |*x| x.drop(),
            .fn_proto => |s| {
                s.identifier.drop();
                s.param_list.drop();
                s.return_type.drop();
                cator.destroy(s);
            },
            .param_list => |*x| {
                x.drop();
            },
            .param_decl => |s| {
                s.identifier.drop();
                s.param_type.drop();
                cator.destroy(s);
            },
            .any_type => {},
            .fn_decl => |d| {
                d.proto.drop();
                d.body.drop();
                cator.destroy(d);
            },
        }
    }

    pub fn render(self: *Self, sink: *Sink, op: ?OpType) !void {
        sink.startNode(self);

        _ = op;

        switch (self.*) {
            .hole => try sink.appendHole(),
            .identifier => |s| try sink.appendAscii(s),
            .call => |c| {
                try c.function.render(sink, null);
                try c.args.render(sink, null);
            },
            .arg_list => |*x| try x.render(sink),
            .op => |*x| try x.render(sink, null),
            .str_lit => |s| {
                try sink.appendAscii("\"");
                try sink.appendAscii(s);
                try sink.appendAscii("\"");
            },
            .try_expr => |x| {
                try sink.appendAscii("try ");
                try x.render(sink, null);
            },
            .expr_stmt => |x| {
                try x.render(sink, null);
                try sink.appendAscii(";");
            },
            .block => |*x| try x.render(sink),
            .fn_proto => |x| {
                try sink.appendAscii("fn ");
                try x.identifier.render(sink, null);
                try x.param_list.render(sink, null);
                try sink.appendAscii(" ");
                try x.return_type.render(sink, null);
            },
            .param_list => |*x| {
                try x.render(sink);
            },
            .param_decl => |x| {
                try x.identifier.render(sink, null);
                try sink.appendAscii(": ");
                try x.param_type.render(sink, null);
            },
            .any_type => try sink.appendAscii("anytype"),
            .fn_decl => |d| {
                try d.proto.render(sink, null);
                try sink.appendAscii(" ");
                try d.body.render(sink, null);
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
            .op => |x| x.operands.items[i].to_tree(x.offers),
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
        };
    }

    pub fn insertAt(self: *Self, i: usize) Error!bool {
        return switch (self.*) {
            .hole => false,
            .identifier => false,
            .call => false,
            .arg_list => |*x| {
                try x.elements.insert(cator, i, .hole);
                return true;
            },
            .op => |*x| {
                try x.operands.insert(cator, i, .hole);
                return true;
            },
            .str_lit => unreachable,
            .try_expr => false,
            .expr_stmt => false,
            .block => |*x| {
                try x.elements.insert(cator, i, .hole);
                return true;
            },
            .fn_proto => false,
            .param_list => |*l| {
                try l.elements.insert(cator, i, try atoms.mkParamDecl());
                return true;
            },
            .param_decl => false,
            .any_type => unreachable,
            .fn_decl => false,
        };
    }

    pub fn removeAt(self: *Self, i: usize) Tree.RemovalOutcome {
        return switch (self.*) {
            .hole => unreachable,
            .identifier => unreachable,
            .call => .not_possible,
            .arg_list => |*l| blk: {
                var elem = l.elements.orderedRemove(i);
                elem.drop();
                break :blk .done;
            },
            .op => |*x| switch (x.removeAt(i)) {
                .normal => .done,
                .replaced => .replaced,
            },
            .str_lit => unreachable,
            .try_expr => .not_possible,
            .expr_stmt => .not_possible,
            .block => |*x| blk: {
                var stmt = x.elements.orderedRemove(i);
                stmt.drop();
                break :blk .done;
            },
            .fn_proto => .not_possible,
            .param_list => |*l| blk: {
                var elem = l.elements.orderedRemove(i);
                elem.drop();
                break :blk .done;
            },
            .param_decl => .not_possible,
            .any_type => unreachable,
            .fn_decl => .not_possible,
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

    fn opaqueInsertAt(ptr: *anyopaque, i: usize) Error!bool {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.insertAt(i);
    }

    fn opaqueRemoveAt(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.removeAt(i);
    }

    fn opaqueRender(ptr: *anyopaque, sink: *Sink) Error!void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        return self.render(sink, null);
    }

    const vtable = VTable{
        .childCount = opaqueChildCount,
        .childAt = opaqueChildAt,
        .insertAt = opaqueInsertAt,
        .removeAt = opaqueRemoveAt,
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

pub fn get_sample() Error!Tree {
    const dot_chain0 = blk: {
        var x = try std.ArrayList(Node).initCapacity(cator, 4);

        x.appendAssumeCapacity(Node{ .identifier = try cator.dupe(u8, "std") });
        x.appendAssumeCapacity(Node{ .identifier = try cator.dupe(u8, "fs") });
        x.appendAssumeCapacity(Node{ .identifier = try cator.dupe(u8, "File") });
        x.appendAssumeCapacity(Node{ .identifier = try cator.dupe(u8, "stdout") });

        break :blk Node{ .op = .{ .operator = .dot, .operands = x, .offers = subtypes.expr } };
    };

    var dot_chain = try std.ArrayList(Node).initCapacity(cator, 2);

    {
        const p = try cator.create(Call);
        p.* = .{
            .function = dot_chain0,
            .args = Node{ .arg_list = ArgList.initialValue() },
        };

        dot_chain.appendAssumeCapacity(Node{ .call = p });
    }

    dot_chain.appendAssumeCapacity(Node{ .identifier = try cator.dupe(u8, "writeAll") });

    const qual_id = Node{ .op = .{ .operator = .dot, .operands = dot_chain, .offers = subtypes.expr } };

    var args = try std.ArrayList(Node).initCapacity(cator, 1);
    args.appendAssumeCapacity(Node{ .str_lit = try cator.dupe(u8, "Hello, World!\\n") });

    const call = try cator.create(Call);
    call.* = .{
        .function = qual_id,
        .args = Node{ .arg_list = ArgList{ .elements = args } },
    };

    const call_node = try cator.create(Node);
    call_node.* = Node{ .call = call };

    const te = try cator.create(Node);
    te.* = Node{ .try_expr = call_node };

    const s = Node{ .expr_stmt = te };

    var b = Block.initialValue();

    try b.elements.append(cator, s);

    const proto = try cator.create(FnProto);
    proto.* = blk: {
        const id = Node{ .identifier = try cator.dupe(u8, "main") };

        const plist = Node{ .param_list = ParamList.initialValue() };

        const ret_typ = Node{ .identifier = try cator.dupe(u8, "void") };

        break :blk FnProto{
            .identifier = id,
            .param_list = plist,
            .return_type = ret_typ,
        };
    };

    const fnd = try cator.create(FnDecl);
    fnd.* = FnDecl{
        .proto = Node{ .fn_proto = proto },
        .body = Node{ .block = b },
    };

    const ret = try cator.create(Node);
    ret.* = Node{ .fn_decl = fnd };

    return ret.to_tree(subtypes.stmt);
}

const atoms = struct {
    fn rwv(comptime f: fn () Error!Node) Tree.Rewriter {
        const local_module = struct {
            fn g(ptr: *anyopaque) Error!void {
                const node: *Node = @ptrCast(@alignCast(ptr));

                node.* = try f();
            }
        };

        return .{ .from_void = local_module.g };
    }
    fn rws(comptime f: fn ([]const u8) Error!Node) Tree.Rewriter {
        const local_module = struct {
            fn g(ptr: *anyopaque, s: []const u8) Error!void {
                const node: *Node = @ptrCast(@alignCast(ptr));

                node.* = try f(s);
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

    fn mkIdentifier(s: []const u8) Error!Node {
        return Node{ .identifier = try cator.dupe(u8, s) };
    }

    const identifier = Offer{
        .name = "identifier",
        .rewriter = rws(mkIdentifier),
    };

    fn mkCall() Error!Node {
        const alist = ArgList.initialValue();

        const p = try cator.create(Call);
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

    fn rwDot(ptr: *anyopaque) Error!void {
        const self: *Node = @ptrCast(@alignCast(ptr));

        self.* = Node{ .op = try Operation(Node, OpType).make_initial_value(.dot, .hole, subtypes.expr) };
    }

    const dot = Offer{
        .name = ".",
        .rewriter = .{ .from_void = rwDot },
    };

    fn mkStrLit(s: []const u8) Error!Node {
        return Node{ .str_lit = try cator.dupe(u8, s) };
    }

    const str_lit = Offer{
        .name = "\"…\"",
        .rewriter = rws(mkStrLit),
    };

    fn mkTryExpr() Error!Node {
        const p = try cator.create(Node);
        p.* = .hole;

        return Node{ .try_expr = p };
    }

    const try_expr = Offer{
        .name = "try",
        .rewriter = rwv(mkTryExpr),
    };

    fn mkExprStmt() Error!Node {
        const p = try cator.create(Node);
        p.* = .hole;

        return Node{ .expr_stmt = p };
    }

    const expr_stmt = Offer{
        .name = ";",
        .rewriter = rwv(mkExprStmt),
    };

    fn mkBlock() Error!Node {
        return Node{ .block = Block.initialValue() };
    }

    const block = Offer{
        .name = "{…}",
        .rewriter = rwv(mkBlock),
    };

    fn mkFnProto() Error!Node {
        const p = try cator.create(FnProto);
        p.identifier = .hole;
        p.param_list = Node{ .param_list = ParamList.initialValue() };
    }

    const fn_proto = Offer{
        .name = "fn",
        .rewriter = rwv(mkFnProto),
    };

    fn mkParamDecl() Error!Node {
        const p = try cator.create(ParamDecl);
        p.* = .{ .identifier = .hole, .param_type = .hole };

        return Node{ .param_decl = p };
    }

    const param_decl = Offer{
        .name = "param decl",
        .rewriter = rwv(mkParamDecl),
    };

    fn mkAnyType() Error!Node {
        return Node.any_type;
    }

    const any_type = Offer{
        .name = "anytype",
        .rewriter = rwv(mkAnyType),
    };

    fn mkFnDecl() Error!Node {
        const p = try cator.create(FnProto);
        p.* = FnProto{ .identifier = .hole, .param_list = ParamList.initialValue() };

        const p0 = try cator.create(FnDecl);
        p0.* = FnDecl{ .proto = Node{ .fn_proto = p }, .body = Node{ .block = Block.initialValue() } };

        return Node{ .fn_decl = p0 };
    }

    const fn_decl = Offer{
        .name = "fn",
        .rewriter = rwv(mkFnDecl),
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

    // One possible value, so no choice to make and therefore an empty array.
    const arg_list: Subtype = &[_]Offer{};

    const param_list: Subtype = &[_]Offer{};

    const param_decl: Subtype = &[_]Offer{};

    const fn_proto: Subtype = &[_]Offer{};

    const block: Subtype = &[_]Offer{};

    const fn_decl: Subtype = &[_]Offer{};
};
