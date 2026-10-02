const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const look = @import("look.zig");

// EVERY LIGHT, after zig-roguelike-scratch's, on an open field at night. The ground is drawn at full brightness and
// one pass of the light map (2x modulate, so it can brighten) lights it; bodies are lit per pixel by their own
// shader from normals bevelled off their silhouette. Nothing in the simulation reads any of it.

const V = mathx.V;
pub const Rgb = @Vector(3, f32);

/// Light-map texels per cell side.
pub const SUB: i32 = 4;
const MAP_W: i32 = 300;
const MAP_H: i32 = 180;
const TEXELS: usize = @intCast(MAP_W * MAP_H);
/// The map is drawn with (DST_COLOR, SRC_COLOR) blending, so a texel stores half the light and reaches twice the art.
const OVERBRIGHT: f32 = 2.0;
pub const MAX_LAMPS: usize = 128;
pub const AMBIENT: Rgb = .{ 0.22, 0.23, 0.33 };
/// Of a lamp's reach, the inverse square's reference distance.
const FALLOFF_D0: f32 = 0.36;
const FLOOR_WRAP: f32 = 1.0;
const BODY_Z: f32 = 0.4;
/// A lamp at height z shows this much of it up the screen, for the side it lights a body from.
const LIFT: f32 = 0.5;
const FAINT: f32 = 0.002;
/// Per channel, light past this bends toward a square root instead of clipping (Brogue's `adjustedLightValue`).
const KNEE: f32 = 1.5;
const TINT_DIRECT: f32 = 0.6;

pub const BODY_LIGHTS: usize = 4;
pub const FLASH_RGB = Rgb{ 0.95, 0.42, 0.32 };
/// Texels toward the viewer, for the side-lighting of a body.
const BODY_LIGHT_Z: f32 = 40.0;
const SHADOW_MAX: f32 = 0.8;
const SHADOW_FULL: f32 = 0.5;
const SHADOW_LAMP_FULL: f32 = 0.25;
const SHADOW_FAINT: f32 = 0.004;
const SHADOW_LEN_LO: f32 = 0.5;
const SHADOW_LEN_HI: f32 = 1.8;
const SHADOW_LEN_PER_CELL: f32 = 0.25;
const SHADOW_SQUASH: f32 = 0.55;
const SHADOW_OVERHEAD: f32 = 0.05;
const SHADOW_RISE_MIN: f32 = 0.3;
const SHADOW_PAD: f32 = 6;
const SHADOW_SOFT_TIP: f32 = 4.0;
const SHADOW_SOFT_FOOT: f32 = 1.2;
const SHADOW_TAPS: i32 = 3;
const CONTACT_W: f32 = 0.62;
const CONTACT_H: f32 = 0.2;
const CONTACT_A: f32 = 0.75;
const GLOW_PX: i32 = 64;

comptime {
    std.debug.assert(SHADOW_PAD >= SHADOW_SOFT_TIP * 0.5 * @as(f32, @floatFromInt(SHADOW_TAPS)));
}

pub const Lamp = struct {
    at: V,
    z: f32,
    colour: Rgb,
    /// Cells: exactly nothing past it.
    reach: f32,
    casts: bool = false,

    /// What reaches a point at height `z`, before the surface turns it.
    fn toward(l: Lamp, q: V, z: f32) ?struct { d: [3]f32, d2: f32, k: f32 } {
        const d = [3]f32{ l.at[0] - q[0], l.at[1] - q[1], l.z - z };
        const d2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
        if (d2 >= l.reach * l.reach) return null;
        return .{ .d = d, .d2 = d2, .k = falloff(d2, l.reach) };
    }

    /// What it adds to the ground at `q`.
    fn onFloor(l: Lamp, q: V) ?Rgb {
        const r = l.toward(q, 0) orelse return null;
        return l.colour * splat(r.k * wrapped(r.d[2] / @sqrt(@max(r.d2, 1e-6)), FLOOR_WRAP));
    }

    fn drawn(l: Lamp) V {
        return .{ l.at[0], l.at[1] - l.z * LIFT };
    }
};

