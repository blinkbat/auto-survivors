const std = @import("std");
const rl = @import("raylib");
const mathx = @import("core/mathx.zig");
const input = @import("core/input.zig");
const formation = @import("play/formation.zig");
const hero = @import("play/hero.zig");
const foe = @import("play/foe.zig");
const run = @import("play/run.zig");
const look = @import("gfx/look.zig");
const font = @import("gfx/font.zig");
const light = @import("gfx/light.zig");
const fx = @import("gfx/fx.zig");
const numbers = @import("gfx/numbers.zig");
const hud = @import("ui/hud.zig");
const audio = @import("sound/audio.zig");

const V = mathx.V;
const Rgb = light.Rgb;

pub const CELL: f32 = @floatFromInt(look.SPRITE_PX);
const WINDOW_W: i32 = 1600;
const WINDOW_H: i32 = 900;
const CAM_EASE: f32 = 7;
/// A frame longer than this is simulated as this long.
const MAX_FRAME: f32 = 0.25;
const SHOTS_DIR = "shots";
const POSE_T: f32 = 150;
const POSE_FOES: usize = 60;
pub const SHOT_SEED: u64 = 0x5EED_2026;

/// Cells between brazier lattice points, and the share of points that hold one.
const BRAZIER_GAP: f32 = 9;
const BRAZIER_ODDS: f32 = 0.5;
const BRAZIER_SEED: u32 = 0xB7A2;
/// Of a sprite's height, how far above its ground point the art's top sits.
const STAND: f32 = 0.66;
const BOB_PX: f32 = 3;
const BOB_HZ: f32 = 1.9;
const BRAZIER_MAX: usize = 64;
const MAX_FIGS: usize = formation.SLOTS + run.MAX_FOES + BRAZIER_MAX + run.MAX_SKELETONS + run.MAX_VINES + run.MAX_BANNERS;
/// Of a swing, the share spent drawing back, and cells back and forward.
const LUNGE_WIND: f32 = 0.2;
const LUNGE_BACK: f32 = 0.1;
const LUNGE_REACH: f32 = 0.34;
const LUNGE_STRETCH: f32 = 0.14;
/// Cells a shooter rocks back as it looses, over seconds.
const RECOIL: f32 = 0.09;
const RECOIL_S: f32 = 0.14;
const HURT_RECOIL: f32 = 0.16;
const SQUASH: f32 = 0.14;
/// Cells a bite lunges.
const JAB: f32 = 0.26;
const BURN_FLASH: f32 = 0.18;
/// Of a swing, the share its blade sweeps over.
const SLASH_SWEEP: f32 = 0.55;
const SLASH_SEGS: usize = 14;
const EMBER_TRAIL: f32 = 70;
const EMBER_BURNING: f32 = 16;
const EMBER_BRAZIER: f32 = 6;
/// How close a level-up zooms, how fast it eases there and back, and cells above the hero's feet it centres on.
const ZOOM: f32 = 2.6;
const ZOOM_EASE: f32 = 6;
const ZOOM_LIFT: f32 = 0.25;
/// Seconds before a Time Stop ends that its frost starts to fade.
const FROZEN_FADE: f32 = 0.4;
/// Seconds a vine takes to grow in and to wither, and cells its lash lunges.
const VINE_GROW_S: f32 = 0.35;
const VINE_LUNGE: f32 = 0.3;
const ROOTS = look.rgb(0x1e2e14);
const WARN = look.rgb(0xe8423a);
const POISON_RATE: f32 = 6;
const NOTES: usize = 6;
const NOTE_RGB = Rgb{ 1.0, 0.7, 0.95 };
/// Seconds a bard's music takes to fade in and to fade out.
const CLOUD_IN_S: f32 = 0.3;
const CLOUD_OUT_S: f32 = 0.6;
/// Green motes a second off a hero mending itself.
const MEND_RATE: f32 = 9;
/// Xp past which an orb is drawn larger.
const BIG_ORB: f32 = 1.5;

const PARTY_LAMP = Rgb{ 0.85, 0.80, 0.72 };
const PARTY_REACH: f32 = 11;
const PARTY_Z: f32 = 1.6;
const FLAME = Rgb{ 1.30, 0.80, 0.40 };
const FLAME_SHIFT = Rgb{ 1.0, 1.6, 2.4 };
const BRAZIER_REACH: f32 = 7.5;
const BRAZIER_Z: f32 = 1.0;
/// Cells above its ground point the brazier's fire burns.
const BRAZIER_FIRE: f32 = 0.42;
const BOLT_LAMP = Rgb{ 0.9, 0.5, 0.2 };
const BOLT_Z: f32 = 0.4;
const BOLT_REACH: f32 = 2.8;
const SPIT_LAMP = Rgb{ 0.25, 0.5, 0.18 };
const SPIT_Z: f32 = 0.3;
const SPIT_REACH: f32 = 1.8;
const BOSS_SPIT_LAMP = Rgb{ 0.7, 0.08, 0.1 };
const BOSS_SPIT_REACH: f32 = 2.6;
const BOSS_LAMP = Rgb{ 0.25, 0.8, 0.45 };
const BOSS_Z: f32 = 1.2;
const BOSS_REACH: f32 = 5;
const SPIT_LAMPS: usize = 40;

pub const Mode = enum { title, play, level, place, recruit, pause, options, over };
pub const TitleRow = enum { start, options, quit };
pub const TITLE_ROWS = std.enums.values(TitleRow);
pub const Placing = union(enum) { move: u32, recruit: hero.Class };
pub const PauseRow = enum { resume_play, restart, options, quit };
pub const PAUSE_ROWS = std.enums.values(PauseRow);
pub const OptionRow = enum { mute, music, sfx, fullscreen, back };
pub const VOL_STEP: f32 = 0.1;
pub const OPTION_ROWS = std.enums.values(OptionRow);
pub const CHOICES: usize = 3;

pub const Fig = struct {
    tex: rl.Texture2D,
    dest: rl.Rectangle,
    mid: V,
    left: bool,
    flash: f32,
    shine: light.Shine,
    ground: f32,
};

