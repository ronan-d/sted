const std = @import("std");
const cator = std.heap.c_allocator;

const Allocator = std.mem.Allocator;

const adw = @import("adw");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const sourceview = @import("gtksourceview");
const pango = @import("pango");

const StedApp = @import("stedapp.zig").StedApp;

const Frame = @import("Frame.zig");

const Srcprg = @import("srcprg.zig").Srcprg;

const Tree = @import("Tree.zig");

const Renderer = extern struct {
    buffer: *gtk.TextBuffer,
    tag: *gtk.TextTag,

    const Self = @This();

    pub fn render_frame(self: Self, frame: Frame) void {
        const with_sentinel: [:0]const u8 = frame.text[0 .. frame.text.len - 1 :0];

        self.buffer.setText(with_sentinel, @intCast(with_sentinel.len));

        // TODO: handle more than one line of code.
        var start: gtk.TextIter = undefined;
        {
            const res = self.buffer.getIterAtLineIndex(&start, 0, @intCast(frame.start_offset));
            if (res != 1) {
                @panic("unexpected string index error");
            }
        }

        var end: gtk.TextIter = undefined;
        {
            const res = self.buffer.getIterAtLineIndex(&end, 0, @intCast(frame.end_offset));
            if (res != 1) {
                @panic("unexpected string index error");
            }
        }

        self.buffer.applyTag(self.tag, &start, &end);
    }
};