/// Windowed inverse square: exactly nothing at `reach`.
fn falloff(d2: f32, reach: f32) f32 {
    const r = d2 / (reach * reach);
    const w = std.math.clamp(1 - r * r, 0, 1);
    const d0 = reach * FALLOFF_D0;
    return w * w / (1 + d2 / (d0 * d0));
}

fn wrapped(cos: f32, wrap: f32) f32 {
    return @max(0, (cos + wrap) / (1 + wrap));
}

pub const FLICKER: f32 = 0.14;
const FLICKER_BANDS = [_]struct { hz: f32, weight: f32 }{
    .{ .hz = 1.5, .weight = 0.6 },
    .{ .hz = 5.0, .weight = 0.3 },
    .{ .hz = 11.0, .weight = 0.1 },
};

fn hash(n: i32, seed: u32) f32 {
    return mathx.unitHash(n, 0, seed);
}

fn noise(t: f32, seed: u32) f32 {
    const i = @floor(t);
    const n: i32 = @intFromFloat(i);
    return mathx.lerpF(hash(n, seed), hash(n +% 1, seed), mathx.smooth(t - i));
}

pub fn flicker(t: f32, seed: u32) f32 {
    var n: f32 = 0;
    for (FLICKER_BANDS, 0..) |b, i| n += b.weight * (noise(t * b.hz, seed ^ (@as(u32, @intCast(i)) *% 0x5BD1E995)) * 2 - 1);
    return 1 + FLICKER * n;
}

fn knee(c: Rgb) Rgb {
    var out = c;
    for (0..3) |i| {
        if (c[i] > KNEE) out[i] = KNEE * @sqrt(c[i] / KNEE);
    }
    return out;
}

fn splat(k: f32) Rgb {
    return @splat(k);
}

fn rgbOf(c: rl.Color) Rgb {
    return Rgb{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) } / splat(255);
}