pub const Game = struct {
    run: *run.Run,
    light: *light.Light,
    fx: fx.Fx,
    numbers: numbers.Numbers,
    audio: audio.Audio,
    st: input.State,
    mode: Mode,
    screen: mathx.P,
    cam: V,
    t: f32,
    acc: f32,
    sprites: look.Sprites,
    face: font.Face,
    left: bool,
    offer: hero.Offer,
    pick: usize,
    placing: Placing,
    cursor: formation.Slot,
    from: Mode,
    choices: [CHOICES]hero.Class,
    pause_row: usize,
    title_row: usize,
    /// Where Options goes back to.
    options_from: Mode,
    option_row: usize,
    muted: bool,
    refused: f32,
    /// 0 out, 1 zoomed in on `focus` for a level-up.
    zoom: f32,
    focus: V,
    quit: bool,
    figs: [MAX_FIGS]Fig,

    /// World pixel at the screen's top-left.
    pub fn origin(g: *const Game) V {
        const s = g.fx.offset();
        return .{
            @round(g.cam[0] * CELL - @as(f32, @floatFromInt(g.screen.x)) * 0.5 + s[0]),
            @round(g.cam[1] * CELL - @as(f32, @floatFromInt(g.screen.y)) * 0.5 + s[1]),
        };
    }

    pub fn px(g: *const Game, q: V) V {
        const o = g.origin();
        return .{ q[0] * CELL - o[0], q[1] * CELL - o[1] };
    }
};

pub fn boot(alloc: std.mem.Allocator, seed: u64) !*Game {
    const g = try alloc.create(Game);
    g.run = try run.Run.create(alloc, seed);
    g.light = try light.Light.create(alloc);
    g.fx = .{};
    g.fx.clear();
    g.numbers = .{};
    g.numbers.clear();
    g.audio = .{};
    g.st = .{};
    g.mode = .play;
    g.screen = .{ .x = WINDOW_W, .y = WINDOW_H };
    g.cam = g.run.party;
    g.t = 0;
    g.acc = 0;
    g.sprites = .{};
    g.face = .{};
    g.left = false;
    g.offer = .{};
    g.pick = 0;
    g.placing = .{ .recruit = .knight };
    g.cursor = formation.CENTRE;
    g.from = .play;
    g.choices = .{ .knight, .archer, .cleric };
    g.pause_row = 0;
    g.title_row = 0;
    g.options_from = .pause;
    g.option_row = 0;
    g.muted = false;
    g.refused = 0;
    g.zoom = 0;
    g.focus = .{ 0, 0 };
    g.quit = false;
    return g;
}

pub fn shut(alloc: std.mem.Allocator, g: *Game) void {
    alloc.destroy(g.run);
    alloc.destroy(g.light);
    alloc.destroy(g);
}

pub fn freshSeed() u64 {
    return @bitCast(std.time.milliTimestamp());
}

pub fn restart(g: *Game, seed: u64) void {
    g.run.reset(seed);
    g.fx.clear();
    g.numbers.clear();
    g.cam = g.run.party;
    g.mode = .play;
    g.acc = 0;
    g.left = false;
}

fn drain(g: *Game) void {
    for (g.run.drainEvents()) |e| {
        g.fx.take(e);
        g.numbers.take(e);
        g.audio.take(e);
    }
}

/// A waiting level-up first, then a waiting recruit.
fn openMenus(g: *Game) void {
    if (g.run.outcome != .running) {
        if (g.mode != .over) g.audio.play(if (g.run.outcome == .won) .victory else .defeat);
        g.mode = .over;
        return;
    }
    if (g.run.levelHead()) |m| {
        g.offer = hero.offer(m.hero, &g.run.rng);
        g.pick = 0;
        g.mode = .level;
        return;
    }
    while (g.run.recruits > 0) {
        g.choices = hero.draft(CHOICES, &g.run.rng);
        g.pick = 0;
        for (g.choices, 0..) |c, i| {
            if (g.run.canRecruit(c)) {
                g.pick = i;
                g.mode = .recruit;
                return;
            }
        }
        g.run.recruits -= 1;
    }
    g.mode = .play;
}

pub fn update(g: *Game, dt: f32) void {
    g.st.update(dt);
    if (g.st.fullscreen) rl.toggleBorderlessWindowed();
    g.screen = .{ .x = rl.getScreenWidth(), .y = rl.getScreenHeight() };
    step(g, dt);
}

/// Everything but reading the devices and the window, so a posed frame can drive it.
pub fn step(g: *Game, dt: f32) void {
    g.t += dt;
    g.refused = @max(0, g.refused - dt);
    if (g.mode != .play) {
        if (g.st.nav != null) g.audio.play(.tick);
        if (g.st.hit(.a)) g.audio.play(.confirm);
    }
    switch (g.mode) {
        .play => playStep(g, dt),
        .level => levelStep(g),
        .place => placeStep(g),
        .recruit => recruitStep(g),
        .title => titleStep(g),
        .pause => pauseStep(g),
        .options => optionsStep(g),
        .over => if (g.st.hit(.a)) restart(g, freshSeed()),
    }
    if (g.mode == .play or g.mode == .title) kindle(g, dt);
    g.fx.step(dt);
    g.numbers.step(dt);
    stepZoom(g, dt);
    const k = mathx.easing(dt, CAM_EASE);
    g.cam = mathx.lerpV(g.cam, g.run.party, k);
}

fn playStep(g: *Game, dt: f32) void {
    if (g.st.hit(.pause)) {
        g.pause_row = 0;
        g.mode = .pause;
        return;
    }
    g.acc += @min(dt, MAX_FRAME);
    while (g.acc >= run.STEP) {
        g.acc -= run.STEP;
        g.run.step(g.st.move);
        drain(g);
        if (g.run.levels.n > 0 or g.run.recruits > 0 or g.run.outcome != .running) {
            g.acc = 0;
            break;
        }
    }
    if (@abs(g.run.vel[0]) > 0.2) g.left = g.run.vel[0] < 0;
    if (g.run.levels.n > 0 or g.run.recruits > 0 or g.run.outcome != .running) openMenus(g);
}

fn sideways(n: ?input.Nav) i32 {
    return switch (n orelse return 0) {
        .left => -1,
        .right => 1,
        else => 0,
    };
}

/// A menu's row, moved up or down round its `n` rows.
fn rowNav(row: usize, n: usize, nav: ?input.Nav) usize {
    return switch (nav orelse return row) {
        .up => mathx.wrapIndex(row, -1, n),
        .down => mathx.wrapIndex(row, 1, n),
        else => row,
    };
}

fn levelStep(g: *Game) void {
    const m = g.run.levelHead() orelse return openMenus(g);
    const d = sideways(g.st.nav);
    if (d != 0) g.pick = mathx.wrapIndex(g.pick, d, g.offer.n);
    if (!g.st.hit(.a)) return;
    const card = g.offer.cards[g.pick];
    if (card == .move) {
        g.placing = .{ .move = m.id };
        g.cursor = m.slot;
        g.from = .level;
        g.mode = .place;
        return;
    }
    m.apply(card);
    g.run.popLevel();
    openMenus(g);
}

