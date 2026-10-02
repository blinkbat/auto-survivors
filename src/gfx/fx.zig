const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const run = @import("../play/run.zig");
const foe = @import("../play/foe.zig");
const light = @import("light.zig");
const look = @import("look.zig");

// EVERY EVENT'S AFTERMATH: gore, mist and stains on the ground, lit by the light map; sparks, embers and bursts of
// light over it; the shake of a heavy blow. Nothing in the simulation reads any of it.

const V = mathx.V;
const Rgb = light.Rgb;
const MOTES: usize = 2400;
const RINGS: usize = 192;
const STAINS: usize = 480;
const STAIN_S: f32 = 14;
const STAIN_FADE: f32 = 0.35;
const GRAV: f32 = 9;
/// A fan this wide throws every way.
const ROUND: f32 = 3.1;
/// Pixels of shake, and how fast it dies, per second.
const SHAKE_MAX: f32 = 14;
const SHAKE_DECAY: f32 = 9;
const CRIT_SHAKE: f32 = 6;
const BEAMS: usize = 16;
const BEAM_S: f32 = 0.4;
const SONG = rl.Color{ .r = 255, .g = 160, .b = 230, .a = 255 };
const GRAVE_GLOW = rl.Color{ .r = 120, .g = 255, .b = 160, .a = 255 };
const GRAVE_SMOKE = rl.Color{ .r = 40, .g = 60, .b = 50, .a = 140 };
const BONE = rl.Color{ .r = 220, .g = 214, .b = 196, .a = 230 };
const LEAF = rl.Color{ .r = 150, .g = 230, .b = 110, .a = 255 };
const VENOM = rl.Color{ .r = 190, .g = 230, .b = 60, .a = 255 };
const SOIL = rl.Color{ .r = 70, .g = 52, .b = 34, .a = 200 };
const STOPPED = rl.Color{ .r = 170, .g = 210, .b = 255, .a = 255 };
const MEND = rl.Color{ .r = 170, .g = 255, .b = 160, .a = 255 };
pub const CHARM_RGB = Rgb{ 1.0, 0.45, 0.85 };

/// A lobbed shell's fire, in flight and where it lands.
pub fn shellHue(warned: bool) Rgb {
    return if (warned) .{ 0.85, 0.35, 1.0 } else .{ 1.0, 0.55, 0.2 };
}

pub const Look = enum { drop, chunk, mist, spark, ember, smoke, glint };

pub const Mote = struct {
    /// Cells: x, y on the ground and z up off it.
    p: [3]f32,
    v: [3]f32,
    life: f32 = 0,
    max: f32 = 1,
    /// Pixels.
    r: f32,
    col: rl.Color,
    end: rl.Color,
    kind: Look,
    grav: f32 = GRAV,
    drag: f32 = 3,

    fn lit(m: Mote) bool {
        return m.kind == .spark or m.kind == .ember or m.kind == .glint;
    }
};

pub const Ring = struct {
    at: V,
    r0: f32,
    r1: f32,
    life: f32 = 0,
    max: f32,
    colour: Rgb,
    a: f32,
};

pub const Beam = struct { from: V, to: V, life: f32 = 0, max: f32 = BEAM_S, colour: Rgb = .{ 0.4, 1.0, 0.45 }, width: f32 = 7 };

pub const Stain = struct { at: V, r: f32, dir: V, stretch: f32, life: f32 = 0, col: rl.Color };

const BLOOD_LO = rl.Color{ .r = 70, .g = 8, .b = 8, .a = 235 };
const EMBER_HOT = rl.Color{ .r = 255, .g = 236, .b = 150, .a = 255 };
const EMBER_COOL = rl.Color{ .r = 200, .g = 40, .b = 10, .a = 0 };
const SPARK_HOT = rl.Color{ .r = 255, .g = 250, .b = 220, .a = 255 };
const SPARK_COOL = rl.Color{ .r = 255, .g = 140, .b = 40, .a = 0 };
const SMOKE = rl.Color{ .r = 30, .g = 26, .b = 26, .a = 120 };
const SCORCH = rl.Color{ .r = 18, .g = 12, .b = 10, .a = 170 };

