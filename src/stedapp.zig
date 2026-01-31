const std = @import("std");

const adw = @import("adw");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const gdk = @import("gdk");

const cator = std.heap.c_allocator;

const StedWindow = @import("stedwindow.zig").StedWindow;

const ThreadCursor = @import("ThreadCursor.zig");
const instruction = ThreadCursor.instruction;

pub const StedApp = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.Application;

    pub const getGObjectType = gobject.ext.defineClass(StedApp, .{
        .classInit = &Class.init,
    });

    pub fn new() *StedApp {
        return gobject.ext.newInstance(StedApp, .{
            .application_id = "org.ronan-d.sted",
            .flags = gio.ApplicationFlags{ .non_unique = true },
        });
    }

    pub fn as(app: *StedApp, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = StedApp;

        fn activateImpl(app: *StedApp) callconv(.c) void {
            const win = StedWindow.new(app);

            app.bind_instruction_to_key(win, .go_right, gdk.KEY_l);
            app.bind_instruction_to_key(win, .go_up, gdk.KEY_k);
            app.bind_instruction_to_key(win, .go_left, gdk.KEY_h);
            app.bind_instruction_to_key(win, .go_down, gdk.KEY_j);

            app.bind_instruction_to_key(win, .insert_before, gdk.KEY_s);
            app.bind_instruction_to_key(win, .insert_after, gdk.KEY_d);

            app.bind_instruction_to_key(win, .remove_cursor_node, gdk.KEY_r);

            app.register_accel("open-num-dialog", gdk.KEY_a);

            app.bind_win_method_to_key(win, "replace", gdk.KEY_o);

            gtk.Window.present(win.as(gtk.Window));
        }

        fn init(class: *Class) callconv(.c) void {
            gio.Application.virtual_methods.activate.implement(class, &activateImpl);
        }
    };

    const Self = @This();

    fn register_accel(self: *Self, name: []const u8, code: c_uint) void {
        const accel = gtk.acceleratorName(code, .{});
        defer std.c.free(accel);

        const accels = [_]?[*:0]const u8{ accel, null };

        const prefix = "win.";

        const qualified_name = std.mem.joinZ(cator, "", &[_][]const u8{ prefix, name }) catch unreachable;
        defer cator.free(qualified_name);

        const accel_slice = accels[0 .. accels.len - 1 :null];

        // Note: at the time of writing, we need to check out a development branch of
        // zig-gobject for setAccelsForAction to be usable.
        gtk.Application.setAccelsForAction(self.as(gtk.Application), qualified_name, accel_slice);
    }

    fn bind_instruction_to_key(app: *StedApp, win: *StedWindow, comptime instr: instruction, keycode: c_uint) void {
        // #. Use Zig introspection to get the name of the instruction as a run time value.

        const union_info = switch (@typeInfo(instruction)) {
            .@"union" => |x| x,
            else => unreachable,
        };

        const name = inline for (union_info.fields) |fld| {
            if (instr == @field(instruction, fld.name)) {
                break fld.name;
            }
        } else unreachable;

        // #. Add an action.

        const local_module = struct {
            fn perform(self: *StedWindow) void {
                self.srcprg.cursor.perform(instr);

                self.refresh() catch unreachable;
            }
        };

        win.addAction(local_module.perform, name);

        // #. Bind the action to the accelerator.

        app.register_accel(name, keycode);
    }

    fn bind_win_method_to_key(
        app: *Self,
        win: *StedWindow,
        comptime method_name: [:0]const u8,
        keycode: c_uint,
    ) void {
        const method = @field(StedWindow, method_name);

        win.addAction(method, method_name);
        app.register_accel(method_name, keycode);
    }
};