pub fn colourOf(c: Rgb, a: f32) rl.Color {
    const k = @max(splat(0), @min(splat(1), c)) * splat(255) + splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

fn texelOf(c: Rgb) rl.Color {
    return colourOf(knee(c) / splat(OVERBRIGHT), 1);
}

pub fn lum(c: Rgb) f32 {
    return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}

/// One light reaching a body: where it shows from on screen and where it stands on the ground, cells.
const BodyLamp = struct { drawn: V, ground: V, colour: Rgb, casts: bool };

pub const Shine = struct {
    ambient: Rgb = @splat(0),
    n: usize = 0,
    lamp: [BODY_LIGHTS]BodyLamp = undefined,

    fn add(self: *Shine, l: BodyLamp) void {
        var i = self.n;
        if (self.n == BODY_LIGHTS) {
            i = 0;
            for (1..BODY_LIGHTS) |k| {
                if (lum(self.lamp[k].colour) < lum(self.lamp[i].colour)) i = k;
            }
            if (lum(l.colour) <= lum(self.lamp[i].colour)) return;
        } else self.n += 1;
        self.lamp[i] = l;
    }

    fn total(self: Shine) Rgb {
        var c: Rgb = @splat(0);
        for (self.lamp[0..self.n]) |l| c += l.colour;
        return c;
    }

    pub fn lit(self: Shine) f32 {
        return lum(self.ambient + self.total());
    }

    /// As the body shader would draw `c`, for what is drawn without it.
    pub fn drawn(self: Shine, c: rl.Color, flash: f32) rl.Color {
        const t = rgbOf(c) * (self.ambient + self.total() * splat(TINT_DIRECT));
        return colourOf(t + (FLASH_RGB - t) * splat(flash), @as(f32, @floatFromInt(c.a)) / 255);
    }
};

pub const Light = struct {
    lamps: [MAX_LAMPS]Lamp,
    n: usize,
    acc: [TEXELS]Rgb,
    map: [TEXELS]rl.Color,
    /// The world texel the map's first one is.
    origin: mathx.P,
    w: i32,
    h: i32,
    gpu: Gpu,

    /// Set field by field: built as one value, it is a temporary bigger than a thread's stack.
    pub fn create(alloc: std.mem.Allocator) !*Light {
        const l = try alloc.create(Light);
        l.n = 0;
        l.origin = .{ .x = 0, .y = 0 };
        l.w = 0;
        l.h = 0;
        l.gpu = .{};
        return l;
    }

    pub fn clear(self: *Light) void {
        self.n = 0;
    }

    pub fn add(self: *Light, l: Lamp) void {
        if (self.n == MAX_LAMPS) return;
        self.lamps[self.n] = l;
        self.n += 1;
    }

    /// The light on the ground at `q`, cells.
    pub fn at(self: *const Light, q: V) Rgb {
        var c = AMBIENT;
        for (self.lamps[0..self.n]) |l| c += l.onFloor(q) orelse continue;
        return c;
    }

    /// The map over cells `lo` to `hi`, a texel round them for the filter.
    pub fn bake(self: *Light, lo: V, hi: V) void {
        const sub: f32 = @floatFromInt(SUB);
        self.origin = .{ .x = @as(i32, @intFromFloat(@floor(lo[0] * sub))) - 1, .y = @as(i32, @intFromFloat(@floor(lo[1] * sub))) - 1 };
        self.w = @min(MAP_W, @as(i32, @intFromFloat(@ceil((hi[0] - lo[0]) * sub))) + 3);
        self.h = @min(MAP_H, @as(i32, @intFromFloat(@ceil((hi[1] - lo[1]) * sub))) + 3);
        const w: usize = @intCast(self.w);
        const h: usize = @intCast(self.h);
        @memset(self.acc[0 .. w * h], AMBIENT);
        for (self.lamps[0..self.n]) |l| {
            const x0 = @max(0, @as(i32, @intFromFloat(@floor((l.at[0] - l.reach) * sub))) - self.origin.x);
            const y0 = @max(0, @as(i32, @intFromFloat(@floor((l.at[1] - l.reach) * sub))) - self.origin.y);
            const x1 = @min(self.w, @as(i32, @intFromFloat(@ceil((l.at[0] + l.reach) * sub))) - self.origin.x + 1);
            const y1 = @min(self.h, @as(i32, @intFromFloat(@ceil((l.at[1] + l.reach) * sub))) - self.origin.y + 1);
            var ty = y0;
            while (ty < y1) : (ty += 1) {
                var tx = x0;
                while (tx < x1) : (tx += 1) {
                    const q = V{ (@as(f32, @floatFromInt(self.origin.x + tx)) + 0.5) / sub, (@as(f32, @floatFromInt(self.origin.y + ty)) + 0.5) / sub };
                    self.acc[@intCast(ty * self.w + tx)] += l.onFloor(q) orelse continue;
                }
            }
        }
        for (self.acc[0 .. w * h], self.map[0 .. w * h]) |c, *m| m.* = texelOf(c);
    }

    /// `cam` is the world pixel at the screen's top-left.
    pub fn drawMap(self: *Light, cam: V, cell: f32) void {
        const tex = self.gpu.map orelse return;
        if (self.w <= 0 or self.h <= 0) return;
        const wf: f32 = @floatFromInt(self.w);
        const hf: f32 = @floatFromInt(self.h);
        rl.updateTextureRec(tex, .{ .x = 0, .y = 0, .width = wf, .height = hf }, &self.map);
        const step = cell / @as(f32, @floatFromInt(SUB));
        rl.gl.rlSetBlendFactors(rl.gl.rl_dst_color, rl.gl.rl_src_color, rl.gl.rl_func_add);
        rl.beginBlendMode(.custom);
        defer rl.endBlendMode();
        rl.drawTexturePro(tex, .{ .x = 0, .y = 0, .width = wf, .height = hf }, .{
            .x = @as(f32, @floatFromInt(self.origin.x)) * step - cam[0],
            .y = @as(f32, @floatFromInt(self.origin.y)) * step - cam[1],
            .width = wf * step,
            .height = hf * step,
        }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
    }

    /// `centre` is the body's middle as drawn, cells. `own` is a lamp the body carries, which lights it flat.
    pub fn onBody(self: *const Light, centre: V, own: ?usize) Shine {
        var s = Shine{ .ambient = AMBIENT };
        for (self.lamps[0..self.n], 0..) |l, i| {
            const r = l.toward(centre, BODY_Z) orelse continue;
            if (r.k <= FAINT) continue;
            if (own == i) {
                s.ambient += l.colour * splat(r.k);
                continue;
            }
            s.add(.{ .drawn = l.drawn(), .ground = l.at, .colour = l.colour * splat(r.k), .casts = l.casts });
        }
        return s;
    }

    /// Needs a live GL context.
    pub fn load(self: *Light, figures: *const [look.FIGURES]?rl.Texture2D) void {
        self.gpu = Gpu.load(figures);
    }

    pub fn unload(self: *Light) void {
        self.gpu.unload();
        self.gpu = .{};
    }

    /// `centre` is its middle, cells; `flash` is how far toward `FLASH_RGB` it is drawn.
    pub fn drawBody(self: *const Light, tex: rl.Texture2D, dest: rl.Rectangle, left: bool, centre: V, s: Shine, flash: f32) void {
        const w: f32 = @floatFromInt(tex.width);
        const h: f32 = @floatFromInt(tex.height);
        const src = rl.Rectangle{ .x = 0, .y = 0, .width = if (left) -w else w, .height = h };
        const normals = self.gpu.art(tex).normals;
        const sh = self.gpu.body;
        if (sh == null or normals == null) {
            rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, s.drawn(rl.Color.white, flash));
            return;
        }
        const px: f32 = @floatFromInt(look.SPRITE_PX);
        var pos: [BODY_LIGHTS][3]f32 = undefined;
        var col: [BODY_LIGHTS][3]f32 = undefined;
        for (s.lamp[0..s.n], 0..) |l, i| {
            pos[i] = .{ (l.drawn[0] - centre[0]) * px, (l.drawn[1] - centre[1]) * px, BODY_LIGHT_Z };
            col[i] = l.colour;
        }
        const size = [2]f32{ w, h };
        const flip: f32 = if (left) -1 else 1;
        const ambient: [3]f32 = s.ambient;
        const n: i32 = @intCast(s.n);
        const b = sh.?;
        rl.beginShaderMode(b.shader);
        defer rl.endShaderMode();
        rl.setShaderValue(b.shader, b.size, &size, .vec2);
        rl.setShaderValue(b.shader, b.flip, &flip, .float);
        rl.setShaderValue(b.shader, b.ambient, &ambient, .vec3);
        rl.setShaderValue(b.shader, b.count, &n, .int);
        rl.setShaderValue(b.shader, b.flash, &flash, .float);
        rl.setShaderValueTexture(b.shader, b.normals, normals.?);
        if (s.n > 0) {
            rl.setShaderValueV(b.shader, b.lpos, &pos, .vec3, n);
            rl.setShaderValueV(b.shader, b.lcol, &col, .vec3, n);
        }
        rl.drawTexturePro(tex, src, dest, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
        rl.gl.rlDrawRenderBatchActive();
    }

    /// The dark under each body's feet, then a shadow from each lamp that casts one. `bodies` have `tex`, `dest`,
    /// `left`, `mid` and `shine`. Black laid over black lands the same in any order, so it is one flush a sprite.
    pub fn drawShadows(self: *const Light, bodies: anytype) void {
        if (self.gpu.glow) |g| {
            for (bodies) |b| {
                const lit = b.shine.lit();
                if (lit <= 0) continue;
                const f = feet(self.gpu.art(b.tex), b.tex, b.dest);
                glowAt(g, f.x, f.y, b.dest.width * CONTACT_W * 0.5, b.dest.width * CONTACT_H * 0.5, colourOf(@splat(0), CONTACT_A * @min(1, lit / 0.8)));
            }
        }
        const sh = self.gpu.shadow orelse return;
        rl.beginShaderMode(sh.shader);
        defer rl.endShaderMode();
        for (self.gpu.arts[0..self.gpu.art_n]) |a| {
            var set = false;
            for (bodies) |b| {
                if (b.tex.id != a.id) continue;
                const f = feet(a, b.tex, b.dest);
                var buf: [BODY_LIGHTS]Cast = undefined;
                const cs = casts(b.shine, b.mid, f.height, &buf);
                if (cs.len == 0) continue;
                const foot = a.foot / @as(f32, @floatFromInt(b.tex.height));
                if (!set) {
                    const size = [2]f32{ @floatFromInt(b.tex.width), @floatFromInt(b.tex.height) };
                    rl.setShaderValue(sh.shader, sh.size, &size, .vec2);
                    rl.setShaderValue(sh.shader, sh.foot, &foot, .float);
                    set = true;
                }
                for (cs) |c| silhouette(b.tex, f.x, f.y, c.lean, b.dest.width, foot, b.left, c.alpha);
            }
            if (set) rl.gl.rlDrawRenderBatchActive();
        }
    }

    /// Additive, centred on `x, y` px, `r` px out.
    pub fn glow(self: *const Light, x: f32, y: f32, r: f32, c: Rgb, a: f32) void {
        const g = self.gpu.glow orelse return;
        glowAt(g, x, y, r, r, colourOf(c, a));
    }
};

/// `lean` is pixels from the feet to the tip.
const Cast = struct { lean: [2]f32, alpha: f32 };

/// Where a body drawn at `dest` stands, px, and how tall it is above that.
fn feet(a: Art, tex: rl.Texture2D, dest: rl.Rectangle) struct { x: f32, y: f32, height: f32 } {
    const height = a.foot * dest.height / @as(f32, @floatFromInt(tex.height));
    return .{ .x = dest.x + dest.width * 0.5, .y = dest.y + height, .height = height };
}

fn casts(s: Shine, centre: V, height: f32, out: *[BODY_LIGHTS]Cast) []const Cast {
    const lit = s.lit();
    if (lit <= 0) return out[0..0];
    var n: usize = 0;
    for (s.lamp[0..s.n]) |l| {
        if (!l.casts) continue;
        const own = lum(l.colour);
        const alpha = SHADOW_MAX * mathx.smooth(own / lit / SHADOW_FULL) * mathx.smooth(own / SHADOW_LAMP_FULL);
        if (alpha < SHADOW_FAINT) continue;
        const dx = centre[0] - l.ground[0];
        const dy = centre[1] - l.ground[1];
        const d = @sqrt(dx * dx + dy * dy);
        if (d < SHADOW_OVERHEAD) continue;
        const len = height * std.math.clamp(SHADOW_LEN_LO + SHADOW_LEN_PER_CELL * d, SHADOW_LEN_LO, SHADOW_LEN_HI);
        const down: f32 = if (dy >= 0) 1 else -1;
        const rise = down * @max(@abs(dy / d) * SHADOW_SQUASH, SHADOW_RISE_MIN);
        out[n] = .{ .lean = .{ dx / d * len, rise * len }, .alpha = alpha };
        n += 1;
    }
    return out[0..n];
}

fn glowAt(g: rl.Texture2D, x: f32, y: f32, rx: f32, ry: f32, c: rl.Color) void {
    look.stretch(g, .{ .x = x - rx, .y = y - ry, .width = rx * 2, .height = ry * 2 }, c);
}

/// Leaning down the screen mirrors the quad, so its corners go the other way round to keep the winding the
/// rasteriser does not cull.
fn silhouette(tex: rl.Texture2D, fx: f32, fy: f32, lean: [2]f32, width: f32, foot: f32, left: bool, alpha: f32) void {
    const pad = SHADOW_PAD / @as(f32, @floatFromInt(tex.width));
    const mirrored = lean[1] > 0;
    const half = width * 0.5 * (1 + pad * 2);
    const stretch = 1 + pad / foot;
    const west: f32 = if (left) 1 + pad else -pad;
    const east: f32 = if (left) -pad else 1 + pad;
    const tip = [2]f32{ fx + lean[0] * stretch, fy + lean[1] * stretch };
    const corners = [4][4]f32{
        .{ west, -pad, tip[0] - half, tip[1] },
        .{ west, foot, fx - half, fy },
        .{ east, foot, fx + half, fy },
        .{ east, -pad, tip[0] + half, tip[1] },
    };
    rl.gl.rlSetTexture(tex.id);
    rl.gl.rlBegin(rl.gl.rl_quads);
    const shade = colourOf(@splat(0), alpha);
    rl.gl.rlColor4ub(shade.r, shade.g, shade.b, shade.a);
    for (0..4) |k| {
        const v = corners[if (mirrored) 3 - k else k];
        rl.gl.rlTexCoord2f(v[0], v[1]);
        rl.gl.rlVertex2f(v[2], v[3]);
    }
    rl.gl.rlEnd();
    rl.gl.rlSetTexture(0);
}

const BODY_FS = look.FS_HEAD ++ std.fmt.comptimePrint(
    "#define LIGHTS {d}\nconst float KNEE = {d:.4};\nconst vec3 FLASH = vec3({d:.4}, {d:.4}, {d:.4});\n",
    .{ BODY_LIGHTS, KNEE, FLASH_RGB[0], FLASH_RGB[1], FLASH_RGB[2] },
) ++
    \\uniform sampler2D normals;
    \\uniform vec2 size;
    \\uniform float flip;
    \\uniform vec3 ambient;
    \\uniform int count;
    \\uniform vec3 lpos[LIGHTS];
    \\uniform vec3 lcol[LIGHTS];
    \\uniform float flash;
    \\const float WRAP = 0.4;
    \\const float RISE = 0.7;
    \\const float RIM = 0.8;
    \\const float RIM_REACH = 2.0;
    \\const float SHEEN = 0.12;
    \\float alphaAt(vec2 px) {
    \\    if (px.x < 0.0 || px.y < 0.0 || px.x >= size.x || px.y >= size.y) return 0.0;
    \\    return texture(texture0, px / size).a;
    \\}
    \\void main() {
    \\    vec2 px = floor(fragTexCoord * size) + 0.5;
    \\    vec4 c = texture(texture0, px / size);
    \\    if (c.a < CLEAR_A) discard;
    \\    vec3 n = texture(normals, px / size).xyz * 2.0 - 1.0;
    \\    n.x *= flip;
    \\    n = normalize(n);
    \\    vec2 p = vec2((px.x - size.x * 0.5) * flip, px.y - size.y * 0.5);
    \\    vec3 light = ambient;
    \\    vec3 sheen = vec3(0.0);
    \\    for (int i = 0; i < LIGHTS; i++) {
    \\        if (i >= count) break;
    \\        vec3 l = lpos[i] - vec3(p, 0.0);
    \\        l.z = max(l.z, length(l.xy) * RISE);
    \\        float diffuse = max((dot(n, normalize(l)) + WRAP) / (1.0 + WRAP), 0.0);
    \\        vec2 toward = normalize(l.xy) * RIM_REACH;
    \\        toward.x *= flip;
    \\        float rim = c.a * (1.0 - alphaAt(px + toward));
    \\        light += lcol[i] * (diffuse + rim * RIM);
    \\        sheen += lcol[i] * rim * SHEEN;
    \\    }
    \\    light = mix(light, KNEE * sqrt(light / KNEE), step(KNEE, light));
    \\    finalColor = vec4(mix(c.rgb * light + sheen, FLASH, flash), c.a) * fragColor;
    \\}
;

const SHADOW_FS = look.FS_HEAD ++ std.fmt.comptimePrint(
    "const float SOFT_TIP = {d:.4};\nconst float SOFT_FOOT = {d:.4};\nconst int TAPS = {d};\n",
    .{ SHADOW_SOFT_TIP, SHADOW_SOFT_FOOT, SHADOW_TAPS },
) ++
    \\uniform vec2 size;
    \\uniform float foot;
    \\float alphaAt(vec2 uv) {
    \\    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > foot) return 0.0;
    \\    return texture(texture0, uv).a;
    \\}
    \\void main() {
    \\    float spread = mix(SOFT_TIP, SOFT_FOOT, clamp(fragTexCoord.y / foot, 0.0, 1.0));
    \\    float a = 0.0;
    \\    for (int i = -TAPS; i <= TAPS; i++) {
    \\        for (int j = -TAPS; j <= TAPS; j++) {
    \\            a += alphaAt(fragTexCoord + vec2(float(i), float(j)) * spread * 0.5 / size);
    \\        }
    \\    }
    \\    float n = float(TAPS * 2 + 1);
    \\    finalColor = vec4(0.0, 0.0, 0.0, a / (n * n) * fragColor.a);
    \\}
;

const BodyShader = struct {
    shader: rl.Shader,
    size: i32,
    flip: i32,
    ambient: i32,
    count: i32,
    lpos: i32,
    lcol: i32,
    normals: i32,
    flash: i32,
};

const ShadowShader = struct {
    shader: rl.Shader,
    size: i32,
    foot: i32,
};

const Art = struct {
    id: u32,
    /// Texel rows from the sprite's top to just under its lowest opaque row.
    foot: f32,
    normals: ?rl.Texture2D,

    fn bare(t: rl.Texture2D) Art {
        return .{ .id = t.id, .foot = @floatFromInt(t.height), .normals = null };
    }
};

/// Texels in from the silhouette over which a body's edge rounds off, and how steeply.
const BEVEL_PX: i32 = 5;
const BEVEL_DEPTH: f32 = 2.0;
const ART_MAX: i32 = 2 * look.SPRITE_PX;
const SOLID_A: u8 = 25;

const Gpu = struct {
    map: ?rl.Texture2D = null,
    glow: ?rl.Texture2D = null,
    body: ?BodyShader = null,
    shadow: ?ShadowShader = null,
    arts: [look.FIGURES]Art = undefined,
    art_n: usize = 0,

    fn load(figures: *const [look.FIGURES]?rl.Texture2D) Gpu {
        var g = Gpu{};
        g.map = look.canvas(MAP_W, MAP_H, rl.Color.black);
        g.glow = look.radial(GLOW_PX, glowAlpha);
        if (look.shader(BODY_FS)) |s| g.body = look.uniforms(BodyShader, s);
        if (look.shader(SHADOW_FS)) |s| g.shadow = look.uniforms(ShadowShader, s);
        for (figures) |b| {
            const t = b orelse continue;
            g.arts[g.art_n] = artOf(t);
            g.art_n += 1;
        }
        return g;
    }

    fn unload(g: Gpu) void {
        if (g.map) |t| rl.unloadTexture(t);
        if (g.glow) |t| rl.unloadTexture(t);
        if (g.body) |s| rl.unloadShader(s.shader);
        if (g.shadow) |s| rl.unloadShader(s.shader);
        for (g.arts[0..g.art_n]) |a| {
            if (a.normals) |t| rl.unloadTexture(t);
        }
    }

    fn art(g: *const Gpu, t: rl.Texture2D) Art {
        for (g.arts[0..g.art_n]) |a| {
            if (a.id == t.id) return a;
        }
        return Art.bare(t);
    }
};

fn artOf(t: rl.Texture2D) Art {
    var a = Art.bare(t);
    if (t.width > ART_MAX or t.height > ART_MAX) return a;
    const img = rl.loadImageFromTexture(t) catch return a;
    defer rl.unloadImage(img);
    var solid: [ART_MAX * ART_MAX]bool = undefined;
    const w: usize = @intCast(t.width);
    for (0..@intCast(t.height)) |y| {
        for (0..w) |x| solid[y * w + x] = rl.getImageColor(img, @intCast(x), @intCast(y)).a > SOLID_A;
    }
    var y: i32 = t.height - 1;
    while (y >= 0) : (y -= 1) {
        if (rowSolid(&solid, t.width, y)) {
            a.foot = @floatFromInt(y + 1);
            break;
        }
    }
    a.normals = bevelNormals(&solid, t.width, t.height);
    return a;
}

fn rowSolid(solid: *const [ART_MAX * ART_MAX]bool, w: i32, y: i32) bool {
    var x: i32 = 0;
    while (x < w) : (x += 1) {
        if (solid[@intCast(y * w + x)]) return true;
    }
    return false;
}

fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32) f32 {
    if (x < 0 or y < 0 or x >= w or y >= h) return 0;
    return f[@intCast(y * w + x)];
}

