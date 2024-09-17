const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

const accent = Color{ .r = 0xfe, .g = 0x80, .b = 0x19, .a = 0xff }; // s:gb.bright_orange
const err = Color{ .r = 0xcc, .g = 0x24, .b = 0x1d, .a = 0xff }; // s:gb.neutral_red
const text = Color{ .r = 0xeb, .g = 0xdb, .b = 0xb2, .a = 0xff }; // s:gb.light1
const text_press = Color{ .r = 0x1d, .g = 0x20, .b = 0x21, .a = 0xff }; // s:gb.dark0_hard
const fill = fill_control;
const fill_window = Color{ .r = 0x66, .g = 0x5c, .b = 0x54, .a = 0xff }; // s:gb.dark3
const fill_control = Color{ .r = 0x7c, .g = 0x6f, .b = 0x64, .a = 0xff }; // s:gb.dark4
const fill_hover = border;
const fill_press = accent;
const border = Color{ .r = 0x83, .g = 0xa5, .b = 0x98, .a = 0xff }; // s:gb.bright_blue

pub const gruvbox = Theme{
    .name = "Gruvbox",
    .dark = true,

    .font_body = .{ .name = "Aleo" },
    .font_heading = .{ .name = "AleoBd" },
    .font_caption = .{ .name = "Aleo" },
    .font_caption_heading = .{ .name = "AleoBd" },
    .font_title = .{ .name = "Aleo" },
    .font_title_1 = .{ .name = "AleoBd" },
    .font_title_2 = .{ .name = "AleoBd" },
    .font_title_3 = .{ .name = "AleoBd" },
    .font_title_4 = .{ .name = "AleoBd" },

    .color_accent = accent,
    .color_err = err,
    .color_text = text,
    .color_text_press = text_press,
    .color_fill = fill,
    .color_fill_window = fill_window,
    .color_fill_control = fill_control,
    .color_fill_hover = fill_hover,
    .color_fill_press = fill_press,
    .color_border = border,

    .style_accent = Options{
        .color_accent = .{ .color = Color.alphaAdd(accent, accent) },
        .color_text = .{ .color = Color.alphaAdd(accent, text) },
        .color_text_press = .{ .color = Color.alphaAdd(accent, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(accent, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(accent, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(accent, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(accent, border) },
    },

    .style_err = Options{
        .color_accent = .{ .color = Color.alphaAdd(err, accent) },
        .color_text = .{ .color = Color.alphaAdd(err, text) },
        .color_text_press = .{ .color = Color.alphaAdd(err, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(err, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(err, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(err, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(err, border) },
    },
};
