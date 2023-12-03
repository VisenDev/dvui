const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const TextLayoutWidget = @This();

pub var defaults: Options = .{
    .name = "TextLayout",
    .margin = Rect.all(4),
    .padding = Rect.all(4),
    .background = true,
    .min_size_content = .{ .w = 250 },
};

pub const InitOptions = struct {
    selection: ?*Selection = null,
    break_lines: bool = true,
};

pub const Selection = struct {
    cursor: usize = 0,
    start: usize = 0,
    end: usize = 0,

    pub fn empty(self: *Selection) bool {
        return self.start == self.end;
    }

    pub fn incCursor(self: *Selection) void {
        self.cursor += 1;
    }

    pub fn decCursor(self: *Selection) void {
        if (self.cursor <= 0) {
            self.cursor = 0;
        } else self.cursor -= 1;
    }

    pub fn incStart(self: *Selection) void {
        self.start += 1;
    }

    pub fn decStart(self: *Selection) void {
        if (self.start <= 0) {
            self.start = 0;
        } else self.start -= 1;
    }

    pub fn incEnd(self: *Selection) void {
        self.end += 1;
    }

    pub fn decEnd(self: *Selection) void {
        if (self.end <= 0) {
            self.end = 0;
        } else self.end -= 1;
    }

    pub fn order(self: *Selection) void {
        if (self.end < self.start) {
            const tmp = self.start;
            self.start = self.end;
            self.end = tmp;
        }
    }
};

wd: WidgetData = undefined,
corners: [4]?Rect = [_]?Rect{null} ** 4,
corners_min_size: [4]?Size = [_]?Size{null} ** 4,
corners_last_seen: ?u8 = null,
insert_pt: Point = Point{},
prevClip: Rect = Rect{},
first_line: bool = true,
break_lines: bool = undefined,

bytes_seen: usize = 0,
selection_in: ?*Selection = null,
selection: *Selection = undefined,
selection_store: Selection = .{},
sel_mouse_down_pt: ?Point = null,
sel_mouse_down_bytes: ?usize = null,
sel_mouse_drag_pt: ?Point = null,
sel_left_right: i32 = 0,
sel_start_r: Rect = .{},
sel_end_r: Rect = .{},
sel_pts: [2]?Point = [2]?Point{ null, null },

cursor_seen: bool = false,
cursor_rect: ?Rect = null,
cursor_updown: i8 = 0, // positive is down
cursor_updown_drag: bool = true,
cursor_updown_pt: ?Point = null,
scroll_to_cursor: bool = false,

touch_editing_done: bool = false,
add_text_done: bool = false,

copy_sel: ?Selection = null,
copy_slice: ?[]u8 = null,

// when this is true and we have focus, show the floating widget with select all, copy, etc.
touch_editing: bool = false,
te_show_draggables: bool = true,
te_show_context_menu: bool = true,
te_focus_on_touchdown: bool = false,
focus_at_start: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TextLayoutWidget {
    const options = defaults.override(opts);
    var self = TextLayoutWidget{ .wd = WidgetData.init(src, .{}, options), .selection_in = init_opts.selection };
    self.break_lines = init_opts.break_lines;
    self.touch_editing = dvui.dataGet(null, self.wd.id, "_touch_editing", bool) orelse false;
    self.te_show_draggables = dvui.dataGet(null, self.wd.id, "_te_show_draggables", bool) orelse true;
    self.te_show_context_menu = dvui.dataGet(null, self.wd.id, "_te_show_context_menu", bool) orelse true;
    self.te_focus_on_touchdown = dvui.dataGet(null, self.wd.id, "_te_focus_on_touchdown", bool) orelse false;

    self.sel_start_r = dvui.dataGet(null, self.wd.id, "_sel_start_r", Rect) orelse .{};
    self.sel_end_r = dvui.dataGet(null, self.wd.id, "_sel_end_r", Rect) orelse .{};

    return self;
}