pub const StedWindow = extern struct {
    parent_instance: Parent,
    renderer: Renderer,
    srcprg: *Srcprg,

    pub const Parent = adw.ApplicationWindow;

    fn init(self: *StedWindow, _: *Class) callconv(.c) void {
        self.as(gtk.Window).setTitle("hello");
        self.as(gtk.Window).setDefaultSize(200, 200);

        const text_view = sourceview.View.new();
        text_view.as(gtk.TextView).setEditable(0);
        text_view.as(gtk.TextView).setCursorVisible(0);
        text_view.as(gtk.TextView).setMonospace(0);

        const toolbar_view = adw.ToolbarView.new();

        toolbar_view.addTopBar(adw.HeaderBar.new().as(gtk.Widget));

        toolbar_view.setContent(text_view.as(gtk.Widget));

        self.as(adw.ApplicationWindow).setContent(toolbar_view.as(gtk.Widget));

        const last_arg: ?*anyopaque = null;

        const buffer = text_view.as(gtk.TextView).getBuffer();

        self.renderer = Renderer{
            .buffer = buffer,
            .tag = buffer.createTag(
                "cursor-tag",
                "underline",
                @intFromEnum(pango.Underline.single),
                last_arg,
            ),
        };

        self.srcprg = cator.create(Srcprg) catch unreachable;
        self.srcprg.* = Srcprg.new() catch unreachable;

        const frame = self.srcprg.render() catch unreachable;
        self.renderer.render_frame(frame);
    }

    fn dispose(self: *StedWindow) callconv(.c) void {
        cator.destroy(self.srcprg);

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn as(app: *StedWindow, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const getGObjectType = gobject.ext.defineClass(StedWindow, .{ .instanceInit = &init });

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = StedWindow;
    };

    pub fn new(app: *StedApp) *StedWindow {
        return gobject.ext.newInstance(StedWindow, .{
            .application = app,
        });
    }

    const Self = @This();

    fn create_input_dialog(self: *Self) !*adw.Dialog {
        const box = gtk.Box.new(gtk.Orientation.vertical, 0);

        const dialog = adw.Dialog.new();
        dialog.setChild(box.as(gtk.Widget));
        dialog.setFollowsContentSize(1);
        dialog.setPresentationMode(adw.DialogPresentationMode.floating);

        const offers = self.srcprg.cursor.cursor_pos.get_offers();
        for (offers) |offer| {
            switch (offer.rewriter) {
                .from_void => |f| {
                    const button = gtk.Button.newWithMnemonic(offer.name);

                    const local_module = struct {
                        pub const SignalData = struct {
                            rewriter: *const fn (*anyopaque) Allocator.Error!void,
                            // The opaque pointer that's inside the `Tree`.
                            win: *StedWindow,
                            dialog: *adw.Dialog,
                        };

                        pub fn destroy_data(p: *SignalData) callconv(.c) void {
                            cator.destroy(p);
                        }

                        pub fn cb(_: *gtk.Button, signal_data: *SignalData) callconv(.c) void {
                            const ptr = signal_data.win.srcprg.cursor.cursor_pos.ptr;
                            signal_data.rewriter(ptr) catch unreachable;

                            signal_data.win.refresh() catch unreachable;

                            {
                                const res = signal_data.dialog.close();
                                if (res != 1) {
                                    @panic("Failed to close dialog");
                                }
                            }
                        }
                    };

                    const signal_data = try cator.create(local_module.SignalData);

                    signal_data.* = .{
                        .rewriter = f,
                        .win = self,
                        .dialog = dialog,
                    };

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *local_module.SignalData,
                        local_module.cb,
                        signal_data,
                        .{ .destroyData = local_module.destroy_data },
                    );

                    box.append(button.as(gtk.Widget));
                },
                .from_int => |f| {
                    const button = gtk.Button.newWithMnemonic(offer.name);

                    box.append(button.as(gtk.Widget));

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb_int,
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
                // WIP partial support for now
                else => {},
            }
        }

        return dialog;
    }

    pub fn addAction(
        self: *Self,
        comptime cb: *const fn (*Self) void,
        name: [:0]const u8,
    ) void {
        const local_module = struct {
            pub fn cb_wrapper(
                _: *gio.SimpleAction,
                _: *glib.Variant,
                p_user_data: ?*anyopaque,
            ) callconv(.c) void {
                const p: *Self = @ptrCast(@alignCast(p_user_data));

                cb(p);
            }
        };

        const entry: gio.ActionEntry = .{
            .f_name = name,
            .f_activate = local_module.cb_wrapper,
            .f_parameter_type = null,
            .f_change_state = null,
            .f_state = null,
            .f_padding = undefined,
        };

        const intermediate_array = [_]gio.ActionEntry{entry};

        self.as(gio.ActionMap).addActionEntries(
            &intermediate_array,
            intermediate_array.len,
            @ptrCast(self),
        );
    }

    pub fn replace(self: *Self) void {
        const dialog = self.create_input_dialog() catch unreachable;

        dialog.present(self.as(gtk.Widget));
    }

    pub fn refresh(self: *Self) !void {
        self.renderer.render_frame(try self.srcprg.render());
    }
};

fn button_cb_int(
    button: *gtk.Button,
    user_data: *anyopaque,
) callconv(.c) void {
    const entry = gtk.Entry.new();

    _ = gtk.Entry.signals.activate.connect(
        entry,
        *anyopaque,
        entry_cb_int,
        user_data,
        .{},
    );

    const dialog_widget = button.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
    const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

    dialog.setChild(entry.as(gtk.Widget));
    _ = entry.as(gtk.Widget).grabFocus();
}

fn entry_cb_int(
    entry: *gtk.Entry,
    user_data: *anyopaque,
) callconv(.c) void {
    const f: *const fn (*anyopaque, u64) Allocator.Error!void = @ptrCast(user_data);
    const text = entry.getBuffer().getText();

    const text_slice = std.mem.sliceTo(text, 0);

    const num = std.fmt.parseInt(u64, text_slice, 10) catch unreachable;

    const dialog_widget = entry.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
    const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

    const win_widget = dialog_widget.getAncestor(StedWindow.getGObjectType()).?;
    const win = gobject.ext.cast(StedWindow, win_widget).?;

    const ptr = win.srcprg.cursor.cursor_pos.ptr;
    f(ptr, num) catch unreachable;

    win.refresh() catch unreachable;

    {
        const res = dialog.close();
        if (res != 1) {
            @panic("Failed to close dialog");
        }
    }
}