pub fn placeOf(g: *Game, s: formation.Slot) run.Run.Place {
    return switch (g.placing) {
        .move => |id| if (g.run.byId(id)) |m| g.run.placing(m.hero.class, s, id) else .refused,
        .recruit => |c| g.run.placing(c, s, null),
    };
}

fn placeStep(g: *Game) void {
    if (g.st.nav) |n| {
        const o = formation.offset(g.cursor);
        const p: mathx.P = switch (n) {
            .up => .{ .x = o.x, .y = @max(-1, o.y - 1) },
            .down => .{ .x = o.x, .y = @min(1, o.y + 1) },
            .left => .{ .x = @max(-1, o.x - 1), .y = o.y },
            .right => .{ .x = @min(1, o.x + 1), .y = o.y },
        };
        g.cursor = formation.at(p).?;
    }
    if (g.st.hit(.b)) {
        g.mode = g.from;
        return;
    }
    if (!g.st.hit(.a)) return;
    const done = switch (g.placing) {
        .move => |id| g.run.moveTo(id, g.cursor),
        .recruit => |c| g.run.recruit(c, g.cursor),
    };
    if (done == .refused) {
        g.refused = hud.REFUSED_S;
        return;
    }
    drain(g);
    if (g.placing == .move) g.run.popLevel();
    openMenus(g);
}

fn recruitStep(g: *Game) void {
    const d = sideways(g.st.nav);
    if (d != 0) g.pick = mathx.wrapIndex(g.pick, d, CHOICES);
    if (g.st.hit(.b)) {
        g.run.recruits -|= 1;
        openMenus(g);
        return;
    }
    if (!g.st.hit(.a)) return;
    const c = g.choices[g.pick];
    if (!g.run.canRecruit(c)) {
        g.refused = hud.REFUSED_S;
        return;
    }
    g.placing = .{ .recruit = c };
    g.from = .recruit;
    g.mode = .place;
    for (0..formation.SLOTS) |i| {
        const s: formation.Slot = @intCast(i);
        if (g.run.placing(c, s, null) != .refused) {
            g.cursor = s;
            break;
        }
    }
}

fn pauseStep(g: *Game) void {
    if (g.st.hit(.pause) or g.st.hit(.b)) {
        g.mode = .play;
        return;
    }
    g.pause_row = rowNav(g.pause_row, PAUSE_ROWS.len, g.st.nav);
    if (!g.st.hit(.a)) return;
    switch (PAUSE_ROWS[g.pause_row]) {
        .resume_play => g.mode = .play,
        .restart => restart(g, freshSeed()),
        .options => openOptions(g, .pause),
        .quit => g.quit = true,
    }
}

pub fn fullscreen() bool {
    return rl.isWindowState(.{ .borderless_windowed_mode = true });
}

fn openOptions(g: *Game, from: Mode) void {
    g.option_row = 0;
    g.options_from = from;
    g.mode = .options;
}

fn titleStep(g: *Game) void {
    g.title_row = rowNav(g.title_row, TITLE_ROWS.len, g.st.nav);
    if (!g.st.hit(.a)) return;
    switch (TITLE_ROWS[g.title_row]) {
        .start => restart(g, freshSeed()),
        .options => openOptions(g, .title),
        .quit => g.quit = true,
    }
}

fn optionsStep(g: *Game) void {
    if (g.st.hit(.pause) or g.st.hit(.b)) {
        g.mode = g.options_from;
        return;
    }
    g.option_row = rowNav(g.option_row, OPTION_ROWS.len, g.st.nav);
    const d = sideways(g.st.nav);
    if (d != 0) {
        const by = @as(f32, @floatFromInt(d)) * VOL_STEP;
        switch (OPTION_ROWS[g.option_row]) {
            .music => g.audio.setMusic(stepped(g.audio.music_vol, by)),
            .sfx => g.audio.setSfx(stepped(g.audio.sfx_vol, by)),
            else => {},
        }
    }
    if (!g.st.hit(.a)) return;
    switch (OPTION_ROWS[g.option_row]) {
        .music, .sfx => {},
        .mute => {
            g.muted = !g.muted;
            g.audio.mute(g.muted);
        },
        .fullscreen => rl.toggleBorderlessWindowed(),
        .back => g.mode = g.options_from,
    }
}

/// A volume moved `by`, landing on a whole `VOL_STEP`.
fn stepped(v: f32, by: f32) f32 {
    return @round((v + by) / VOL_STEP) * VOL_STEP;
}

pub const Brazier = struct { at: V, seed: u32 };

/// Every brazier whose lattice point lies within `lo` to `hi`, cells.
fn braziers(lo: V, hi: V, out: []Brazier) []Brazier {
    var n: usize = 0;
    var j: i32 = @intFromFloat(@floor(lo[1] / BRAZIER_GAP));
    while (@as(f32, @floatFromInt(j)) * BRAZIER_GAP <= hi[1]) : (j += 1) {
        var i: i32 = @intFromFloat(@floor(lo[0] / BRAZIER_GAP));
        while (@as(f32, @floatFromInt(i)) * BRAZIER_GAP <= hi[0]) : (i += 1) {
            if (n == out.len) return out[0..n];
            if (mathx.unitHash(i, j, BRAZIER_SEED) >= BRAZIER_ODDS) continue;
            if (i == 0 and j == 0) continue;
            const jx = mathx.unitHash(i, j, BRAZIER_SEED + 1);
            const jy = mathx.unitHash(i, j, BRAZIER_SEED + 2);
            out[n] = .{
                .at = .{ (@as(f32, @floatFromInt(i)) + 0.2 + jx * 0.6) * BRAZIER_GAP, (@as(f32, @floatFromInt(j)) + 0.2 + jy * 0.6) * BRAZIER_GAP },
                .seed = mathx.hash(i, j, BRAZIER_SEED + 3),
            };
            n += 1;
        }
    }
    return out[0..n];
}

fn flame(t: f32, seed: u32) struct { colour: Rgb, glow: f32 } {
    const k = light.flicker(t, seed);
    var shift: Rgb = undefined;
    for (0..3) |i| shift[i] = std.math.pow(f32, k, FLAME_SHIFT[i]);
    return .{ .colour = FLAME * shift, .glow = k };
}

const View = struct { lo: V, hi: V };

fn viewOf(g: *const Game) View {
    const o = g.origin();
    return .{
        .lo = .{ o[0] / CELL, o[1] / CELL },
        .hi = .{ (o[0] + @as(f32, @floatFromInt(g.screen.x))) / CELL, (o[1] + @as(f32, @floatFromInt(g.screen.y))) / CELL },
    };
}