pub fn install(self: *TextLayoutWidget, focused: bool) !void {
    self.focus_at_start = focused;

    try self.wd.register();
    dvui.parentSet(self.widget());

    if (self.selection_in) |sel| {
        self.selection = sel;
    } else {
        if (dvui.dataGet(null, self.wd.id, "_selection", Selection)) |s| {
            self.selection_store = s;
        }
        self.selection = &self.selection_store;
    }

    if (dvui.dataGet(null, self.wd.id, "_sel_left_right", i32)) |slf| {
        self.sel_left_right = slf;
    }

    if (dvui.captured(self.wd.id)) {
        if (dvui.dataGet(null, self.wd.id, "_sel_mouse_down_bytes", usize)) |p| {
            self.sel_mouse_down_bytes = p;
        }
    }

    if (dvui.dataGet(null, self.wd.id, "_cursor_updown_pt", Point)) |p| {
        self.cursor_updown_pt = p;
        dvui.dataRemove(null, self.wd.id, "_cursor_updown_pt");
        if (dvui.dataGet(null, self.wd.id, "_cursor_updown_drag", bool)) |cud| {
            self.cursor_updown_drag = cud;
        }
    }

    if (dvui.dataGet(null, self.wd.id, "_copy_sel_next_frame", bool) != null) {
        dvui.dataRemove(null, self.wd.id, "_copy_sel_next_frame");
        self.copy_sel = self.selection.*;
    }

    const rs = self.wd.contentRectScale();

    try self.wd.borderAndBackground(.{});

    self.prevClip = dvui.clip(rs.r);

    if (self.touch_editing and self.te_show_draggables and self.focus_at_start and self.wd.visible()) {
        const size = 24;
        {
            var rect = self.sel_start_r;
            rect.y += rect.h; // move to below the line
            const srs = self.screenRectScale(rect);
            rect = dvui.windowRectScale().rectFromScreen(srs.r);
            rect.x -= size;
            rect.w = size;
            rect.h = size;

            var fc = dvui.FloatingWidget.init(@src(), .{ .rect = rect });
            try fc.install();

            const fcrs = fc.wd.rectScale();
            var evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = fc.wd.id, .r = fcrs.r }))
                    continue;

                if (e.evt == .mouse) {
                    const me = e.evt.mouse;
                    if (me.action == .press and me.button.touch()) {
                        dvui.captureMouse(fc.wd.id);
                        self.te_show_context_menu = false;
                    } else if (me.action == .release and me.button.touch()) {
                        dvui.captureMouse(null);
                    } else if (me.action == .motion and dvui.captured(fc.wd.id)) {
                        const corner = me.p.plus(.{ .x = size * 0.7 * dvui.windowNaturalScale(), .y = -size * 0.7 * dvui.windowNaturalScale() });
                        self.sel_pts[0] = self.wd.contentRectScale().pointFromScreen(corner);
                        self.sel_pts[1] = self.sel_end_r.topleft().plus(.{ .y = self.sel_end_r.h / 2 });
                        //std.debug.print("sel_pts {?any} {?any}\n", .{ self.sel_pts[0], self.sel_pts[1] });
                    }
                }
            }

            try dvui.pathAddPoint(.{ .x = fcrs.r.x + fcrs.r.w, .y = fcrs.r.y });
            try dvui.pathAddArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);
            try dvui.pathFillConvex(dvui.themeGet().color_fill_control);

            try dvui.pathAddPoint(.{ .x = fcrs.r.x + fcrs.r.w, .y = fcrs.r.y });
            try dvui.pathAddArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);
            try dvui.pathStroke(true, 1.0, .none, self.wd.options.color(.border));

            fc.deinit();
        }

        {
            var rect = self.sel_end_r;
            rect.y += rect.h; // move to below the line
            const srs = self.screenRectScale(rect);
            rect = dvui.windowRectScale().rectFromScreen(srs.r);
            rect.w = size;
            rect.h = size;

            var fc = dvui.FloatingWidget.init(@src(), .{ .rect = rect });
            try fc.install();
            const fcrs = fc.wd.rectScale();
            var evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = fc.wd.id, .r = fcrs.r }))
                    continue;

                if (e.evt == .mouse) {
                    const me = e.evt.mouse;
                    if (me.action == .press and me.button.touch()) {
                        dvui.captureMouse(fc.wd.id);
                        self.te_show_context_menu = false;
                    } else if (me.action == .release and me.button.touch()) {
                        dvui.captureMouse(null);
                    } else if (me.action == .motion and dvui.captured(fc.wd.id)) {
                        const corner = me.p.plus(.{ .x = -size * 0.7 * dvui.windowNaturalScale(), .y = -size * 0.7 * dvui.windowNaturalScale() });
                        self.sel_pts[1] = self.wd.contentRectScale().pointFromScreen(corner);
                        if (self.sel_pts[0] == null) {
                            self.sel_pts[0] = self.sel_start_r.topleft().plus(.{ .y = self.sel_start_r.h / 2 });
                        }
                    }
                }
            }

            try dvui.pathAddPoint(.{ .x = fcrs.r.x, .y = fcrs.r.y });
            try dvui.pathAddArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);
            try dvui.pathFillConvex(dvui.themeGet().color_fill_control);

            try dvui.pathAddPoint(.{ .x = fcrs.r.x, .y = fcrs.r.y });
            try dvui.pathAddArc(.{ .x = fcrs.r.x + fcrs.r.w / 2, .y = fcrs.r.y + fcrs.r.h / 2 }, fcrs.r.w / 2, std.math.pi, 0, true);
            try dvui.pathStroke(true, 1.0, .none, self.wd.options.color(.border));

            fc.deinit();
        }
    }
}

pub fn format(self: *TextLayoutWidget, comptime fmt: []const u8, args: anytype, opts: Options) !void {
    var cw = dvui.currentWindow();
    const l = try std.fmt.allocPrint(cw.arena, fmt, args);
    try self.addText(l, opts);
}