/// Laigter's soft bevel: distance to the nearest clear texel (outside counts as clear), raised on a quarter circle.
fn bevelNormals(solid: *const [ART_MAX * ART_MAX]bool, w: i32, h: i32) ?rl.Texture2D {
    var height: [ART_MAX * ART_MAX]f32 = undefined;
    const reach = BEVEL_PX + 1;
    var y: i32 = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const i: usize = @intCast(y * w + x);
            if (!solid[i]) {
                height[i] = 0;
                continue;
            }
            var near2: i32 = reach * reach;
            var dy: i32 = -reach;
            while (dy <= reach) : (dy += 1) {
                var dx: i32 = -reach;
                while (dx <= reach) : (dx += 1) {
                    const sx = x + dx;
                    const sy = y + dy;
                    const clear = sx < 0 or sy < 0 or sx >= w or sy >= h or !solid[@intCast(sy * w + sx)];
                    if (clear) near2 = @min(near2, dx * dx + dy * dy);
                }
            }
            const t = std.math.clamp((@sqrt(@as(f32, @floatFromInt(near2))) - 0.5) / @as(f32, @floatFromInt(BEVEL_PX)), 0, 1);
            height[i] = @sqrt(1 - (t - 1) * (t - 1));
        }
    }
    var px: [ART_MAX * ART_MAX]rl.Color = undefined;
    y = 0;
    while (y < h) : (y += 1) {
        var x: i32 = 0;
        while (x < w) : (x += 1) {
            const gx = texel(&height, w, h, x + 1, y) - texel(&height, w, h, x - 1, y);
            const gy = texel(&height, w, h, x, y + 1) - texel(&height, w, h, x, y - 1);
            const n = Rgb{ -gx * BEVEL_DEPTH, -gy * BEVEL_DEPTH, 1 };
            const unit = n / splat(@sqrt(@reduce(.Add, n * n)));
            px[@intCast(y * w + x)] = colourOf(unit * splat(0.5) + splat(0.5), 1);
        }
    }
    return look.clamped(look.rgba(&px, w, h), .point);
}