fn inView(v: View, q: V, pad: f32) bool {
    return q[0] > v.lo[0] - pad and q[0] < v.hi[0] + pad and q[1] > v.lo[1] - pad and q[1] < v.hi[1] + pad;
}

/// Index 0 is the party's own lamp.
fn lightUp(g: *Game, v: View, fires: []const Brazier) void {
    const l = g.light;
    const r = g.run;
    l.clear();
    l.add(.{ .at = r.party, .z = PARTY_Z, .colour = PARTY_LAMP, .reach = PARTY_REACH });
    for (fires) |b| l.add(.{ .at = b.at, .z = BRAZIER_Z, .colour = flame(g.t, b.seed).colour, .reach = BRAZIER_REACH, .casts = true });
    if (r.boss()) |b| l.add(.{ .at = b.at, .z = BOSS_Z, .colour = BOSS_LAMP, .reach = BOSS_REACH });
    for (r.bolts.constSlice()) |b| {
        if (b.kind != .fire or !inView(v, b.at, 3)) continue;
        l.add(.{ .at = b.at, .z = BOLT_Z, .colour = BOLT_LAMP, .reach = BOLT_REACH });
    }
    var spits: usize = 0;
    for (r.spits.constSlice()) |s| {
        if (spits == SPIT_LAMPS or !inView(v, s.at, 2)) continue;
        spits += 1;
        l.add(.{ .at = s.at, .z = SPIT_Z, .colour = if (s.big) BOSS_SPIT_LAMP else SPIT_LAMP, .reach = if (s.big) BOSS_SPIT_REACH else SPIT_REACH });
    }
    l.bake(v.lo, v.hi);
}

/// How a body is drawn off its ground point: moved `shift` cells, scaled `sx` by `sy` about its feet, raised `lift` px.
const Pose = struct {
    shift: V = .{ 0, 0 },
    sx: f32 = 1,
    sy: f32 = 1,
    lift: f32 = 0,
    left: bool,

    /// Flattened by a blow, `k` of the way from whole.
    fn squash(p: *Pose, k: f32) void {
        p.sx *= 1 + SQUASH * k;
        p.sy *= 1 - SQUASH * k;
    }
};

fn figAt(g: *Game, tex: rl.Texture2D, at: V, pose: Pose, flash: f32, own: ?usize) Fig {
    const w = @as(f32, @floatFromInt(tex.width)) * pose.sx;
    const h = @as(f32, @floatFromInt(tex.height)) * pose.sy;
    const p = g.px(mathx.add(at, pose.shift));
    const dest = rl.Rectangle{ .x = @round(p[0] - w * 0.5), .y = @round(p[1] - h * STAND - pose.lift), .width = w, .height = h };
    const o = g.origin();
    const mid = V{ (dest.x + w * 0.5 + o[0]) / CELL, (dest.y + h * 0.5 + o[1]) / CELL };
    return .{ .tex = tex, .dest = dest, .mid = mid, .left = pose.left, .flash = flash, .shine = g.light.onBody(mid, own), .ground = at[1] };
}

/// Cells along its aim a knight lunges: a short draw back, then the thrust and its return.
fn lungeOf(t: f32) f32 {
    if (t < LUNGE_WIND) return -LUNGE_BACK * t / LUNGE_WIND;
    return LUNGE_REACH * @sin(std.math.pi * (t - LUNGE_WIND) / (1 - LUNGE_WIND));
}

fn heroPose(g: *const Game, m: run.Member, moving: bool) Pose {
    var p = Pose{ .left = g.left };
    if (moving) p.lift = @abs(@sin((g.t * BOB_HZ + @as(f32, @floatFromInt(m.slot)) * 0.17) * mathx.TAU)) * BOB_PX;
    const aim = mathx.fromHeading(m.aim);
    if (m.swing > 0) {
        const t = 1 - m.swing / run.SWING_S;
        p.shift = mathx.scale(aim, lungeOf(t));
        const s = @sin(std.math.pi * t);
        p.sx = 1 + LUNGE_STRETCH * s;
        p.sy = 1 - LUNGE_STRETCH * 0.5 * s;
        p.left = aim[0] < 0;
    } else if (m.hero.class == .archer or m.hero.class == .pyromancer) {
        const since = m.stats.cd - m.cd;
        if (m.cd > 0 and since < RECOIL_S) {
            p.shift = mathx.scale(aim, -RECOIL * (1 - since / RECOIL_S));
            p.left = aim[0] < 0;
        }
    }
    const k = m.flash / run.FLASH_S;
    p.shift = mathx.add(p.shift, mathx.scale(m.kick, HURT_RECOIL * k));
    p.squash(k);
    return p;
}

fn foePose(f: run.Foe) Pose {
    var p = Pose{ .left = f.vel[0] < 0 };
    if (f.frozen > 0) return p;
    const since = run.BITE_CD - f.bite;
    if (since >= 0 and since < run.JAB_S) {
        p.shift = mathx.scale(f.jab, JAB * @sin(std.math.pi * since / run.JAB_S));
        p.left = f.jab[0] < 0;
    }
    p.squash(f.flash / run.FLASH_S);
    return p;
}

fn skeletonPose(k: run.Skeleton) Pose {
    var p = Pose{ .left = k.jab[0] < 0 };
    if (k.swing > 0) {
        const t = 1 - k.swing / run.SWING_S;
        p.shift = mathx.scale(k.jab, JAB * @sin(std.math.pi * t));
    }
    p.squash(k.flash / run.FLASH_S);
    return p;
}

/// A bard's music: a glow at its reach, notes drifting in it, fading as it ends.
fn drawClouds(g: *Game, v: View) void {
    rl.beginBlendMode(.additive);
    defer rl.endBlendMode();
    for (g.run.clouds.constSlice()) |c| {
        if (!inView(v, c.at, c.radius + 1)) continue;
        const p = g.px(c.at);
        const a = mathx.smooth(c.life / CLOUD_OUT_S) * mathx.smooth((hero.CLOUD_S - c.life) / CLOUD_IN_S);
        const rad = c.radius * CELL;
        g.light.glow(p[0], p[1], rad * 1.1, .{ 0.8, 0.35, 0.7 }, 0.25 * a);
        for (0..NOTES) |i| {
            const h = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(NOTES)) * mathx.TAU + g.t * 0.7;
            const bob = @sin(g.t * 3 + @as(f32, @floatFromInt(i)) * 1.7) * 6;
            const q = mathx.add(p, mathx.scale(mathx.fromHeading(h), rad * 0.6));
            drawNote(q[0], q[1] + bob, light.colourOf(NOTE_RGB, 0.9 * a));
        }
    }
}