pub fn addText(self: *TextLayoutWidget, text: []const u8, opts: Options) !void {
    const options = self.wd.options.override(opts);
    const msize = try options.fontGet().textSize("m");
    const line_height = try options.fontGet().lineHeight();
    var txt = text;

    const rect = self.wd.contentRect();
    var container_width = rect.w;
    if (container_width == 0) {
        // if we are not being shown at all, probably this is the first
        // frame for us and we should calculate our min height assuming we
        // get at least our min width

        // do this dance so we aren't repeating the contentRect
        // calculations here
        const given_width = self.wd.rect.w;
        self.wd.rect.w = @max(given_width, self.wd.min_size.w);
        container_width = self.wd.contentRect().w;
        self.wd.rect.w = given_width;
    }

    while (txt.len > 0) {
        var linestart: f32 = 0;
        var linewidth = container_width;
        var width = linewidth - self.insert_pt.x;
        var width_after: f32 = 0;
        for (self.corners, 0..) |corner, i| {
            if (corner) |cor| {
                if (@max(cor.y, self.insert_pt.y) < @min(cor.y + cor.h, self.insert_pt.y + line_height)) {
                    linewidth -= cor.w;
                    if (linestart == cor.x) {
                        // used below - if we moved over for a widget, we
                        // can drop to the next line expecting more room
                        // later
                        linestart = (cor.x + cor.w);
                    }

                    if (self.insert_pt.x <= (cor.x + cor.w)) {
                        width -= cor.w;
                        if (self.insert_pt.x >= cor.x) {
                            // widget on left side, skip over it
                            self.insert_pt.x = (cor.x + cor.w);
                        } else {
                            // widget on right side, need to add width to min_size below
                            width_after = self.corners_min_size[i].?.w;
                        }
                    }
                }
            }
        }

        var end: usize = undefined;

        // get slice of text that fits within width or ends with newline
        var s = try options.fontGet().textSizeEx(txt, if (self.break_lines) width else null, &end, .before);

        // ensure we always get at least 1 codepoint so we make progress
        if (end == 0) {
            end = std.unicode.utf8ByteSequenceLength(txt[0]) catch 1;
            s = try options.fontGet().textSize(txt[0..end]);
        }

        const newline = (txt[end - 1] == '\n');

        //std.debug.print("{d} 1 txt to {d} \"{s}\"\n", .{ container_width, end, txt[0..end] });

        // if we are boxed in too much by corner widgets drop to next line
        if (self.break_lines and s.w > width and linewidth < container_width) {
            self.insert_pt.y += line_height;
            self.insert_pt.x = 0;
            continue;
        }

        // try to break on space if:
        // - slice ended due to width (not newline)
        // - linewidth is long enough (otherwise too narrow to break on space)
        if (self.break_lines and end < txt.len and !newline and linewidth > (10 * msize.w)) {
            const space: []const u8 = &[_]u8{' '};
            // now we are under the length limit but might be in the middle of a word
            // look one char further because we might be right at the end of a word
            const spaceIdx = std.mem.lastIndexOfLinear(u8, txt[0 .. end + 1], space);
            if (spaceIdx) |si| {
                end = si + 1;
                s = try options.fontGet().textSize(txt[0..end]);
            } else if (self.insert_pt.x > linestart) {
                // can't fit breaking on space, but we aren't starting at the left edge
                // so drop to next line
                self.insert_pt.y += line_height;
                self.insert_pt.x = 0;
                continue;
            }
        }

        // now we know the line of text we are about to render
        // see if selection needs to be updated

        // if the text changed our selection might be in the middle of utf8 chars, so fix it up
        while (self.selection.start >= self.bytes_seen and self.selection.start < self.bytes_seen + end and txt[self.selection.start - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.start += 1;
        }

        while (self.selection.cursor >= self.bytes_seen and self.selection.cursor < self.bytes_seen + end and txt[self.selection.cursor - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.cursor += 1;
        }

        while (self.selection.end >= self.bytes_seen and self.selection.end < self.bytes_seen + end and txt[self.selection.end - self.bytes_seen] & 0xc0 == 0x80) {
            self.selection.end += 1;
        }

        if (self.sel_left_right != 0 and !self.cursor_seen and self.selection.cursor <= self.bytes_seen + end) {
            while (self.sel_left_right < 0 and self.selection.cursor > self.bytes_seen) {
                var move_start: bool = undefined;
                if (self.selection.cursor == self.selection.start) {
                    move_start = true;
                } else {
                    move_start = false;
                }

                // move cursor one utf8 char left
                self.selection.cursor -|= 1;
                while (self.selection.cursor > self.bytes_seen and txt[self.selection.cursor - self.bytes_seen] & 0xc0 == 0x80) {
                    // in the middle of a multibyte char
                    self.selection.cursor -|= 1;
                }

                if (move_start) {
                    self.selection.start = self.selection.cursor;
                } else {
                    self.selection.end = self.selection.cursor;
                }
                self.sel_left_right += 1;
            }

            if (self.sel_left_right < 0 and self.selection.cursor == 0) {
                self.sel_left_right = 0;
            }

            while (self.sel_left_right > 0 and self.selection.cursor < (self.bytes_seen + end)) {
                var move_start: bool = undefined;
                if (self.selection.cursor == self.selection.end) {
                    move_start = false;
                } else {
                    move_start = true;
                }

                // move cursor one utf8 char right
                self.selection.cursor += std.unicode.utf8ByteSequenceLength(txt[self.selection.cursor - self.bytes_seen]) catch 1;

                if (move_start) {
                    self.selection.start = self.selection.cursor;
                } else {
                    self.selection.end = self.selection.cursor;
                }
                self.sel_left_right -= 1;
            }
        }

        if (self.sel_mouse_down_pt) |p| {
            const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
            if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                // point is before this text
                self.sel_mouse_down_bytes = self.bytes_seen;
                self.selection.cursor = self.sel_mouse_down_bytes.?;
                self.selection.start = self.sel_mouse_down_bytes.?;
                self.selection.end = self.sel_mouse_down_bytes.?;
                self.sel_mouse_down_pt = null;
            } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                // point is in this text
                const how_far = p.x - rs.x;
                var pt_end: usize = undefined;
                _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                self.sel_mouse_down_bytes = self.bytes_seen + pt_end;
                self.selection.cursor = self.sel_mouse_down_bytes.?;
                self.selection.start = self.sel_mouse_down_bytes.?;
                self.selection.end = self.sel_mouse_down_bytes.?;
                self.sel_mouse_down_pt = null;
            } else {
                if (newline and p.y < (rs.y + rs.h)) {
                    // point is after this text on this same horizontal line
                    self.sel_mouse_down_bytes = self.bytes_seen + end - 1;
                    self.sel_mouse_down_pt = null;
                } else {
                    // point is after this text, but we might not get anymore
                    self.sel_mouse_down_bytes = self.bytes_seen + end;
                }
                self.selection.cursor = self.sel_mouse_down_bytes.?;
                self.selection.start = self.sel_mouse_down_bytes.?;
                self.selection.end = self.sel_mouse_down_bytes.?;
            }
            self.scroll_to_cursor = true;
        }

        if (self.sel_mouse_drag_pt) |p| {
            const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
            if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                // point is before this text
                self.selection.cursor = self.bytes_seen;
                self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen);
                self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen);
                self.sel_mouse_drag_pt = null;
            } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                // point is in this text
                const how_far = p.x - rs.x;
                var pt_end: usize = undefined;
                _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                self.selection.cursor = self.bytes_seen + pt_end;
                self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen + pt_end);
                self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen + pt_end);
                self.sel_mouse_drag_pt = null;
            } else {
                // point is after this text, but we might not get anymore
                self.selection.cursor = self.bytes_seen + end;
                self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen + end);
                self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen + end);
            }

            // don't set scroll_to_cursor here because when we are dragging
            // we are already doing a scroll_drag in processEvent
        }

        if (self.cursor_updown == 0) {
            if (self.cursor_updown_pt) |p| {
                const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                    // point is before this text
                    if (self.cursor_updown_drag) {
                        if (self.selection.cursor == self.selection.start) {
                            self.selection.cursor = self.bytes_seen;
                            self.selection.start = self.bytes_seen;
                        } else {
                            self.selection.cursor = self.bytes_seen;
                            self.selection.end = self.bytes_seen;
                        }
                    } else {
                        self.selection.cursor = self.bytes_seen;
                        self.selection.start = self.bytes_seen;
                        self.selection.end = self.bytes_seen;
                    }
                    self.cursor_updown_pt = null;
                    self.selection.order();
                    self.scroll_to_cursor = true;
                } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                    // point is in this text
                    const how_far = p.x - rs.x;
                    var pt_end: usize = undefined;
                    _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                    if (self.cursor_updown_drag) {
                        if (self.selection.cursor == self.selection.start) {
                            self.selection.cursor = self.bytes_seen + pt_end;
                            self.selection.start = self.bytes_seen + pt_end;
                        } else {
                            self.selection.cursor = self.bytes_seen + pt_end;
                            self.selection.end = self.bytes_seen + pt_end;
                        }
                    } else {
                        self.selection.cursor = self.bytes_seen + pt_end;
                        self.selection.start = self.bytes_seen + pt_end;
                        self.selection.end = self.bytes_seen + pt_end;
                    }
                    self.cursor_updown_pt = null;
                    self.selection.order();
                    self.scroll_to_cursor = true;
                } else {
                    if (newline and p.y < (rs.y + rs.h)) {
                        // point is after this text on this same horizontal line
                        if (self.cursor_updown_drag) {
                            if (self.selection.cursor == self.selection.start) {
                                self.selection.cursor = self.bytes_seen + end - 1;
                                self.selection.start = self.bytes_seen + end - 1;
                            } else {
                                self.selection.cursor = self.bytes_seen + end - 1;
                                self.selection.end = self.bytes_seen + end - 1;
                            }
                        } else {
                            self.selection.cursor = self.bytes_seen + end - 1;
                            self.selection.start = self.bytes_seen + end - 1;
                            self.selection.end = self.bytes_seen + end - 1;
                        }
                        self.cursor_updown_pt = null;
                    } else {
                        // point is after this text, but we might not get anymore
                        if (self.cursor_updown_drag) {
                            if (self.selection.cursor == self.selection.start) {
                                self.selection.cursor = self.bytes_seen + end;
                                self.selection.start = self.bytes_seen + end;
                            } else {
                                self.selection.cursor = self.bytes_seen + end;
                                self.selection.end = self.bytes_seen + end;
                            }
                        } else {
                            self.selection.cursor = self.bytes_seen + end;
                            self.selection.start = self.bytes_seen + end;
                            self.selection.end = self.bytes_seen + end;
                        }
                    }
                    self.selection.order();
                    self.scroll_to_cursor = true;
                }
            }
        }

        if (self.sel_pts[0] != null or self.sel_pts[1] != null) {
            var sel_bytes = [2]?usize{ null, null };
            for (self.sel_pts, 0..) |maybe_pt, i| {
                if (maybe_pt) |p| {
                    const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                    if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                        // point is before this text
                        sel_bytes[i] = self.bytes_seen;
                        self.sel_pts[i] = null;
                    } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                        // point is in this text
                        const how_far = p.x - rs.x;
                        var pt_end: usize = undefined;
                        _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                        sel_bytes[i] = self.bytes_seen + pt_end;
                        self.sel_pts[i] = null;
                    } else {
                        if (newline and p.y < (rs.y + rs.h)) {
                            // point is after this text on this same horizontal line
                            sel_bytes[i] = self.bytes_seen + end - 1;
                            self.sel_pts[i] = null;
                        } else {
                            // point is after this text, but we might not get anymore
                            sel_bytes[i] = self.bytes_seen + end;
                        }
                    }
                }
            }

            //std.debug.print("sel_bytes {?d} {?d}\n", .{ sel_bytes[0], sel_bytes[1] });

            // start off getting both, then maybe getting one
            if (sel_bytes[0] != null and sel_bytes[1] != null) {
                self.selection.cursor = @min(sel_bytes[0].?, sel_bytes[1].?);
                self.selection.start = @min(sel_bytes[0].?, sel_bytes[1].?);
                self.selection.end = @max(sel_bytes[0].?, sel_bytes[1].?);

                // changing touch selection, need to refresh to move draggables
                dvui.refresh(null, @src(), self.wd.id);
            } else if (sel_bytes[0] != null or sel_bytes[1] != null) {
                self.selection.end = sel_bytes[0] orelse sel_bytes[1].?;
            }
        }

        // record screen position of selection for touch editing (use s for
        // height in case we are calling textSize with an empty slice)
        var do_sel_start_r = false;
        var new_start_r: Rect = undefined;
        var do_sel_end_r = false;
        var new_end_r: Rect = undefined;
        if (self.selection.start >= self.bytes_seen and self.selection.start <= self.bytes_seen + end) {
            do_sel_start_r = true;
            const start_off = try options.fontGet().textSize(txt[0..self.selection.start -| self.bytes_seen]);
            new_start_r = .{ .x = self.insert_pt.x + start_off.w, .y = self.insert_pt.y, .w = 0, .h = s.h };
        }

        if (self.selection.end >= self.bytes_seen and self.selection.end <= self.bytes_seen + end) {
            do_sel_end_r = true;
            const end_off = try options.fontGet().textSize(txt[0..self.selection.end -| self.bytes_seen]);
            new_end_r = .{ .x = self.insert_pt.x + end_off.w, .y = self.insert_pt.y, .w = 0, .h = s.h };
        }

        const rs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = width, .h = @max(0, rect.h - self.insert_pt.y) });
        //std.debug.print("renderText: {} {s}\n", .{ rs.r, txt[0..end] });
        const rtxt = if (newline) txt[0 .. end - 1] else txt[0..end];
        try dvui.renderText(.{
            .font = options.fontGet(),
            .text = rtxt,
            .rs = rs,
            .color = options.color(.text),
            .sel_start = self.selection.start -| self.bytes_seen,
            .sel_end = self.selection.end -| self.bytes_seen,
            .sel_color = options.color(.fill),
            .sel_color_bg = options.color(.accent),
        });

        if (!self.cursor_seen and self.selection.cursor < self.bytes_seen + end) {
            self.cursor_seen = true;
            const size = try options.fontGet().textSize(txt[0 .. self.selection.cursor - self.bytes_seen]);
            const cr = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 1, .h = try options.fontGet().lineHeight() };

            if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
                const cr_new = cr.add(.{ .y = @as(f32, @floatFromInt(self.cursor_updown)) * try options.fontGet().lineHeight() });
                self.cursor_updown_pt = cr_new.topleft().plus(.{ .y = cr_new.h / 2 });

                // might have already passed, so need to go again next frame
                dvui.refresh(null, @src(), self.wd.id);

                var scrollto = Event{ .evt = .{ .scroll_to = .{
                    .screen_rect = self.screenRectScale(cr_new).r,
                } } };
                self.processEvent(&scrollto, true);
            }

            if (self.scroll_to_cursor) {
                var scrollto = Event{ .evt = .{ .scroll_to = .{
                    .screen_rect = self.screenRectScale(cr.outset(self.wd.options.paddingGet())).r,
                } } };
                self.processEvent(&scrollto, true);
            }

            if (self.selection.start == self.selection.end) {
                self.cursor_rect = cr;
            }
        }

        // even if we don't actually render, need to update insert_pt and minSize
        // like we did because our parent might size based on that (might be in a
        // scroll area)
        self.insert_pt.x += s.w;
        const size = self.wd.padSize(.{ .w = self.insert_pt.x, .h = self.insert_pt.y + s.h });
        if (!self.break_lines) {
            self.wd.min_size.w = @max(self.wd.min_size.w, size.w + width_after);
        }
        self.wd.min_size.h = @max(self.wd.min_size.h, size.h);

        if (self.copy_sel) |sel| {
            // we are copying to clipboard
            if (sel.start < self.bytes_seen + end) {
                // need to copy some
                const cstart = if (sel.start < self.bytes_seen) 0 else (sel.start - self.bytes_seen);
                const cend = if (sel.end < self.bytes_seen + end) (sel.end - self.bytes_seen) else end;

                // initialize or realloc
                if (self.copy_slice) |slice| {
                    const old_len = slice.len;
                    self.copy_slice = try dvui.currentWindow().arena.realloc(slice, slice.len + (cend - cstart));
                    @memcpy(self.copy_slice.?[old_len..], txt[cstart..cend]);
                } else {
                    self.copy_slice = try dvui.currentWindow().arena.dupe(u8, txt[cstart..cend]);
                }

                // push to clipboard if done
                if (sel.end <= self.bytes_seen + end) {
                    try dvui.clipboardTextSet(self.copy_slice.?);

                    self.copy_sel = null;
                    dvui.currentWindow().arena.free(self.copy_slice.?);
                    self.copy_slice = null;
                }
            }
        }

        // discard bytes we've dealt with
        txt = txt[end..];
        self.bytes_seen += end;

        // move insert_pt to next line if we have more text
        if (txt.len > 0 or newline) {
            self.insert_pt.y += line_height;
            self.insert_pt.x = 0;
            if (newline) {
                const newline_size = self.wd.padSize(.{ .w = self.insert_pt.x, .h = self.insert_pt.y + s.h });
                if (!self.break_lines) {
                    self.wd.min_size.w = @max(self.wd.min_size.w, newline_size.w);
                }
                self.wd.min_size.h = @max(self.wd.min_size.h, newline_size.h);
            }
        }

        if (do_sel_start_r) {
            if (newline and (self.selection.start == self.bytes_seen)) {
                new_start_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 0, .h = s.h };
            }
            if (!self.sel_start_r.equals(new_start_r)) {
                dvui.refresh(null, @src(), self.wd.id);
            }
            self.sel_start_r = new_start_r;
        }

        if (do_sel_end_r) {
            if (newline and (self.selection.end == self.bytes_seen)) {
                new_end_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 0, .h = s.h };
            }
            if (!self.sel_end_r.equals(new_end_r)) {
                dvui.refresh(null, @src(), self.wd.id);
            }
            self.sel_end_r = new_end_r;
        }

        if (self.wd.options.rect != null) {
            // we were given a rect, so don't need to calculate our min height,
            // so stop as soon as we run off the end of the clipping region
            // this helps for performance
            const nextrs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y });
            if (nextrs.r.y > (dvui.clipGet().y + dvui.clipGet().h)) {
                //std.debug.print("stopping after: {s}\n", .{rtxt});
                break;
            }
        }
    }
}

