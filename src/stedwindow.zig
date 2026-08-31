const std = @import("std");
const Allocator = std.mem.Allocator;

const adw = @import("adw");
const gdk = @import("gdk");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const pango = @import("pango");

const Callback = @import("Callback.zig");
const commands = @import("commands.zig");
const Core = @import("Core.zig");
const Frame = @import("Frame.zig");
const key_registry = @import("key_registry.zig");
const shortcuts = @import("shortcuts.zig");
const Srcprg = @import("srcprg.zig").Srcprg;
const StedApp = @import("stedapp.zig").StedApp;
const ThreadCursor = @import("ThreadCursor.zig");
const instruction = ThreadCursor.instruction;
const Tree = @import("Tree.zig");
const ui_layout = @import("ui_layout.zig");

pub const StedWindow = extern struct {
    parent_instance: Parent,
    core: *Core,

    pub const Parent = adw.ApplicationWindow;

    pub fn as(app: *StedWindow, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const getGObjectType = gobject.ext.defineClass(StedWindow, .{
        .classInit = Class.init,
        .parent_class = &Class.parent,
    });

    fn finalizeImpl(win: *StedWindow) callconv(.c) void {
        win.deinit();

        gobject.Object.virtual_methods.finalize.call(Class.parent, win.as(Parent));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = StedWindow;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.finalize.implement(class, &finalizeImpl);
        }
    };

    pub fn new(app: *StedApp) !*StedWindow {
        const win = gobject.ext.newInstance(StedWindow, .{
            .application = app,
        });

        win.as(gtk.Window).setTitle("Sted");

        const text_view = gtk.TextView.new();
        text_view.setEditable(0);
        text_view.setCursorVisible(0);
        text_view.setMonospace(1);

        win.core = try app.init.gpa.create(Core);
        win.core.* = try Core.new(app.init.*, text_view.getBuffer());

        text_view.as(gtk.Widget).setSizeRequest(
            4 * ui_layout.unit_in_pixels,
            4 * ui_layout.unit_in_pixels,
        );

        const paned = gtk.Paned.new(gtk.Orientation.horizontal);
        paned.setStartChild(text_view.as(gtk.Widget));

        paned.setEndChild(win.core.shortcut_pane.vbox.as(gtk.Widget));

        paned.setResizeStartChild(1);
        paned.setResizeEndChild(0);
        paned.setShrinkStartChild(0);
        paned.setShrinkEndChild(0);

        const toolbar_view = adw.ToolbarView.new();

        toolbar_view.addTopBar(adw.HeaderBar.new().as(gtk.Widget));

        toolbar_view.setContent(paned.as(gtk.Widget));

        win.as(adw.ApplicationWindow).setContent(toolbar_view.as(gtk.Widget));

        win.core.registerKeymapChangeCallbacks();

        key_registry.setUpController(win.core, win.as(gtk.Widget));

        for (commands.all_commands) |*c| {
            const k = key_registry.keyForCommand(c.*);
            if (c.* == .replace) {
                const local_module = struct {
                    fn cb(_: *Core, w: *StedWindow) void {
                        w.replace();
                    }
                };

                const callback = Callback.init(*StedWindow, local_module.cb, win);

                try win.core.bindCommandToCallback(.replace, k, callback);
            } else {
                try win.core.bindInstruction(c, k);
            }
        }

        try win.core.refresh();

        return win;
    }

    const Self = @This();

    fn create_input_dialog(self: *Self) !*adw.Dialog {
        const box = gtk.Box.new(gtk.Orientation.vertical, 0);

        const dialog = adw.Dialog.new();
        dialog.setChild(box.as(gtk.Widget));
        dialog.setFollowsContentSize(1);
        dialog.setPresentationMode(adw.DialogPresentationMode.floating);

        const offers = self.core.srcprg.cursor.cursor_pos.getOffers();

        for (offers) |offer| {
            const button = gtk.Button.newWithMnemonic(offer.name);
            box.append(button.as(gtk.Widget));

            switch (offer.rewriter) {
                .from_void => |f| {
                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb_void,
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
                .from_int => |f| {
                    const button_cb = button_cb_generic(u64, int_from_string);

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb,
                        // Note: it would be nice to be more type-safe here.
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
                .from_string => |f| {
                    const button_cb = button_cb_generic([]const u8, string_from_string);

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb,
                        // Note: it would be nice to be more type-safe here.
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
            }
        }

        return dialog;
    }

    pub fn replace(self: *Self) void {
        const dialog = self.create_input_dialog() catch unreachable;

        dialog.present(self.as(gtk.Widget));
    }

    pub fn deinit(_: *Self) void {}
};

fn button_cb_generic(
    param_type: type,
    from_string: fn ([*:0]const u8) param_type,
) fn (button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
    const local_module = struct {
        fn button_cb(button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
            const entry = gtk.Entry.new();

            const entry_cb = entry_cb_generic(param_type, from_string);

            _ = gtk.Entry.signals.activate.connect(
                entry,
                *anyopaque,
                entry_cb,
                user_data,
                .{},
            );

            const dialog_widget = button.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
            const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

            dialog.setChild(entry.as(gtk.Widget));
            _ = entry.as(gtk.Widget).grabFocus();
        }
    };

    return local_module.button_cb;
}

fn entry_cb_generic(
    param_type: type,
    from_string: fn ([*:0]const u8) param_type,
) fn (entry: *gtk.Entry, user_data: *anyopaque) callconv(.c) void {
    const local_module = struct {
        fn entry_cb(entry: *gtk.Entry, user_data: *anyopaque) callconv(.c) void {
            const f: *const fn (*anyopaque, Allocator, param_type) Allocator.Error!void = @ptrCast(user_data);
            const text = entry.getBuffer().getText();

            const text_slice = std.mem.sliceTo(text, 0);

            const arg = from_string(text_slice);

            const dialog_widget = entry.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
            const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

            const win_widget = dialog_widget.getAncestor(StedWindow.getGObjectType()).?;
            const win = gobject.ext.cast(StedWindow, win_widget).?;

            const ptr = win.core.srcprg.cursor.cursor_pos.ptr;
            f(ptr, win.core.init.gpa, arg) catch unreachable;

            win.core.refresh() catch unreachable;

            close_dialog(dialog);
        }
    };

    return local_module.entry_cb;
}

fn int_from_string(text: [*:0]const u8) u64 {
    const text_slice = std.mem.sliceTo(text, 0);

    const num = std.fmt.parseInt(u64, text_slice, 10) catch unreachable;

    return num;
}

fn string_from_string(text: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(text, 0);
}

fn button_cb_void(button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
    const f: *const fn (*anyopaque, Allocator) Allocator.Error!void = @ptrCast(user_data);

    const dialog_widget = button.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
    const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

    const win_widget = dialog_widget.getAncestor(StedWindow.getGObjectType()).?;
    const win = gobject.ext.cast(StedWindow, win_widget).?;

    const ptr = win.core.srcprg.cursor.cursor_pos.ptr;
    f(ptr, win.core.init.gpa) catch unreachable;

    win.core.refresh() catch unreachable;

    close_dialog(dialog);
}

fn close_dialog(d: *adw.Dialog) void {
    const res = d.close();
    if (res != 1) {
        @panic("Failed to close dialog");
    }
}