fn drawNote(x: f32, y: f32, c: rl.Color) void {
    rl.drawCircleV(.{ .x = x, .y = y }, 3.5, c);
    rl.drawLineEx(.{ .x = x + 3, .y = y }, .{ .x = x + 3, .y = y - 11 }, 1.5, c);
    rl.drawLineEx(.{ .x = x + 3, .y = y - 11 }, .{ .x = x + 8, .y = y - 8 }, 1.5, c);
}

/// 0 to 1 as a vine grows in, and back to 0 as it withers.
fn growth(vine: run.Vine) f32 {
    return mathx.smooth((hero.VINE_S - vine.life) / VINE_GROW_S) * mathx.smooth(vine.life / VINE_GROW_S);
}

/// A vine grows in and withers out, and lunges along its lash.
fn vinePose(vine: run.Vine) Pose {
    var p = Pose{ .left = vine.aim[0] < 0 };
    const grow = growth(vine);
    p.sx = 0.4 + 0.6 * grow;
    p.sy = 0.2 + 0.8 * grow;
    if (vine.lash > 0) {
        const t = 1 - vine.lash / run.LASH_S;
        p.shift = mathx.scale(vine.aim, VINE_LUNGE * @sin(std.math.pi * t));
        p.sx *= 1 + 0.15 * @sin(std.math.pi * t);
    }
    return p;
}

/// Where a warned shell will land: a red ring at its reach, filling toward the moment it does.
fn drawWarnings(g: *Game, v: View) void {
    for (g.run.shells.constSlice()) |s| {
        if (!s.warned or !inView(v, s.at, s.radius + 1)) continue;
        const p = vec(g.px(s.at));
        const k = std.math.clamp(s.t / s.fuse, 0, 1);
        const rad = s.radius * CELL;
        const pulse = 0.75 + 0.25 * @sin(g.t * 14);
        rl.drawCircleV(p, rad * k, look.fade(WARN, 0.22 + 0.2 * k));
        rl.drawRing(p, rad - 3, rad, 0, 360, 48, look.fade(WARN, 0.85 * pulse));
    }
}

/// Each shell in flight, high on its arc, and the small mark an unwarned one throws ahead of it.
fn drawShells(g: *Game, v: View) void {
    rl.beginBlendMode(.additive);
    defer rl.endBlendMode();
    for (g.run.shells.constSlice()) |s| {
        if (!inView(v, s.at, 6)) continue;
        const k = std.math.clamp(s.t / s.fuse, 0, 1);
        const ground = mathx.lerpV(s.from, s.at, k);
        const rise = run.LOB_ARC * mathx.len(mathx.sub(s.at, s.from)) * 4 * k * (1 - k);
        const p = g.px(.{ ground[0], ground[1] - rise });
        const hot: Rgb = if (s.warned) .{ 0.85, 0.35, 1.0 } else .{ 1.0, 0.55, 0.2 };
        g.light.glow(p[0], p[1], if (s.warned) 30 else 16, hot, 0.85);
        g.light.glow(p[0], p[1], if (s.warned) 10 else 6, .{ 1, 0.95, 0.85 }, 1);
        if (!s.warned) {
            const q = g.px(s.at);
            g.light.glow(q[0], q[1], s.radius * CELL, .{ 1.0, 0.35, 0.1 }, 0.12 * k);
        }
    }
}

/// The tile each vine holds, darkened under its roots, before the light map lights it.
fn drawRoots(g: *Game, v: View) void {
    for (g.run.vines.constSlice()) |vine| {
        if (!inView(v, vine.at, 1)) continue;
        const a = growth(vine);
        const p = g.px(.{ vine.at[0] - 0.5, vine.at[1] - 0.5 });
        rl.drawRectangleRounded(.{ .x = p[0] + 3, .y = p[1] + 3, .width = CELL - 6, .height = CELL - 6 }, 0.3, 6, look.fade(ROOTS, 0.75 * a));
    }
}

fn gatherFigs(g: *Game, v: View, fires: []const Brazier) []Fig {
    const r = g.run;
    var n: usize = 0;
    const moving = mathx.len2(r.vel) > 0.01;
    for (r.members.constSlice()) |m| {
        const tex = g.sprites.heroes.get(m.hero.class) orelse continue;
        g.figs[n] = figAt(g, tex, m.at, heroPose(g, m, moving), m.flash / run.FLASH_S, 0);
        n += 1;
    }
    for (r.foes.constSlice()) |f| {
        if (!inView(v, f.at, 2) or n == MAX_FIGS) continue;
        const tex = g.sprites.foes.get(f.kind) orelse continue;
        g.figs[n] = figAt(g, tex, f.at, foePose(f), @max(f.flash / run.FLASH_S, if (f.burn.t > 0) BURN_FLASH else 0), null);
        n += 1;
    }
    if (g.sprites.brazier) |tex| {
        for (fires) |b| {
            if (!inView(v, b.at, 2) or n == MAX_FIGS) continue;
            g.figs[n] = figAt(g, tex, b.at, .{ .left = false }, 0, null);
            n += 1;
        }
    }
    if (g.sprites.skeleton) |tex| {
        for (r.skeletons.constSlice()) |k| {
            if (!inView(v, k.at, 2) or n == MAX_FIGS) continue;
            g.figs[n] = figAt(g, tex, k.at, skeletonPose(k), k.flash / run.FLASH_S, null);
            n += 1;
        }
    }
    if (g.sprites.vine) |tex| {
        for (r.vines.constSlice()) |vine| {
            if (!inView(v, vine.at, 2) or n == MAX_FIGS) continue;
            g.figs[n] = figAt(g, tex, vine.at, vinePose(vine), 0, null);
            n += 1;
        }
    }
    if (g.sprites.banner) |tex| {
        for (r.banners.constSlice()) |b| {
            if (n == MAX_FIGS) break;
            g.figs[n] = figAt(g, tex, b, .{ .left = false, .lift = (@sin(g.t * 3) * 0.5 + 0.5) * 4 }, 0, null);
            n += 1;
        }
    }
    const figs = g.figs[0..n];
    std.sort.pdq(Fig, figs, {}, struct {
        fn lt(_: void, a: Fig, b: Fig) bool {
            return a.ground < b.ground;
        }
    }.lt);
    return figs;
}