pub fn addTextDone(self: *TextLayoutWidget, opts: Options) !void {
    self.add_text_done = true;

    if (self.copy_sel) |_| {
        // we are copying to clipboard and never stopped
        try dvui.clipboardTextSet(self.copy_slice orelse "");

        self.copy_sel = null;
        if (self.copy_slice) |cs| {
            dvui.currentWindow().arena.free(cs);
        }
        self.copy_slice = null;
    }

    // if we had mouse/keyboard interaction, need to handle things if addText never gets called
    if (self.sel_mouse_down_pt) |_| {
        self.sel_mouse_down_bytes = self.bytes_seen;
    }

    if (self.selection.start > self.bytes_seen or self.bytes_seen == 0) {
        const options = self.wd.options.override(opts);
        self.sel_start_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .h = try options.fontGet().lineHeight() };
        if (self.selection.start > self.bytes_seen) {
            dvui.refresh(null, @src(), self.wd.id);
        }
    }

    if (self.selection.end > self.bytes_seen or self.bytes_seen == 0) {
        const options = self.wd.options.override(opts);
        self.sel_end_r = .{ .x = self.insert_pt.x, .y = self.insert_pt.y, .h = try options.fontGet().lineHeight() };
        if (self.selection.end > self.bytes_seen) {
            dvui.refresh(null, @src(), self.wd.id);
        }
    }

    self.selection.cursor = @min(self.selection.cursor, self.bytes_seen);
    self.selection.start = @min(self.selection.start, self.bytes_seen);
    self.selection.end = @min(self.selection.end, self.bytes_seen);

    if (self.sel_left_right > 0 and self.selection.cursor == self.bytes_seen) {
        self.sel_left_right = 0;
    } else if (self.sel_left_right < 0 and self.selection.cursor == 0) {
        self.sel_left_right = 0;
    }

    if (!self.cursor_seen) {
        self.cursor_seen = true;
        self.selection.cursor = self.bytes_seen;

        const options = self.wd.options.override(opts);
        const cr = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = 1, .h = try options.fontGet().lineHeight() };

        if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
            const cr_new = cr.add(.{ .y = @as(f32, @floatFromInt(self.cursor_updown)) * try options.fontGet().lineHeight() });
            self.cursor_updown_pt = cr_new.topleft().plus(.{ .y = cr_new.h / 2 });

            // might have already passed, so need to go again next frame
            dvui.refresh(null, @src(), self.wd.id);

            var scrollto = Event{ .evt = .{ .scroll_to = .{
                .screen_rect = self.screenRectScale(cr_new).r,
            } } };
            self.processEvent(&scrollto, true);
        }

        if (self.scroll_to_cursor) {
            var scrollto = Event{ .evt = .{ .scroll_to = .{
                .screen_rect = self.screenRectScale(cr.outset(self.wd.options.paddingGet())).r,
            } } };
            self.processEvent(&scrollto, true);
        }

        if (self.selection.start == self.selection.end) {
            self.cursor_rect = cr;
        }
    }
}

