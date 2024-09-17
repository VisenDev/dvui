const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

//Colors inspired by the flow neovim theme
const accent = Color{ .r = 0xff, .g = 0x33, .b = 0x99, .a = 0xff }; // colors.fluo.pink
const err = Color{ .r = 0xf2, .g = 0xf2, .b = 0xf2, .a = 0xff }; // colors.white
const text = Color{ .r = 0xf2, .g = 0xf2, .b = 0xf2, .a = 0xff }; // colors.white
const text_press = Color{ .r = 0x0d, .g = 0x0d, .b = 0x0d, .a = 0xff }; // colors.black
const fill = Color{ .r = 0x0d, .g = 0x13, .b = 0x2f, .a = 0xff }; // colors.grey[1]
const fill_window = fill; // Color{ .r = 0x9f, .g = 0xa7, .b = 0xc7, .a = 0xff }; // colors.grey[7]
const fill_control = Color{ .r = 0x51, .g = 0x5b, .b = 0x7f, .a = 0xff }; // colors.grey[4]
const fill_hover = Color{ .r = 0x62, .g = 0x72, .b = 0xa4, .a = 0xff }; // colors.bg_border
const fill_press = accent;
const border = Color{ .r = 0x9f, .g = 0xa7, .b = 0xc7, .a = 0xff }; // colors.grey[7]

pub const flow = Theme{
    .name = "Flow",
    .dark = true,

    .font_body = .{ .name = "Vera" },
    .font_heading = .{ .name = "VeraBd" },
    .font_caption = .{ .name = "Vera" },
    .font_caption_heading = .{ .name = "VeraBd" },
    .font_title = .{ .name = "Vera" },
    .font_title_1 = .{ .name = "VeraBd" },
    .font_title_2 = .{ .name = "VeraBd" },
    .font_title_3 = .{ .name = "VeraBd" },
    .font_title_4 = .{ .name = "VeraBd" },

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