fn drawFloor(g: *Game) void {
    const tex = g.sprites.floor orelse return rl.clearBackground(look.rgb(0x181e1a));
    const o = g.origin();
    const w: f32 = @floatFromInt(g.screen.x);
    const h: f32 = @floatFromInt(g.screen.y);
    const tw: f32 = @floatFromInt(tex.width);
    const th: f32 = @floatFromInt(tex.height);
    rl.drawTexturePro(tex, .{ .x = @mod(o[0], tw), .y = @mod(o[1], th), .width = w, .height = h }, .{ .x = 0, .y = 0, .width = w, .height = h }, .{ .x = 0, .y = 0 }, 0, rl.Color.white);
}

fn vec(p: V) rl.Vector2 {
    return .{ .x = p[0], .y = p[1] };
}

fn drawOrbs(g: *Game, v: View) void {
    rl.beginBlendMode(.additive);
    for (g.run.orbs.constSlice()) |o| {
        if (!inView(v, o.at, 1)) continue;
        const p = g.px(o.at);
        g.light.glow(p[0], p[1], if (o.xp > BIG_ORB) 18 else 12, .{ 0.3, 0.6, 1.0 }, 0.55);
    }
    rl.endBlendMode();
    for (g.run.orbs.constSlice()) |o| {
        if (!inView(v, o.at, 1)) continue;
        const p = g.px(o.at);
        rl.drawPoly(vec(p), 4, if (o.xp > BIG_ORB) 6 else 4, 0, look.rgb(0xb8e0ff));
    }
}

fn drawFires(g: *Game, v: View, fires: []const Brazier) void {
    const r = g.run;
    rl.beginBlendMode(.additive);
    defer rl.endBlendMode();
    for (fires) |b| {
        if (!inView(v, b.at, 3)) continue;
        const f = flame(g.t, b.seed);
        const p = g.px(.{ b.at[0], b.at[1] - BRAZIER_FIRE });
        g.light.glow(p[0], p[1], CELL * 2.6, .{ 1.0, 0.52, 0.22 }, 0.18 * f.glow);
        g.light.glow(p[0], p[1] - 4, CELL * 0.45, .{ 1.0, 0.7, 0.35 }, 0.9 * f.glow);
        g.light.glow(p[0], p[1] - 8, CELL * 0.22, .{ 1.0, 0.95, 0.7 }, 0.9 * f.glow);
    }
    for (r.bolts.constSlice()) |b| {
        if (b.kind != .fire or !inView(v, b.at, 1)) continue;
        const p = g.px(b.at);
        const k: f32 = if (b.crit) 1.8 else 1;
        g.light.glow(p[0], p[1], 26 * k, .{ 1.0, 0.5, 0.15 }, 0.8);
        g.light.glow(p[0], p[1], 9 * k, .{ 1.0, 0.95, 0.7 }, 1);
    }
    for (r.spits.constSlice()) |s| {
        if (!inView(v, s.at, 1)) continue;
        const p = g.px(s.at);
        if (s.big) {
            const pulse = 0.8 + 0.2 * @sin(g.t * 18);
            g.light.glow(p[0], p[1], 34 * pulse, .{ 1.0, 0.1, 0.15 }, 0.75);
            g.light.glow(p[0], p[1], 12, .{ 1.0, 0.75, 0.8 }, 1);
        } else {
            g.light.glow(p[0], p[1], 20, .{ 0.4, 0.9, 0.3 }, 0.6);
            g.light.glow(p[0], p[1], 7, .{ 0.9, 1.0, 0.7 }, 1);
        }
    }
    for (r.foes.constSlice()) |f| {
        if (f.frozen <= 0 or !inView(v, f.at, 1)) continue;
        const p = g.px(f.at);
        const a = @min(1, f.frozen / FROZEN_FADE);
        g.light.glow(p[0], p[1] - CELL * 0.25, CELL * 0.55, .{ 0.45, 0.65, 1.0 }, 0.55 * a);
    }
    for (r.foes.constSlice()) |f| {
        if (f.burn.t <= 0 or !inView(v, f.at, 1)) continue;
        const p = g.px(f.at);
        const k = light.flicker(g.t * 2, f.uid);
        g.light.glow(p[0], p[1] - CELL * 0.25, CELL * 0.5 * k, .{ 1.0, 0.45, 0.12 }, 0.45);
    }
    for (r.foes.constSlice()) |f| {
        if (f.charm <= 0 or !inView(v, f.at, 1)) continue;
        const p = g.px(f.at);
        g.light.glow(p[0], p[1] - CELL * 0.25, CELL * 0.55, .{ 1.0, 0.45, 0.85 }, 0.45);
        drawNote(p[0] + 10, p[1] - CELL * 0.8 + @sin(g.t * 5 + @as(f32, @floatFromInt(f.uid))) * 3, light.colourOf(NOTE_RGB, 1));
    }
    for (r.foes.constSlice()) |f| {
        if (f.poison.t <= 0 or !inView(v, f.at, 1)) continue;
        const p = g.px(f.at);
        g.light.glow(p[0], p[1] - CELL * 0.25, CELL * 0.45, .{ 0.6, 0.9, 0.15 }, 0.3);
    }
    if (r.boss()) |b| {
        const p = g.px(b.at);
        g.light.glow(p[0], p[1] - CELL * 1.1, CELL * 1.2, .{ 0.3, 1.0, 0.6 }, 0.25);
    }
}

fn drawShots(g: *Game, v: View) void {
    for (g.run.bolts.constSlice()) |b| {
        if (b.kind != .arrow or !inView(v, b.at, 1)) continue;
        const p = g.px(b.at);
        const tail = g.px(mathx.sub(b.at, mathx.scale(mathx.norm(b.vel), 0.45)));
        rl.drawLineEx(vec(tail), vec(p), if (b.crit) 4 else 2, if (b.crit) look.BRIGHT else look.ARROW);
    }
}

/// The blade's crescent: its edge sweeps across the aim, a fading trail behind it, swung the other way each time.
fn drawSlashes(g: *Game) void {
    rl.beginBlendMode(.additive);
    defer rl.endBlendMode();
    for (g.run.members.constSlice()) |m| {
        if (m.swing <= 0) continue;
        const t = 1 - m.swing / run.SWING_S;
        const sweep = mathx.smooth(t / SLASH_SWEEP);
        const fade = 1 - mathx.smooth((t - SLASH_SWEEP) / (1 - SLASH_SWEEP));
        const way: f32 = if (m.swings % 2 == 0) 1 else -1;
        const lead = m.aim + way * (sweep - 0.5) * m.stats.cleave * 2;
        const p = g.px(mathx.add(m.at, mathx.scale(mathx.fromHeading(m.aim), lungeOf(t))));
        const reach = (m.stats.range + 0.15) * CELL;
        const hot: Rgb = .{ 0.85, 0.9, 1.0 };
        for (0..SLASH_SEGS) |i| {
            const a = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SLASH_SEGS));
            const b = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(SLASH_SEGS));
            const h0 = lead - way * m.stats.cleave * 2 * sweep * (1 - a);
            const h1 = lead - way * m.stats.cleave * 2 * sweep * (1 - b);
            const lo = degOf(@min(h0, h1));
            const hi = degOf(@max(h0, h1));
            const inner = reach * (1 - 0.42 * b);
            rl.drawRing(vec(p), inner, reach, lo, hi, 4, light.colourOf(hot, b * b * 0.75 * fade * @sqrt(m.swing_k)));
        }
        const edge = mathx.add(p, mathx.scale(mathx.fromHeading(lead), reach * 0.86));
        g.light.glow(edge[0], edge[1], 22, hot, 0.8 * fade);
    }
}