pub fn touchEditing(self: *TextLayoutWidget, rs: RectScale) !void {
    if (!self.add_text_done) {
        try self.addTextDone(.{});
    }
    self.touch_editing_done = true;

    if (self.touch_editing and self.te_show_context_menu and self.focus_at_start and self.wd.visible()) {
        var fc = dvui.FloatingWidget.init(@src(), .{});

        var r = rs.r.offsetNeg(dvui.windowRectPixels()).scale(1.0 / dvui.windowNaturalScale());

        if (dvui.minSizeGet(fc.data().id)) |_| {
            const ms = dvui.minSize(fc.data().id, fc.data().options.min_sizeGet());
            fc.wd.rect.w = ms.w;
            fc.wd.rect.h = ms.h;

            fc.wd.rect.x = r.x + r.w - fc.wd.rect.w;
            fc.wd.rect.y = r.y - fc.wd.rect.h;

            fc.wd.rect = dvui.placeOnScreen(dvui.windowRect(), .{ .x = fc.wd.rect.x, .y = fc.wd.rect.y }, fc.wd.rect);
        } else {
            // need another frame to get our min size
            dvui.refresh(null, @src(), fc.wd.id);
        }

        try fc.install();
        defer fc.deinit();

        var hbox = try dvui.box(@src(), .horizontal, .{
            .corner_radius = dvui.ButtonWidget.defaults.corner_radiusGet(),
            .background = true,
            .border = dvui.Rect.all(1),
        });
        defer hbox.deinit();

        if (try dvui.buttonIcon(@src(), "copy", dvui.entypo.copy, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            dvui.dataSet(null, self.wd.id, "_copy_sel_next_frame", true);

            // we are called after all the text has been rendered, so
            // need to go another frame to actually do the copy
            dvui.refresh(null, @src(), self.wd.id);
        }

        if (try dvui.buttonIcon(@src(), "select all", dvui.entypo.swap, .{}, .{ .min_size_content = .{ .h = 20 }, .margin = Rect.all(2) })) {
            self.selection.start = 0;
            self.selection.cursor = 0;
            self.selection.end = std.math.maxInt(usize);

            // we are after all the text has been rendered, so need to go
            // another frame to show the select all
            dvui.refresh(null, @src(), self.wd.id);
        }
    }
}

pub fn widget(self: *TextLayoutWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *TextLayoutWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *TextLayoutWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const ret = dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
    var i: usize = undefined;
    if (g.y < 0.5) {
        if (g.x < 0.5) {
            i = 0; // upleft
        } else {
            i = 1; // upright
        }
    } else {
        if (g.x < 0.5) {
            i = 2; // downleft
        } else {
            i = 3; // downright
        }
    }

    self.corners[i] = ret;
    self.corners_last_seen = @intCast(i);
    return ret;
}

pub fn screenRectScale(self: *TextLayoutWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToScreen(rect);
}

pub fn minSizeForChild(self: *TextLayoutWidget, s: Size) void {
    if (self.corners_last_seen) |ls| {
        self.corners_min_size[ls] = s;
    }
    // we calculate our min size in deinit() after we have seen our text
}

// Using this function helps prevent accidentally using the selection when the
// end is way too large, because the way we do select all is to set end to
// maxInt(usize) and fix it up the next frame.
//
// Either the caller knows the max (like TextEntryWidget), or they can pass
// maxInt(usize) and be clued into what might happen.
pub fn selectionGet(self: *TextLayoutWidget, max: usize) *Selection {
    self.selection.start = @min(self.selection.start, max);
    self.selection.cursor = @min(self.selection.cursor, max);
    self.selection.end = @min(self.selection.end, max);
    return self.selection;
}

pub fn matchEvent(self: *TextLayoutWidget, e: *Event) bool {
    if (self.touch_editing and e.evt == .mouse and e.evt.mouse.action == .release and e.evt.mouse.button.touch()) {
        self.te_show_draggables = true;
        self.te_show_context_menu = true;
    }

    return dvui.eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r });
}

