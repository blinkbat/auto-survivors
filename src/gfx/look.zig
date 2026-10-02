const std = @import("std");
const rl = @import("raylib");
const hero = @import("../play/hero.zig");
const foe = @import("../play/foe.zig");

// EVERY PICTURE. A body with a sprite draws it, lit by the body shader; the rest is drawn from shapes here.

/// Sprites are authored at this many pixels a cell, facing right, and drawn 1:1.
pub const SPRITE_PX: i32 = 64;

pub const Heroes = std.EnumArray(hero.Class, ?rl.Texture2D);
pub const Foes = std.EnumArray(foe.Kind, ?rl.Texture2D);

/// The sprites the body shader lights besides the heroes and foes: fields of `Sprites`.
const PROPS = [_][]const u8{ "brazier", "banner", "vine", "skeleton" };

/// Every sprite the body shader lights.
pub const FIGURES: usize = Heroes.len + Foes.len + PROPS.len;

/// Needs a live GL context.
pub const Sprites = struct {
    heroes: Heroes = .initFill(null),
    foes: Foes = .initFill(null),
    brazier: ?rl.Texture2D = null,
    banner: ?rl.Texture2D = null,
    vine: ?rl.Texture2D = null,
    skeleton: ?rl.Texture2D = null,
    floor: ?rl.Texture2D = null,
    up_icons: std.EnumArray(hero.Up, ?rl.Texture2D) = .initFill(null),
    branch_icons: std.EnumArray(hero.Branch, ?rl.Texture2D) = .initFill(null),
    move_icon: ?rl.Texture2D = null,
    rest_icon: ?rl.Texture2D = null,

    pub fn load() Sprites {
        var s = Sprites{ .floor = texture(@embedFile("floor.png")) };
        inline for (PROPS) |p| @field(s, p) = texture(@embedFile(p ++ ".png"));
        for (hero.CLASSES) |c| s.heroes.set(c, texture(HERO_PNGS.get(c)));
        for (foe.KINDS) |k| s.foes.set(k, texture(FOE_PNGS.get(k)));
        if (s.floor) |f| rl.setTextureWrap(f, .repeat);
        inline for (comptime std.enums.values(hero.Up)) |u| s.up_icons.set(u, texture(@embedFile("icon_" ++ @tagName(u) ++ ".png")));
        inline for (comptime std.enums.values(hero.Branch)) |b| s.branch_icons.set(b, texture(@embedFile("icon_" ++ @tagName(b) ++ ".png")));
        s.move_icon = texture(@embedFile("icon_move.png"));
        s.rest_icon = texture(@embedFile("icon_rest.png"));
        return s;
    }

    pub fn unload(self: Sprites) void {
        inline for (std.meta.fields(Sprites)) |f| {
            const v = @field(self, f.name);
            const all: []const ?rl.Texture2D = if (f.type == ?rl.Texture2D) &.{v} else &v.values;
            for (all) |t| {
                if (t) |x| rl.unloadTexture(x);
            }
        }
    }

    pub fn icon(self: *const Sprites, c: hero.Card) ?rl.Texture2D {
        return switch (c) {
            .up => |u| self.up_icons.get(u),
            .branch => |b| self.branch_icons.get(b),
            .move => self.move_icon,
            .rest => self.rest_icon,
        };
    }

    pub fn figures(self: Sprites) [FIGURES]?rl.Texture2D {
        var props: [PROPS.len]?rl.Texture2D = undefined;
        inline for (PROPS, 0..) |p, i| props[i] = @field(self, p);
        return self.heroes.values ++ self.foes.values ++ props;
    }

    fn texture(png: []const u8) ?rl.Texture2D {
        const img = rl.loadImageFromMemory(".png", png) catch return null;
        defer rl.unloadImage(img);
        return rl.loadTextureFromImage(img) catch null;
    }
};

/// Each of `E`'s sprites, `<tag>.png`.
fn pngs(comptime E: type) std.EnumArray(E, []const u8) {
    var a: std.EnumArray(E, []const u8) = undefined;
    inline for (comptime std.enums.values(E)) |e| a.set(e, @embedFile(@tagName(e) ++ ".png"));
    return a;
}

const HERO_PNGS = pngs(hero.Class);
const FOE_PNGS = pngs(foe.Kind);

fn whole(t: rl.Texture2D) rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = @floatFromInt(t.width), .height = @floatFromInt(t.height) };
}

pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, whole(t), dest, .{ .x = 0, .y = 0 }, 0, tint);
}