fn glowAlpha(dx: f32, dy: f32) f32 {
    const r2 = @min(1, dx * dx + dy * dy);
    return (1 - r2) * (1 - r2) * @exp(-3 * r2);
}

test "a lamp pools light on the ground below it, falling to nothing at its reach" {
    const l = try Light.create(std.testing.allocator);
    defer std.testing.allocator.destroy(l);
    l.add(.{ .at = .{ 0, 0 }, .z = 1.0, .colour = .{ 1.3, 0.8, 0.4 }, .reach = 7.5 });
    std.debug.print("lamp light on the ground by cells out:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0, 1, 2, 3, 4, 5, 6, 7, 7.5 }) |r| {
        const v = lum(l.at(.{ r, 0 })) - lum(AMBIENT);
        std.debug.print(" {d}:{d:.3}", .{ r, v });
        try std.testing.expect(v <= last);
        last = v;
    }
    std.debug.print("\n", .{});
    try std.testing.expect(lum(l.at(.{ 0, 0 })) - lum(AMBIENT) > 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last, 1e-5);
}

test "the baked map matches the light at a texel's middle" {
    const l = try Light.create(std.testing.allocator);
    defer std.testing.allocator.destroy(l);
    l.add(.{ .at = .{ 3.2, 2.1 }, .z = 1.6, .colour = .{ 1, 1, 1 }, .reach = 9 });
    l.bake(.{ -10, -6 }, .{ 15, 8 });
    const sub: f32 = @floatFromInt(SUB);
    const tx: i32 = 40;
    const ty: i32 = 30;
    const q = V{ (@as(f32, @floatFromInt(l.origin.x + tx)) + 0.5) / sub, (@as(f32, @floatFromInt(l.origin.y + ty)) + 0.5) / sub };
    const baked = l.acc[@intCast(ty * l.w + tx)];
    try std.testing.expectApproxEqAbs(lum(l.at(q)), lum(baked), 1e-4);
    try std.testing.expect(l.w * l.h <= MAP_W * MAP_H);
}