pub fn processEvents(self: *TextLayoutWidget) void {
    var evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *TextLayoutWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.evt == .mouse) {
        if (e.evt.mouse.action == .focus) {
            e.handled = true;
            // focus so that we can receive keyboard input
            dvui.focusWidget(self.wd.id, null, e.num);
        } else if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
            e.handled = true;
            // capture and start drag
            dvui.captureMouse(self.wd.id);
            dvui.dragPreStart(e.evt.mouse.p, .ibeam, Point{});

            if (e.evt.mouse.button.touch()) {
                std.debug.print("touch down\n", .{});
                self.te_focus_on_touchdown = self.focus_at_start;
                if (self.touch_editing) {
                    self.te_show_context_menu = false;

                    // need to refresh draggables
                    dvui.refresh(null, @src(), self.wd.id);
                }
            } else {
                self.sel_mouse_down_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                self.sel_mouse_drag_pt = null;
                self.cursor_updown = 0;
                self.cursor_updown_pt = null;
            }
        } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
            e.handled = true;

            if (dvui.captured(self.wd.id)) {
                if (e.evt.mouse.button.touch()) {
                    // this was a touch-release without drag, which transitions
                    // us between touch editing

                    if (self.te_focus_on_touchdown) {
                        self.touch_editing = !self.touch_editing;
                        self.sel_mouse_down_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                    } else {
                        self.touch_editing = true;
                    }
                }

                dvui.captureMouse(null);
            }
        } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
            // move if dragging
            if (dvui.dragging(e.evt.mouse.p)) |_| {
                if (!e.evt.mouse.button.touch()) {
                    e.handled = true;
                    self.sel_mouse_drag_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                    self.cursor_updown = 0;
                    self.cursor_updown_pt = null;
                    var scrolldrag = Event{ .evt = .{ .scroll_drag = .{
                        .mouse_pt = e.evt.mouse.p,
                        .screen_rect = self.wd.rectScale().r,
                        .capture_id = self.wd.id,
                    } } };
                    self.processEvent(&scrolldrag, true);
                } else {
                    // user intended to scroll with a finger swipe
                    dvui.captureMouse(null); // stop possible drag and capture
                }
            }
        }
    } else if (e.evt == .key and (e.evt.key.action == .down or e.evt.key.action == .repeat) and e.evt.key.mod.shift()) {
        switch (e.evt.key.code) {
            .left => {
                e.handled = true;
                if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                    // only change selection if mouse isn't trying to change it
                    self.sel_left_right -= 1;
                    self.scroll_to_cursor = true;
                }
            },
            .right => {
                e.handled = true;
                if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                    // only change selection if mouse isn't trying to change it
                    self.sel_left_right += 1;
                    self.scroll_to_cursor = true;
                }
            },
            .up, .down => |code| {
                e.handled = true;
                if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown_pt == null) {
                    self.cursor_updown += if (code == .down) 1 else -1;
                }
            },
            else => {},
        }
    } else if (e.evt == .key and e.evt.key.mod.controlCommand() and e.evt.key.code == .c and e.evt.key.action == .down) {
        // copy
        e.handled = true;
        self.copy_sel = self.selection.*;
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *TextLayoutWidget) void {
    if (!self.add_text_done) {
        self.addTextDone(.{}) catch |err| {
            dvui.log.err("TextLayoutWidget.deinit addTextDone got {!}\n", .{err});
        };
    }
    if (!self.touch_editing_done) {
        self.touchEditing(.{ .r = dvui.clipGet(), .s = self.wd.rectScale().s }) catch |err| {
            dvui.log.err("TextLayoutWidget.deinit touchEditing got {!}\n", .{err});
        };
    }
    dvui.dataSet(null, self.wd.id, "_touch_editing", self.touch_editing);
    dvui.dataSet(null, self.wd.id, "_te_show_draggables", self.te_show_draggables);
    dvui.dataSet(null, self.wd.id, "_te_show_context_menu", self.te_show_context_menu);
    dvui.dataSet(null, self.wd.id, "_te_focus_on_touchdown", self.te_focus_on_touchdown);
    dvui.dataSet(null, self.wd.id, "_sel_start_r", self.sel_start_r);
    dvui.dataSet(null, self.wd.id, "_sel_end_r", self.sel_end_r);
    dvui.dataSet(null, self.wd.id, "_selection", self.selection.*);

    if (self.sel_left_right != 0) {
        // user might have pressed left a few times, but we couldn't
        // process them all this frame because they crossed calls to
        // addText
        dvui.dataSet(null, self.wd.id, "_sel_left_right", self.sel_left_right);
        dvui.refresh(null, @src(), self.wd.id);
    }
    if (dvui.captured(self.wd.id) and self.sel_mouse_down_bytes != null) {
        // once we figure out where the mousedown was, we need to save it
        // as long as we are dragging
        dvui.dataSet(null, self.wd.id, "_sel_mouse_down_bytes", self.sel_mouse_down_bytes.?);
    }
    if (self.cursor_updown != 0) {
        // user pressed keys to move the cursor up/down, and on this frame
        // we figured out the pixel position where the new cursor should
        // be, but need to save this for next frame to figure out the byte
        // position based on this pixel position
        dvui.dataSet(null, self.wd.id, "_cursor_updown_pt", self.cursor_updown_pt.?);
        dvui.dataSet(null, self.wd.id, "_cursor_updown_drag", self.cursor_updown_drag);
    }
    dvui.clipSet(self.prevClip);

    // check if the widgets are taller than the text
    const left_height = (self.corners_min_size[0] orelse Size{}).h + (self.corners_min_size[2] orelse Size{}).h;
    const right_height = (self.corners_min_size[1] orelse Size{}).h + (self.corners_min_size[3] orelse Size{}).h;
    self.wd.min_size.h = @max(self.wd.min_size.h, self.wd.padSize(.{ .h = @max(left_height, right_height) }).h);

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