/// Borrows `px`, packed `w` to a row: nothing to unload.
pub fn rgba(px: *anyopaque, w: i32, h: i32) rl.Image {
    return .{ .data = px, .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
}

/// Needs a live GL context.
pub fn clamped(img: rl.Image, filter: rl.TextureFilter) ?rl.Texture2D {
    const t = rl.loadTextureFromImage(img) catch return null;
    rl.setTextureFilter(t, filter);
    rl.setTextureWrap(t, .clamp);
    return t;
}

/// Needs a live GL context.
pub fn canvas(w: i32, h: i32, c: rl.Color) ?rl.Texture2D {
    const img = rl.genImageColor(w, h, c);
    defer rl.unloadImage(img);
    return clamped(img, .bilinear);
}

/// White, its alpha `alphaAt(dx, dy)` from the middle, 1 at the middle of each edge. Needs a live GL context.
pub fn radial(comptime px: i32, comptime alphaAt: fn (f32, f32) f32) ?rl.Texture2D {
    const n: usize = @intCast(px);
    var img: [n * n]rl.Color = undefined;
    const half: f32 = @as(f32, @floatFromInt(px)) * 0.5;
    for (0..n) |y| {
        for (0..n) |x| {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5 - half) / half;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5 - half) / half;
            img[y * n + x] = .{ .r = 255, .g = 255, .b = 255, .a = @intFromFloat(std.math.clamp(alphaAt(dx, dy), 0, 1) * 255) };
        }
    }
    return clamped(rgba(&img, px, px), .bilinear);
}

/// Null when it does not compile: raylib then hands back its default shader rather than an error.
pub fn shader(fs: [:0]const u8) ?rl.Shader {
    const s = rl.loadShaderFromMemory(null, fs) catch return null;
    return if (s.id == rl.gl.rlGetShaderIdDefault()) null else s;
}

/// Every field but `shader` is the location of the GLSL uniform it is named for.
pub fn uniforms(comptime T: type, s: rl.Shader) T {
    var u: T = undefined;
    u.shader = s;
    inline for (std.meta.fields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, "shader")) continue;
        @field(u, f.name) = rl.getShaderLocation(s, f.name);
    }
    return u;
}

pub fn rgb(hex: u24) rl.Color {
    return .{ .r = @intCast(hex >> 16), .g = @intCast((hex >> 8) & 0xff), .b = @intCast(hex & 0xff), .a = 255 };
}

pub fn fade(c: rl.Color, a: f32) rl.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * std.math.clamp(a, 0, 1)) };
}

/// What every fragment shader opens with: raylib's inputs and output, and the alpha below which nothing is drawn.
pub const FS_HEAD =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\out vec4 finalColor;
    \\const float CLEAR_A = 0.004;
    \\
;

pub const BG = rgb(0x07070a);
pub const TEXT = rgb(0xd8cdb4);
pub const DIM = rgb(0x8c8672);
pub const GOLD = rgb(0xc9a24a);
pub const BRIGHT = rgb(0xf0d27a);
pub const FOE = rgb(0xe0503a);
pub const LIFE = rgb(0x9c2f2a);
pub const LIFE_BG = fade(rgb(0x2a1414), 0.85);
pub const XP = rgb(0x5aa8e8);
pub const EDGE = rgb(0x4a4438);
pub const PANEL = rgb(0x0e0d12);
pub const RAISED = rgb(0x1a1820);
pub const VEIL = fade(BG, 0.74);
pub const ARROW = rgb(0xe6dcb4);
pub const SHIELD = rgb(0x9cc4ff);
pub const BOSS = rgb(0x78ffaa);

pub fn class(c: hero.Class) rl.Color {
    return switch (c) {
        .knight => rgb(0x9cb0d8),
        .archer => rgb(0x7cc86e),
        .cleric => rgb(0xf0e2b0),
        .pyromancer => rgb(0xf07a3a),
        .mystic => rgb(0x7ab8ff),
        .druid => rgb(0x8cc860),
        .bard => rgb(0xf096d8),
        .necromancer => rgb(0x7ad09a),
    };
}

/// What a blow on it sprays.
pub fn matter(k: ?foe.Kind) rl.Color {
    const kind = k orelse return .{ .r = 175, .g = 22, .b = 20, .a = 235 };
    return switch (kind) {
        .ghoul, .brute, .charger, .hound => .{ .r = 160, .g = 20, .b = 18, .a = 235 },
        .husk => .{ .r = 120, .g = 130, .b = 60, .a = 235 },
        .shellback => .{ .r = 90, .g = 110, .b = 190, .a = 235 },
        .imp => .{ .r = 230, .g = 110, .b = 40, .a = 235 },
        .warlock => .{ .r = 150, .g = 60, .b = 190, .a = 235 },
        .bat => .{ .r = 130, .g = 50, .b = 170, .a = 235 },
        .spitter => .{ .r = 150, .g = 180, .b = 40, .a = 235 },
        .boss => .{ .r = 70, .g = 220, .b = 130, .a = 235 },
    };
}

test "every hero and foe has a sprite and a colour" {
    for (hero.CLASSES) |c| {
        try std.testing.expect(HERO_PNGS.get(c).len > 0);
        try std.testing.expect(std.ascii.isUpper(hero.class(c).name[0]));
    }
    for (foe.KINDS) |k| try std.testing.expect(FOE_PNGS.get(k).len > 0);
}