fn darker(c: rl.Color, k: f32) rl.Color {
    return .{ .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * k), .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * k), .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * k), .a = c.a };
}

fn mix(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const k = std.math.clamp(t, 0, 1);
    return .{
        .r = @intFromFloat(mathx.lerpF(@floatFromInt(a.r), @floatFromInt(b.r), k)),
        .g = @intFromFloat(mathx.lerpF(@floatFromInt(a.g), @floatFromInt(b.g), k)),
        .b = @intFromFloat(mathx.lerpF(@floatFromInt(a.b), @floatFromInt(b.b), k)),
        .a = @intFromFloat(mathx.lerpF(@floatFromInt(a.a), @floatFromInt(b.a), k)),
    };
}

/// The oldest of a full ring of them gives way.
fn overwrite(comptime T: type, buf: []T, head: *usize, v: T) void {
    buf[head.*] = v;
    head.* = (head.* + 1) % buf.len;
}

/// A foe's size, for how much of it there is to spill.
fn bulk(k: ?foe.Kind) f32 {
    return switch (k orelse return 1) {
        .bat => 0.6,
        .ghoul, .spitter, .imp, .hound, .warlock => 1,
        .husk, .charger => 1.4,
        .shellback => 1.8,
        .brute => 2,
        .boss => 3.5,
    };
}