/// Motes each frame: embers off bolts in flight, burning foes and the braziers in view; bubbles off poisoned foes;
/// green off heroes mending themselves.
fn kindle(g: *Game, dt: f32) void {
    const r = g.run;
    const v = viewOf(g);
    for (r.bolts.constSlice()) |b| {
        if (b.kind == .fire and inView(v, b.at, 1)) g.fx.smoulder(b.at, 0.4, EMBER_TRAIL * (if (b.crit) @as(f32, 2) else 1), 0.06, dt);
    }
    for (r.foes.constSlice()) |f| {
        if (f.burn.t > 0 and inView(v, f.at, 1)) g.fx.smoulder(f.at, 0.5, EMBER_BURNING, 0.25, dt);
        if (f.poison.t > 0 and inView(v, f.at, 1)) g.fx.fester(f.at, POISON_RATE, dt);
    }
    for (r.members.constSlice()) |m| {
        if (m.stats.regen > 0 and m.hp < m.stats.max_hp) g.fx.mend(m.at, MEND_RATE, dt);
    }
    var buf: [BRAZIER_MAX]Brazier = undefined;
    for (braziers(v.lo, v.hi, &buf)) |b| g.fx.smoulder(.{ b.at[0], b.at[1] - 0.05 }, BRAZIER_FIRE + 0.1, EMBER_BRAZIER, 0.12, dt);
}

/// raylib's degrees, for a vertex pointing along `heading`.
pub fn degOf(heading: f32) f32 {
    return heading * 180 / std.math.pi - 90;
}

fn drawBars(g: *Game) void {
    const r = g.run;
    for (r.skeletons.constSlice()) |k| {
        const p = g.px(k.at);
        const w: f32 = 32;
        rl.drawRectangleV(.{ .x = p[0] - w * 0.5 - 1, .y = p[1] + 13 }, .{ .x = w + 2, .y = 5 }, look.LIFE_BG);
        rl.drawRectangleV(.{ .x = p[0] - w * 0.5, .y = p[1] + 14 }, .{ .x = w * std.math.clamp(k.hp / k.max, 0, 1), .y = 3 }, look.class(.necromancer));
    }
    for (r.members.constSlice()) |m| {
        const p = g.px(m.at);
        const w: f32 = 44;
        const x = p[0] - w * 0.5;
        const y = p[1] + 14;
        rl.drawRectangleV(.{ .x = x - 1, .y = y - 1 }, .{ .x = w + 2, .y = 8 }, look.LIFE_BG);
        rl.drawRectangleV(.{ .x = x, .y = y }, .{ .x = w * std.math.clamp(m.hp / m.stats.max_hp, 0, 1), .y = 4 }, look.LIFE);
        rl.drawRectangleV(.{ .x = x, .y = y + 4 }, .{ .x = w * std.math.clamp(m.hero.xp / hero.xpFor(m.hero.level), 0, 1), .y = 2 }, look.XP);
        if (r.warded(m.slot) < 1) rl.drawPoly(.{ .x = x - 7, .y = y + 2 }, 4, 5, 0, look.SHIELD);
        if (r.cursed(m.slot)) rl.drawPoly(.{ .x = x + w + 7, .y = y + 2 }, 4, 5, 0, look.class(.necromancer));
        if (r.power(&m) > 1) rl.drawPoly(.{ .x = x - 7, .y = y - 8 }, 3, 5, -90, look.class(.bard));
    }
}

pub fn drawWorld(g: *Game) void {
    const v = viewOf(g);
    var fire_buf: [BRAZIER_MAX]Brazier = undefined;
    const fires = braziers(.{ v.lo[0] - BRAZIER_REACH, v.lo[1] - BRAZIER_REACH }, .{ v.hi[0] + BRAZIER_REACH, v.hi[1] + BRAZIER_REACH }, &fire_buf);
    lightUp(g, v, fires);
    const figs = gatherFigs(g, v, fires);
    const o = g.origin();

    drawFloor(g);
    drawRoots(g, v);
    drawWarnings(g, v);
    g.fx.drawGround(o, CELL);
    for (figs) |f| g.light.drawShadows(f.tex, f.dest, f.left, f.mid, f.shine);
    g.light.drawMap(o, CELL);
    drawOrbs(g, v);
    for (figs) |f| g.light.drawBody(f.tex, f.dest, f.left, f.mid, f.shine, f.flash);
    drawShots(g, v);
    drawShells(g, v);
    drawClouds(g, v);
    drawFires(g, v, fires);
    drawSlashes(g);
    g.fx.drawLight(g.light, o, CELL);
    drawBars(g);
    g.numbers.draw(g.face, o, CELL);
}

/// The hero a level-up is about: its own, or the one it is moving.
fn leveling(g: *Game) ?*run.Member {
    return switch (g.mode) {
        .level => g.run.levelHead(),
        .place => if (g.from == .level) switch (g.placing) {
            .move => |id| g.run.byId(id),
            .recruit => null,
        } else null,
        else => null,
    };
}

fn stepZoom(g: *Game, dt: f32) void {
    const m = leveling(g);
    if (m) |h| g.focus = mathx.sub(h.at, .{ 0, ZOOM_LIFT });
    const k = mathx.easing(dt, ZOOM_EASE);
    g.zoom = mathx.ease(g.zoom, if (m != null) 1 else 0, k, k);
}

/// The world as the zoom draws it: `focus` slides from where it stands to the middle of the top half.
fn zoomCamera(g: *const Game) rl.Camera2D {
    const s = mathx.smooth(g.zoom);
    const at = g.px(g.focus);
    const anchor = V{ @as(f32, @floatFromInt(g.screen.x)) * 0.5, @as(f32, @floatFromInt(g.screen.y)) * 0.25 };
    const off = mathx.lerpV(at, anchor, s);
    return .{ .offset = vec(off), .target = vec(at), .rotation = 0, .zoom = mathx.lerpF(1, ZOOM, s) };
}

