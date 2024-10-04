const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const sfml = @import("sfml");

const SfmlBackend = @This();
pub const Context = *SfmlBackend;

pub const InitOptions = struct {
    /// The allocator used for temporary allocations used during init()
    allocator: std.mem.Allocator,
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[:0]const u8 = null,
};

pub fn createWindow(options: InitOptions) void {
    _ = options; // autofix
    //c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE);
    //if (options.vsync) {
    //    c.SetConfigFlags(c.FLAG_VSYNC_HINT);
    //}

    //c.InitWindow(@as(c_int, @intFromFloat(options.size.w)), @as(c_int, @intFromFloat(options.size.h)), options.title);

    //if (options.icon) |image_bytes| {
    //    const icon = c.LoadImageFromMemory(".png", image_bytes.ptr, @intCast(image_bytes.len));
    //    c.SetWindowIcon(icon);
    //}

    //if (options.min_size) |min| {
    //    c.SetWindowMinSize(@intFromFloat(min.w), @intFromFloat(min.h));
    //}
    //if (options.max_size) |max| {
    //    c.SetWindowMaxSize(@intFromFloat(max.w), @intFromFloat(max.h));
    //}
}