pub const Fx = struct {
    motes: [MOTES]Mote = undefined,
    mote_head: usize = 0,
    rings: [RINGS]Ring = undefined,
    ring_head: usize = 0,
    stains: [STAINS]Stain = undefined,
    stain_head: usize = 0,
    rng: mathx.Rng = mathx.Rng.init(0xF1A5),
    beams: [BEAMS]Beam = undefined,
    beam_head: usize = 0,
    shake: f32 = 0,
    t: f32 = 0,

    pub fn clear(self: *Fx) void {
        for (&self.motes) |*m| m.life = 0;
        for (&self.rings) |*r| r.life = 0;
        for (&self.stains) |*s| s.life = 0;
        for (&self.beams) |*b| b.life = 0;
        self.shake = 0;
    }

    fn mote(self: *Fx, m: Mote) void {
        overwrite(Mote, &self.motes, &self.mote_head, m);
    }

    fn ring(self: *Fx, r: Ring) void {
        overwrite(Ring, &self.rings, &self.ring_head, r);
    }

    fn stain(self: *Fx, at: V, r: f32, dir: V, stretch: f32, col: rl.Color) void {
        overwrite(Stain, &self.stains, &self.stain_head, .{ .at = at, .r = r, .dir = dir, .stretch = stretch, .life = STAIN_S, .col = col });
    }

    fn jolt(self: *Fx, px: f32) void {
        self.shake = @min(SHAKE_MAX, @max(self.shake, px));
    }

    fn heading(self: *Fx, dir: V, fan: f32) V {
        const base = if (mathx.len2(dir) > 0) mathx.headingOf(dir) else self.rng.unit() * mathx.TAU;
        return mathx.fromHeading(base + (self.rng.unit() * 2 - 1) * fan);
    }

    /// `n` of `kind` thrown along `dir`, fanned `fan` either side, `speed` cells a second.
    fn throw(self: *Fx, kind: Look, at: V, z: f32, dir: V, n: usize, speed: f32, fan: f32, col: rl.Color) void {
        for (0..n) |_| {
            const d = self.heading(dir, fan);
            const s = speed * self.rng.span(0.35, 1.25);
            var m = Mote{
                .p = .{ at[0], at[1], z },
                .v = .{ d[0] * s, d[1] * s, 0 },
                .r = 2,
                .col = col,
                .end = col,
                .kind = kind,
            };
            switch (kind) {
                .drop => {
                    m.v[2] = self.rng.span(0.8, 2.6);
                    m.r = self.rng.span(1.6, 3.4);
                    m.life = self.rng.span(0.35, 0.8);
                },
                .chunk => {
                    m.v[2] = self.rng.span(1.6, 3.2);
                    m.r = self.rng.span(3.2, 5.5);
                    m.col = darker(col, 0.75);
                    m.end = m.col;
                    m.grav = 12;
                    m.drag = 1.5;
                    m.life = self.rng.span(0.5, 0.9);
                },
                .mist => {
                    m.v = .{ d[0] * s * 0.35, d[1] * s * 0.35, 0.2 };
                    m.r = self.rng.span(8, 15);
                    m.col = look.fade(col, 0.45);
                    m.end = look.fade(col, 0);
                    m.grav = 0;
                    m.drag = 4;
                    m.life = self.rng.span(0.25, 0.45);
                },
                .spark => {
                    m.v[2] = self.rng.span(0.4, 1.8);
                    m.r = self.rng.span(1.2, 2.2);
                    m.end = SPARK_COOL;
                    m.grav = 5;
                    m.drag = 2.5;
                    m.life = self.rng.span(0.15, 0.4);
                },
                .ember => {
                    m.v[2] = self.rng.span(0.3, 1.2);
                    m.r = self.rng.span(1.4, 3.0);
                    m.end = EMBER_COOL;
                    m.grav = -self.rng.span(0.6, 1.8);
                    m.drag = 2;
                    m.life = self.rng.span(0.45, 1.1);
                },
                .glint => {
                    m.v = .{ d[0] * s * 0.2, d[1] * s * 0.2, 0.9 };
                    m.r = self.rng.span(1.4, 2.4);
                    m.end = look.fade(col, 0);
                    m.grav = 0;
                    m.drag = 1;
                    m.life = self.rng.span(0.5, 0.9);
                },
                .smoke => {
                    m.v = .{ d[0] * s * 0.3, d[1] * s * 0.3, 0.6 };
                    m.r = self.rng.span(7, 12);
                    m.end = look.fade(col, 0);
                    m.grav = -0.4;
                    m.drag = 1.5;
                    m.life = self.rng.span(0.6, 1.1);
                },
            }
            m.max = m.life;
            self.mote(m);
        }
    }

    fn burst(self: *Fx, at: V, r0: f32, r1: f32, s: f32, c: Rgb, a: f32) void {
        self.ring(.{ .at = at, .r0 = r0, .r1 = r1, .life = s, .max = s, .colour = c, .a = a });
    }

    fn bleed(self: *Fx, at: V, dir: V, k: f32, col: rl.Color, kill: bool) void {
        const n = @as(usize, @intFromFloat(k * @as(f32, if (kill) 22 else 8)));
        self.throw(.drop, at, 0.45, dir, n, 3.2, if (kill) 1.4 else 0.55, col);
        self.throw(.mist, at, 0.45, dir, if (kill) 2 else 1, 1.5, 0.5, col);
        if (!kill) return;
        self.throw(.chunk, at, 0.4, dir, @intFromFloat(k * 4), 2.6, 1.2, col);
        self.stain(at, 0.28 * @sqrt(k), .{ 1, 0 }, 1, darker(col, 0.8));
        for (0..@as(usize, @intFromFloat(k * 3))) |_| {
            const d = self.heading(dir, 0.6);
            self.stain(mathx.add(at, mathx.scale(d, self.rng.span(0.3, 0.9) * @sqrt(k))), self.rng.span(0.06, 0.12), d, self.rng.span(2, 4), col);
        }
    }

    pub fn take(self: *Fx, e: run.Event) void {
        switch (e.kind) {
            .hit => {
                const col = look.matter(e.foe);
                self.bleed(e.at, e.dir, bulk(e.foe) * @as(f32, if (e.big) 1.8 else 1), col, false);
                if (e.big) {
                    self.throw(.spark, e.at, 0.5, e.dir, 10, 5, 0.8, SPARK_HOT);
                    self.burst(e.at, 0.1, 0.7, 0.18, .{ 1, 0.9, 0.6 }, 0.9);
                }
                if (e.crit) self.jolt(CRIT_SHAKE);
            },
            .kill => {
                const k = bulk(e.foe);
                self.bleed(e.at, e.dir, k, look.matter(e.foe), true);
            },
            .hurt => {
                self.bleed(e.at, e.dir, 1.2, look.matter(null), false);
            },
            .fall => {
                self.bleed(e.at, .{ 0, 0 }, 2.5, look.matter(null), true);
                self.burst(e.at, 0.2, 1.8, 0.6, .{ 1, 0.3, 0.2 }, 0.35);
            },
            .block => {
                self.throw(.spark, e.at, 0.5, mathx.scale(e.dir, -1), 12, 4.5, 0.9, look.SHIELD);
                self.burst(e.at, 0.1, 0.65, 0.22, .{ 0.6, 0.8, 1.0 }, 1);
            },
            .blast => {
                const k: f32 = if (e.big) @as(f32, 1.8) else 1;
                self.throw(.ember, e.at, 0.4, .{ 0, 0 }, @intFromFloat(16 * k), 3.4, ROUND, EMBER_HOT);
                self.throw(.spark, e.at, 0.4, e.dir, @intFromFloat(8 * k), 5, 1.1, SPARK_HOT);
                self.throw(.smoke, e.at, 0.4, .{ 0, 0 }, 2, 1, ROUND, SMOKE);
                self.burst(e.at, 0.15, @max(e.amount, 0.6) * 1.1 * k, 0.28, .{ 1.0, 0.55, 0.18 }, 1);
                self.burst(e.at, 0.1, 0.45 * k, 0.12, .{ 1.0, 0.95, 0.7 }, 1);
                self.stain(e.at, 0.3 * k, .{ 1, 0 }, 1, SCORCH);
            },
            .cast => self.throw(.ember, e.at, 0.7, .{ 0, 0 }, 5, 1.4, ROUND, EMBER_HOT),
            .heal => self.burst(e.at, 0.1, 0.5, 0.35, .{ 0.5, 1.0, 0.45 }, 0.5),
            .pulse => self.burst(e.at, 0.3, e.amount, 0.55, .{ 1.0, 0.92, 0.6 }, 0.2),
            .wave => self.burst(e.at, 0.3, e.amount, 0.35, .{ 1.0, 0.75, 0.3 }, 0.25),
            .lifeline => self.beam(e.from, e.at),
            .sprout => {
                self.burst(e.at, 0.1, 0.7, 0.35, .{ 0.45, 0.9, 0.35 }, 0.3);
                self.throw(.glint, e.at, 0.1, .{ 0, 0 }, 10, 1.2, ROUND, LEAF);
                self.throw(.mist, e.at, 0.1, .{ 0, 0 }, 2, 1, ROUND, SOIL);
            },
            .lash => {
                self.beamOf(.{ .from = .{ e.from[0], e.from[1] + 0.15 }, .to = .{ e.at[0], e.at[1] + 0.3 }, .life = run.LASH_S, .max = run.LASH_S, .colour = if (e.big) .{ 0.7, 0.95, 0.2 } else .{ 0.35, 0.8, 0.3 }, .width = 5 });
            },
            .poison => self.throw(.glint, e.at, 0.4, .{ 0, 0 }, 3, 0.6, ROUND, VENOM),
            .strum => {
                self.burst(e.at, 0.2, e.amount, 0.5, .{ 1.0, 0.55, 0.9 }, 0.35);
                self.throw(.glint, e.at, 0.3, .{ 0, 0 }, 14, e.amount * 1.4, ROUND, SONG);
            },
            .charm => {
                self.throw(.glint, e.at, 0.6, .{ 0, 0 }, 8, 0.8, ROUND, SONG);
                self.burst(e.at, 0.1, 0.6, 0.3, CHARM_RGB, 0.8);
            },
            .raise => {
                self.burst(e.at, 0.1, 0.8, 0.45, .{ 0.4, 1.0, 0.6 }, 0.7);
                self.throw(.smoke, e.at, 0.1, .{ 0, 0 }, 3, 0.8, ROUND, GRAVE_SMOKE);
                self.throw(.glint, e.at, 0.2, .{ 0, 0 }, 8, 0.8, ROUND, GRAVE_GLOW);
            },
            .revive => {
                self.burst(e.at, 0.2, 1.6, 0.8, .{ 0.4, 1.0, 0.6 }, 0.6);
                self.throw(.smoke, e.at, 0.1, .{ 0, 0 }, 4, 1, ROUND, GRAVE_SMOKE);
                self.throw(.glint, e.at, 0.3, .{ 0, 0 }, 18, 1.2, ROUND, GRAVE_GLOW);
            },
            .crumble => {
                self.throw(.chunk, e.at, 0.4, .{ 0, 0 }, 9, 2.2, ROUND, BONE);
                self.throw(.mist, e.at, 0.3, .{ 0, 0 }, 2, 1, ROUND, BONE);
            },
            .boom => {
                self.burst(e.at, 0.2, e.amount, 0.35, shellHue(e.big), 1);
                self.throw(.ember, e.at, 0.2, .{ 0, 0 }, @intFromFloat(10 + 12 * e.amount), 2.5 * e.amount, ROUND, EMBER_HOT);
                self.throw(.smoke, e.at, 0.2, .{ 0, 0 }, @intFromFloat(2 + 2 * e.amount), e.amount, ROUND, SMOKE);
                self.stain(e.at, 0.45 * e.amount, .{ 1, 0 }, 1, SCORCH);
            },
            .stop => {
                self.burst(e.at, 0.2, e.amount, 0.45, .{ 0.6, 0.8, 1.0 }, 0.45);
                self.throw(.glint, e.at, 0.3, .{ 0, 0 }, 16, e.amount * 1.6, ROUND, STOPPED);
            },
            .level => {
                self.burst(e.at, 0.2, 1.2, 0.7, .{ 1.0, 0.85, 0.4 }, 0.35);
                self.throw(.spark, e.at, 0.2, .{ 0, 0 }, 14, 2, ROUND, look.BRIGHT);
            },
            .recruit => self.burst(e.at, 0.4, 3.0, 0.9, .{ 1.0, 0.85, 0.4 }, 0.3),
            .merge => self.burst(e.at, 0.3, 2.0, 0.8, .{ 0.9, 0.95, 1.0 }, 0.4),
            .smite => self.throw(.spark, e.at, 0.5, .{ 0, 0 }, 3, 1.5, ROUND, look.BRIGHT),
            .swing, .boss, .burn, .loose, .spit, .lob => {},
        }
    }

    /// `rate` a second, on average, over this frame.
    fn some(self: *Fx, rate: f32, dt: f32) usize {
        const want = rate * dt;
        var n: usize = @intFromFloat(@floor(want));
        if (self.rng.unit() < want - @floor(want)) n += 1;
        return n;
    }

    /// `rate` motes a second, each from up to `spread` cells off `at`, `z` cells up.
    fn seep(self: *Fx, kind: Look, at: V, z: f32, spread: f32, speed: f32, col: rl.Color, rate: f32, dt: f32) void {
        for (0..self.some(rate, dt)) |_| {
            const off = mathx.scale(mathx.fromHeading(self.rng.unit() * mathx.TAU), self.rng.unit() * spread);
            self.throw(kind, mathx.add(at, off), z, .{ 0, 0 }, 1, speed, ROUND, col);
        }
    }

    /// Embers off something burning at `at`, `z` cells up.
    pub fn smoulder(self: *Fx, at: V, z: f32, rate: f32, spread: f32, dt: f32) void {
        self.seep(.ember, at, z, spread, 0.5, EMBER_HOT, rate, dt);
    }

    /// Pale green motes rising off a hero mending itself.
    pub fn mend(self: *Fx, at: V, rate: f32, dt: f32) void {
        self.seep(.glint, at, 0.3, 0.3, 0.3, MEND, rate, dt);
    }

    /// Sickly bubbles off a poisoned foe.
    pub fn fester(self: *Fx, at: V, rate: f32, dt: f32) void {
        self.seep(.glint, at, 0.4, 0.25, 0.2, VENOM, rate, dt);
    }

    fn beam(self: *Fx, from: V, to: V) void {
        self.beamOf(.{ .from = from, .to = to, .life = BEAM_S });
    }

    fn beamOf(self: *Fx, b: Beam) void {
        overwrite(Beam, &self.beams, &self.beam_head, b);
    }

    pub fn step(self: *Fx, dt: f32) void {
        self.t += dt;
        for (&self.motes) |*m| {
            if (m.life <= 0) continue;
            m.life -= dt;
            const k = @exp(-m.drag * dt);
            m.v[0] *= k;
            m.v[1] *= k;
            m.v[2] -= m.grav * dt;
            for (0..3) |i| m.p[i] += m.v[i] * dt;
            if (m.p[2] <= 0 and m.grav > 0) {
                m.p[2] = 0;
                if ((m.kind == .drop or m.kind == .chunk) and m.life > 0) {
                    const sp = mathx.len(.{ m.v[0], m.v[1] });
                    const d = if (sp > 0.01) mathx.scale(.{ m.v[0], m.v[1] }, 1 / sp) else V{ 1, 0 };
                    self.stain(.{ m.p[0], m.p[1] }, m.r / @as(f32, look.SPRITE_PX) * 1.6, d, 1 + @min(3, sp * 0.8), m.col);
                }
                m.life = 0;
            }
        }
        for (&self.rings) |*r| r.life = @max(0, r.life - dt);
        for (&self.stains) |*s| s.life = @max(0, s.life - dt);
        for (&self.beams) |*b| b.life = @max(0, b.life - dt);
        self.shake = @max(0, self.shake - self.shake * SHAKE_DECAY * dt - dt);
    }

    /// Pixels to move the view this frame.
    pub fn offset(self: *const Fx) V {
        if (self.shake <= 0) return .{ 0, 0 };
        return .{ @sin(self.t * 71) * self.shake, @cos(self.t * 59) * self.shake * 0.8 };
    }

    /// Before the light map, which lights it. `cam` is the world pixel at the screen's top-left.
    pub fn drawGround(self: *const Fx, cam: V, cell: f32) void {
        for (self.stains) |s| {
            if (s.life <= 0) continue;
            const a = @min(1, s.life / (STAIN_S * STAIN_FADE));
            const c = look.fade(s.col, a * 0.8);
            const n: usize = if (s.stretch > 1.3) 4 else 1;
            for (0..n) |i| {
                const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                const at = mathx.add(s.at, mathx.scale(s.dir, t * s.r * s.stretch));
                const r = s.r * cell * (1 - t * 0.6);
                rl.drawEllipse(@intFromFloat(at[0] * cell - cam[0]), @intFromFloat(at[1] * cell - cam[1]), r, r * 0.6, c);
            }
        }
        for (self.motes) |m| {
            if (m.life <= 0 or m.lit()) continue;
            const t = 1 - m.life / m.max;
            const x = m.p[0] * cell - cam[0];
            const y = (m.p[1] - m.p[2]) * cell - cam[1];
            const r = if (m.kind == .mist or m.kind == .smoke) m.r * (1 + t) else m.r;
            const col = if (m.kind == .drop or m.kind == .chunk) mix(m.col, BLOOD_LO, t) else mix(m.col, m.end, t);
            if (m.kind == .drop) {
                const tail = V{ x - m.v[0] * 0.02 * cell, y - (m.v[1] - m.v[2]) * 0.02 * cell };
                rl.drawLineEx(.{ .x = tail[0], .y = tail[1] }, .{ .x = x, .y = y }, r * 1.3, col);
            }
            rl.drawCircleV(.{ .x = x, .y = y }, r, col);
        }
    }

    pub fn drawLight(self: *const Fx, l: *const light.Light, cam: V, cell: f32) void {
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (self.rings) |r| {
            if (r.life <= 0) continue;
            const t = 1 - r.life / r.max;
            const rad = mathx.lerpF(r.r0, r.r1, mathx.smooth(t)) * cell;
            const x = r.at[0] * cell - cam[0];
            const y = r.at[1] * cell - cam[1];
            const a = r.a * (1 - t);
            l.glow(x, y, rad, r.colour, a);
        }
        for (self.beams) |b| {
            if (b.life <= 0) continue;
            const a = b.life / b.max;
            const p = V{ b.from[0] * cell - cam[0], (b.from[1] - 0.3) * cell - cam[1] };
            const q = V{ b.to[0] * cell - cam[0], (b.to[1] - 0.3) * cell - cam[1] };
            rl.drawLineEx(.{ .x = p[0], .y = p[1] }, .{ .x = q[0], .y = q[1] }, b.width, light.colourOf(b.colour, a * 0.35));
            rl.drawLineEx(.{ .x = p[0], .y = p[1] }, .{ .x = q[0], .y = q[1] }, 2.5, light.colourOf(.{ 0.8, 1.0, 0.8 }, a));
            l.glow(q[0], q[1], 22, .{ 0.5, 1.0, 0.5 }, a * 0.8);
        }
        for (self.motes) |m| {
            if (m.life <= 0 or !m.lit()) continue;
            const t = 1 - m.life / m.max;
            const x = m.p[0] * cell - cam[0];
            const y = (m.p[1] - m.p[2]) * cell - cam[1];
            const hot = switch (m.kind) {
                .ember => EMBER_HOT,
                .glint => m.col,
                else => SPARK_HOT,
            };
            const col = mix(hot, m.end, t);
            if (m.kind == .spark) {
                const tail = V{ x - m.v[0] * 0.035 * cell, y - (m.v[1] - m.v[2]) * 0.035 * cell };
                rl.drawLineEx(.{ .x = tail[0], .y = tail[1] }, .{ .x = x, .y = y }, m.r, col);
            } else {
                l.glow(x, y, m.r * 4, .{ 1.0, 0.45, 0.12 }, (1 - t) * 0.35);
                rl.drawCircleV(.{ .x = x + @sin(self.t * 9 + m.p[0] * 13) * 1.5, .y = y }, m.r * (1 - t * 0.5), col);
            }
        }
    }
};