pub fn drawFrame(g: *Game) void {
    rl.clearBackground(look.BG);
    if (g.zoom > 0) {
        rl.beginMode2D(zoomCamera(g));
        drawWorld(g);
        rl.endMode2D();
    } else drawWorld(g);
    hud.draw(g);
}

pub fn withGame(flags: rl.ConfigFlags, title: [:0]const u8, seed: u64, comptime body: fn (*Game) void) void {
    const alloc = std.heap.c_allocator;
    rl.setConfigFlags(flags);
    rl.initWindow(WINDOW_W, WINDOW_H, title);
    defer rl.closeWindow();
    input.claimKeys();
    const g = boot(alloc, seed) catch |e| {
        std.debug.print("boot FAILED ({s})\n", .{@errorName(e)});
        return;
    };
    defer shut(alloc, g);
    g.sprites = look.Sprites.load();
    defer g.sprites.unload();
    g.face = font.Face.load();
    defer g.face.unload();
    const figures = g.sprites.figures();
    g.light.load(&figures);
    defer g.light.unload();
    body(g);
}

pub fn play() void {
    withGame(.{ .vsync_hint = true, .msaa_4x_hint = true }, "Auto Survivors", freshSeed(), loop);
}

fn loop(g: *Game) void {
    rl.setTargetFPS(144);
    g.audio = audio.Audio.load();
    defer g.audio.unload();
    g.mode = .title;
    while (!rl.windowShouldClose() and !g.quit) {
        g.audio.update(rl.getFrameTime());
        update(g, rl.getFrameTime());
        rl.beginDrawing();
        drawFrame(g);
        rl.endDrawing();
    }
}

/// DEV ONLY. A render texture, not `takeScreenshot`: the batch is only guaranteed flushed at `endTextureMode`.
pub fn shot() void {
    withGame(.{ .window_hidden = true }, "auto-survivors --shot", SHOT_SEED, shoot);
}

fn shoot(g: *Game) void {
    const target = rl.loadRenderTexture(g.screen.x, g.screen.y) catch {
        std.debug.print("render texture FAILED\n", .{});
        return;
    };
    defer rl.unloadRenderTexture(target);
    std.fs.cwd().makePath(SHOTS_DIR) catch {};

    poseRun(g);
    capture(g, target, SHOTS_DIR ++ "/run.png");

    const m = g.run.memberAt(formation.CENTRE).?;
    _ = g.run.levels.push(m.id);
    openMenus(g);
    g.zoom = 1;
    stepZoom(g, 0);
    capture(g, target, SHOTS_DIR ++ "/level.png");

    g.placing = .{ .move = m.id };
    g.cursor = 2;
    g.from = .level;
    g.mode = .place;
    stepZoom(g, 0);
    capture(g, target, SHOTS_DIR ++ "/place.png");
    g.zoom = 0;

    g.run.levels.n = 0;
    g.run.recruits = 1;
    openMenus(g);
    capture(g, target, SHOTS_DIR ++ "/recruit.png");

    g.run.recruits = 0;
    g.mode = .pause;
    capture(g, target, SHOTS_DIR ++ "/pause.png");

    g.mode = .options;
    capture(g, target, SHOTS_DIR ++ "/options.png");

    g.mode = .title;
    capture(g, target, SHOTS_DIR ++ "/title.png");
}

/// A full formation two and a half minutes in, a horde round it.
fn poseRun(g: *Game) void {
    const r = g.run;
    r.t = POSE_T;
    for (0..POSE_FOES) |i| {
        const h = @as(f32, @floatFromInt(i)) * 2.399;
        const kind: foe.Kind = switch (i % 5) {
            0 => .bat,
            1 => .spitter,
            2 => .husk,
            else => .ghoul,
        };
        _ = r.spawnAt(kind, mathx.add(r.party, mathx.scale(mathx.fromHeading(h), 3.5 + @as(f32, @floatFromInt(i % 7)) * 0.7)));
    }
    while (r.members.n < formation.SLOTS) {
        for (0..formation.SLOTS) |i| {
            if (r.memberAt(@intCast(i)) == null) _ = r.recruit(hero.CLASSES[i % hero.CLASSES.len], @intCast(i));
        }
    }
    const c = r.memberAt(formation.CENTRE).?;
    if (c.hero.class != .pyromancer) {
        for (r.members.slice()) |*m| {
            if (m.hero.class == .pyromancer) {
                _ = r.moveTo(m.id, formation.CENTRE);
                break;
            }
        }
    }
    for (r.members.slice()) |*m| m.hp = m.stats.max_hp * 0.8;
    _ = r.drainEvents();
    g.fx.clear();
    for (0..90) |_| {
        r.spawn_acc += 0.05;
        r.step(.{ 0.6, -0.8 });
        for (r.drainEvents()) |e| {
            g.fx.take(e);
            g.numbers.take(e);
        }
        g.fx.step(run.STEP);
    }
    r.levels.n = 0;
    r.recruits = 0;
    g.mode = .play;
    g.cam = r.party;
    g.left = false;
}

fn capture(g: *Game, target: rl.RenderTexture2D, path: [:0]const u8) void {
    rl.beginTextureMode(target);
    drawFrame(g);
    rl.endTextureMode();
    var img = rl.loadImageFromTexture(target.texture) catch {
        std.debug.print("{s} FAILED\n", .{path});
        return;
    };
    defer rl.unloadImage(img);
    rl.imageFlipVertical(&img);
    rl.imageFormat(&img, .uncompressed_r8g8b8);
    std.debug.print("{s} {s}\n", .{ path, if (rl.exportImage(img, path)) "written" else "FAILED" });
}

test "braziers are where their lattice puts them, the same from any view" {
    var a: [BRAZIER_MAX]Brazier = undefined;
    var b: [BRAZIER_MAX]Brazier = undefined;
    const wide = braziers(.{ -40, -40 }, .{ 40, 40 }, &a);
    const narrow = braziers(.{ 0, 0 }, .{ 20, 20 }, &b);
    std.debug.print("braziers in an 80-cell square: {d}, in a 20-cell one: {d}\n", .{ wide.len, narrow.len });
    try std.testing.expect(wide.len > narrow.len and narrow.len > 0);
    for (narrow) |n| {
        var found = false;
        for (wide) |w| found = found or (w.at[0] == n.at[0] and w.at[1] == n.at[1]);
        try std.testing.expect(found);
    }
}
