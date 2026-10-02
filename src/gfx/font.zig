const std = @import("std");
const rl = @import("raylib");

const TTF = "Balthazar-Regular.ttf";
/// One atlas this big, mipmapped, reads clean at every size drawn.
const ATLAS_PX: i32 = 96;
const SHADOW_A: u16 = 200;
/// Text size per pixel the shadow sits down and right.
const SHADOW_STEP: i32 = 14;
pub const BODY: i32 = 20;
pub const SMALL: i32 = 16;
pub const HEAD: i32 = 30;
pub const TITLE: i32 = 56;

/// Until `load` succeeds, raylib's built-in font stands in.
pub const Face = struct {
    font: ?rl.Font = null,

    /// Needs a live GL context.
    pub fn load() Face {
        var f = rl.loadFontFromMemory(".ttf", @embedFile(TTF), ATLAS_PX, null) catch return .{};
        rl.genTextureMipmaps(&f.texture);
        rl.setTextureFilter(f.texture, .trilinear);
        return .{ .font = f };
    }

    pub fn unload(self: *Face) void {
        if (self.font) |f| rl.unloadFont(f);
        self.font = null;
    }

    pub fn width(self: Face, s: [:0]const u8, size: i32) i32 {
        const f = self.font orelse return rl.measureText(s, size);
        return @intFromFloat(rl.measureTextEx(f, s, @floatFromInt(size), 0).x);
    }

    pub fn draw(self: Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const f = self.font orelse return rl.drawText(s, x, y, size, col);
        rl.drawTextEx(f, s, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, @floatFromInt(size), 0, col);
    }

    /// Over a drop shadow.
    pub fn text(self: Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        const off = @max(@divTrunc(size, SHADOW_STEP), 1);
        self.draw(s, x + off, y + off, size, .{ .r = 0, .g = 0, .b = 0, .a = @intCast(SHADOW_A * col.a / 255) });
        self.draw(s, x, y, size, col);
    }

    /// Its middle on `cx`.
    pub fn mid(self: Face, s: [:0]const u8, cx: i32, y: i32, size: i32, col: rl.Color) void {
        self.text(s, cx - @divTrunc(self.width(s, size), 2), y, size, col);
    }

    /// Word-wrapped to `w`, lines `line` apart; the height it took.
    pub fn wrapped(self: Face, s: []const u8, x: i32, y: i32, w: i32, size: i32, line: i32, col: rl.Color, centred: bool) i32 {
        var buf: [256:0]u8 = undefined;
        var n: usize = 0;
        var row: i32 = 0;
        var words = std.mem.tokenizeScalar(u8, s, ' ');
        while (words.next()) |word| {
            const before = n;
            if (n > 0 and n < buf.len) {
                buf[n] = ' ';
                n += 1;
            }
            const take = @min(word.len, buf.len - n);
            @memcpy(buf[n..][0..take], word[0..take]);
            n += take;
            buf[n] = 0;
            if (before > 0 and self.width(buf[0..n :0], size) > w) {
                buf[before] = 0;
                self.lineAt(buf[0..before :0], x, y + row * line, w, size, col, centred);
                row += 1;
                std.mem.copyForwards(u8, buf[0..take], word[0..take]);
                n = take;
                buf[n] = 0;
            }
        }
        if (n > 0) {
            self.lineAt(buf[0..n :0], x, y + row * line, w, size, col, centred);
            row += 1;
        }
        return row * line;
    }

    fn lineAt(self: Face, s: [:0]const u8, x: i32, y: i32, w: i32, size: i32, col: rl.Color, centred: bool) void {
        if (centred) self.mid(s, x + @divTrunc(w, 2), y, size, col) else self.text(s, x, y, size, col);
    }
};