test "a kill's spray lands as stains and every mote is gone within a second" {
    var f = Fx{};
    f.clear();
    f.take(.{ .kind = .kill, .at = .{ 1, 1 }, .dir = .{ 1, 0 }, .foe = .ghoul });
    for (0..60) |_| f.step(1.0 / 60.0);
    var stains: usize = 0;
    for (f.stains) |s| stains += @intFromBool(s.life > 0);
    var live: usize = 0;
    for (f.motes) |m| live += @intFromBool(m.life > 0);
    std.debug.print("a ghoul's death: {d} stains a second on, {d} motes still flying\n", .{ stains, live });
    try std.testing.expect(stains > 8);
    try std.testing.expectEqual(@as(usize, 0), live);
}

test "only a critical hit shakes the view, and the shake dies" {
    var f = Fx{};
    f.clear();
    for ([_]run.EventKind{ .fall, .kill, .hurt, .blast, .boss }) |k| f.take(.{ .kind = k, .at = .{ 0, 0 }, .big = true, .foe = .brute });
    f.take(.{ .kind = .hit, .at = .{ 0, 0 }, .big = true, .foe = .brute });
    try std.testing.expectEqual(@as(f32, 0), f.shake);
    f.take(.{ .kind = .hit, .at = .{ 0, 0 }, .crit = true, .foe = .ghoul });
    const first = f.shake;
    var t: f32 = 0;
    while (f.shake > 0 and t < 2) : (t += 1.0 / 60.0) f.step(1.0 / 60.0);
    std.debug.print("a crit shakes {d:.0} px, still in {d:.2} s\n", .{ first, t });
    try std.testing.expect(first > 0 and t < 1);
}
