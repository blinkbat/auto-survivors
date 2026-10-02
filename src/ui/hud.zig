const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const formation = @import("../play/formation.zig");
const hero = @import("../play/hero.zig");
const run = @import("../play/run.zig");
const director = @import("../play/director.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const game = @import("../game.zig");

// THE HUD AND EVERY OVERLAY. Reads the game; changes nothing.

const Game = game.Game;

pub const REFUSED_S: f32 = 0.8;
const PAD: i32 = 20;
const LINE: i32 = 26;
const MAP_PX: i32 = 180;
/// Cells from the party to the minimap's edge.
const MAP_REACH: f32 = run.DESPAWN_R;
const MAP_DOT: f32 = 4;
const MAP_INSET: f32 = MAP_DOT + 2;
/// Pixels in from the screen's edge an arrow to something off it sits.
const BEACON_PAD: f32 = 28;
const BEACON_PX: f32 = 14;
const BOSS_W: i32 = 520;
const BOSS_H: i32 = 14;
const CARD_W: i32 = 300;
const CARD_H: i32 = 240;
const ICON_PX: i32 = 64;
const CARD_GAP: i32 = 24;
const CARD_PAD: i32 = 16;
const PLACE_PX: i32 = 128;
const PLACE_GAP: i32 = 8;
const BUF: usize = 160;
const CLOCK: usize = 16;
const VEIL_FADE: i32 = 90;
const ZOOMED_PLACE_PX: i32 = 84;
const TILE = look.fade(look.RAISED, 0.96);
const MENU_STEP: i32 = LINE + 14;
const PIPS: usize = @intFromFloat(@round(1 / game.VOL_STEP));
const NAV = input.NAV_CAPTION;
const A = input.Button.a.caption();
const B = input.Button.b.caption();
/// Past this much zoom the clock and kill count would sit over the hero, so they go.
const ZOOM_HUD: f32 = 0.05;

fn mid(g: *Game, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    g.face.mid(s, @divTrunc(g.screen.x, 2), y, size, col);
}

fn fmt(buf: []u8, comptime f: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, f, args) catch "";
}

fn ruleText(buf: []u8, row: hero.ClassRow) [:0]const u8 {
    return fmt(buf, "{s}: {s}", .{ row.rule, row.rule_desc });
}

fn veil(g: *Game) void {
    rl.drawRectangle(0, 0, g.screen.x, g.screen.y, look.VEIL);
}

/// The lower half, under the hero the view has zoomed in on, faded in over `VEIL_FADE` px.
fn veilLow(g: *Game) i32 {
    const top = @divTrunc(g.screen.y, 2);
    rl.drawRectangleGradientV(0, top - VEIL_FADE, g.screen.x, VEIL_FADE, look.fade(look.BG, 0), look.VEIL);
    rl.drawRectangle(0, top, g.screen.x, g.screen.y - top, look.VEIL);
    return top;
}

fn box(x: i32, y: i32, w: i32, h: i32, fill: rl.Color, edge: rl.Color, thick: f32) void {
    rl.drawRectangle(x, y, w, h, fill);
    rl.drawRectangleLinesEx(.{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) }, thick, edge);
}

/// Row `i` of a menu centred on `cy`.
fn menuRow(g: *Game, label: [:0]const u8, cy: i32, i: usize, on: bool) void {
    mid(g, label, cy - 20 + @as(i32, @intCast(i)) * MENU_STEP, font.HEAD, if (on) look.BRIGHT else look.DIM);
}

fn clock(buf: []u8, t: f32) [:0]const u8 {
    const s: u32 = @intFromFloat(@max(0, t));
    return fmt(buf, "{d:0>2}:{d:0>2}", .{ s / 60, s % 60 });
}

pub fn draw(g: *Game) void {
    if (g.mode == .title) return drawTitle(g);
    if (g.mode == .options and g.options_from == .title) return drawOptions(g);
    if (g.zoom < ZOOM_HUD) {
        drawTop(g);
        drawMinimap(g);
        drawBeacons(g);
    }
    switch (g.mode) {
        .title, .play => {},
        .level => drawLevel(g),
        .place => drawPlace(g),
        .recruit => drawRecruit(g),
        .pause => drawPause(g),
        .options => drawOptions(g),
        .over => drawOver(g),
    }
}

fn drawTop(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    var t: [CLOCK]u8 = undefined;
    const r = g.run;
    mid(g, clock(&t, r.t), PAD - 6, font.HEAD + 6, look.TEXT);
    g.face.text(fmt(&buf, "{d} slain", .{r.kills}), PAD, PAD, font.BODY, look.DIM);
    if (r.boss()) |b| {
        const x = @divTrunc(g.screen.x - BOSS_W, 2);
        const y = PAD + font.HEAD + 14;
        mid(g, if (b.final) "THE LICH" else "A LESSER LICH", y, font.BODY, look.BOSS);
        box(x, y + LINE, BOSS_W, BOSS_H, look.LIFE_BG, look.EDGE, 1);
        rl.drawRectangle(x + 1, y + LINE + 1, @intFromFloat(@as(f32, @floatFromInt(BOSS_W - 2)) * std.math.clamp(b.hp / b.max, 0, 1)), BOSS_H - 2, look.BOSS);
    } else if (r.t < director.BOSS_AT) {
        mid(g, fmt(&buf, "The lich comes at {s}", .{clock(&t, director.BOSS_AT)}), PAD + font.HEAD + 10, font.SMALL, look.DIM);
    }
}

/// Top right: the party at the middle, every lich and flag about it, one past its reach held on its rim.
fn drawMinimap(g: *Game) void {
    const r = g.run;
    const x = g.screen.x - PAD - MAP_PX;
    box(x, PAD, MAP_PX, MAP_PX, look.fade(look.PANEL, 0.85), look.EDGE, 1);
    const c = mathx.V{ @floatFromInt(x + @divTrunc(MAP_PX, 2)), @floatFromInt(PAD + @divTrunc(MAP_PX, 2)) };
    for (r.banners.constSlice()) |b| dot(mapAt(c, mathx.sub(b, r.party)), MAP_DOT, look.GOLD);
    for (r.foes.constSlice()) |f| {
        if (f.kind == .boss) dot(mapAt(c, mathx.sub(f.at, r.party)), MAP_DOT + 1, look.FOE);
    }
    dot(c, MAP_DOT, rl.Color.white);
}

/// Where cells `off` from the party sit on the minimap centred on `c`.
fn mapAt(c: mathx.V, off: mathx.V) mathx.V {
    var rel = mathx.scale(off, 1 / MAP_REACH);
    const k = @max(@abs(rel[0]), @abs(rel[1]));
    if (k > 1) rel = mathx.scale(rel, 1 / k);
    return mathx.add(c, mathx.scale(rel, @as(f32, @floatFromInt(@divTrunc(MAP_PX, 2))) - MAP_INSET));
}

fn dot(p: mathx.V, r: f32, col: rl.Color) void {
    rl.drawCircleV(.{ .x = p[0], .y = p[1] }, r, col);
}

/// Every lich and flag off the screen, as an arrow on its edge pointing at it.
fn drawBeacons(g: *Game) void {
    const r = g.run;
    for (r.foes.constSlice()) |f| {
        if (f.kind == .boss) beacon(g, f.at, look.FOE);
    }
    for (r.banners.constSlice()) |b| beacon(g, b, look.GOLD);
}

fn beacon(g: *Game, at: mathx.V, col: rl.Color) void {
    const size = mathx.V{ @floatFromInt(g.screen.x), @floatFromInt(g.screen.y) };
    const p = g.px(at);
    const q = edgeOf(p, size) orelse return;
    const deg = game.degOf(mathx.headingOf(mathx.sub(p, mathx.scale(size, 0.5))));
    rl.drawPoly(.{ .x = q[0], .y = q[1] }, 3, BEACON_PX + 5, deg, look.fade(look.BG, 0.75));
    rl.drawPoly(.{ .x = q[0], .y = q[1] }, 3, BEACON_PX, deg, col);
}

/// Null on the screen; otherwise where the line from the middle to `p` crosses the screen's edge, `BEACON_PAD` in.
fn edgeOf(p: mathx.V, size: mathx.V) ?mathx.V {
    if (p[0] >= 0 and p[0] <= size[0] and p[1] >= 0 and p[1] <= size[1]) return null;
    const c = mathx.scale(size, 0.5);
    const d = mathx.sub(p, c);
    const k = @min((c[0] - BEACON_PAD) / @max(@abs(d[0]), 1e-3), (c[1] - BEACON_PAD) / @max(@abs(d[1]), 1e-3));
    return mathx.add(c, mathx.scale(d, k));
}

fn cardsX(g: *Game, n: usize) i32 {
    const w = @as(i32, @intCast(n)) * CARD_W + (@as(i32, @intCast(n)) - 1) * CARD_GAP;
    return @divTrunc(g.screen.x - w, 2);
}

fn card(g: *Game, x: i32, y: i32, on: bool, dim: bool, icon: ?rl.Texture2D, title: [:0]const u8, desc: []const u8, foot: [:0]const u8, tint: rl.Color) void {
    box(x, y, CARD_W, CARD_H, TILE, if (on) look.BRIGHT else look.EDGE, if (on) 3 else 1);
    const a: f32 = if (dim) 0.4 else 1;
    if (icon) |t| look.stretch(t, .{ .x = @floatFromInt(x + @divTrunc(CARD_W - ICON_PX, 2)), .y = @floatFromInt(y + CARD_PAD - 4), .width = @floatFromInt(ICON_PX), .height = @floatFromInt(ICON_PX) }, look.fade(rl.Color.white, a));
    const ty = y + CARD_PAD + ICON_PX + 2;
    g.face.mid(title, x + @divTrunc(CARD_W, 2), ty, font.HEAD, look.fade(tint, a));
    _ = g.face.wrapped(desc, x + CARD_PAD, ty + font.HEAD + 12, CARD_W - CARD_PAD * 2, font.BODY, LINE - 2, look.fade(look.TEXT, a), true);
    g.face.mid(foot, x + @divTrunc(CARD_W, 2), y + CARD_H - CARD_PAD - font.SMALL, font.SMALL, look.fade(look.DIM, a));
}

fn drawLevel(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    var foot: [BUF]u8 = undefined;
    const m = g.run.levelHead() orelse return;
    const row = hero.class(m.hero.class);
    const top = veilLow(g);
    const cy = top + 110 + CARD_H / 2;
    const promo = g.offer.n > 0 and g.offer.cards[0] == .branch;
    mid(g, fmt(&buf, "{s} - Level {d}{s}", .{ m.hero.name(), m.hero.level, if (promo) ": Promotion" else "" }), top + 4, font.TITLE, look.class(m.hero.class));
    mid(g, ruleText(&buf, row), top + 70, font.BODY, look.DIM);
    const x0 = cardsX(g, g.offer.n);
    for (g.offer.slice(), 0..) |c, i| {
        const f: [:0]const u8 = switch (c) {
            .up => |u| fmt(&foot, "{d} / {d}", .{ m.hero.ups.get(u), hero.up(u).max }),
            .branch => "Promotion",
            .move => fmt(&foot, "Now in the {s}", .{slotName(m.slot)}),
            .rest => "",
        };
        card(g, x0 + @as(i32, @intCast(i)) * (CARD_W + CARD_GAP), cy - CARD_H / 2, i == g.pick, false, g.sprites.icon(c), c.name(), c.desc(), f, if (c == .move) look.TEXT else look.BRIGHT);
    }
    mid(g, NAV ++ " choose   " ++ A ++ " take", cy + CARD_H / 2 + 22, font.BODY, look.DIM);
}

const DIR_NAMES = std.EnumArray(mathx.Dir, [:0]const u8).init(.{ .n = "north", .ne = "north-east", .e = "east", .se = "south-east", .s = "south", .sw = "south-west", .w = "west", .nw = "north-west" });

fn slotName(s: formation.Slot) [:0]const u8 {
    for (mathx.ALL_DIRS) |d| {
        if (formation.frontCentre(d) == s) return DIR_NAMES.get(d);
    }
    return "centre";
}

fn placeWord(p: run.Run.Place) [:0]const u8 {
    return switch (p) {
        .move => "move here",
        .swap => "swap",
        .merge => "merge",
        .recruit => "place",
        .refused => "-",
    };
}

fn drawPlace(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    const r = g.run;
    const low = g.from == .level;
    const cell = if (low) ZOOMED_PLACE_PX else PLACE_PX;
    const side = formation.SIDE * cell + (formation.SIDE - 1) * PLACE_GAP;
    const x0 = @divTrunc(g.screen.x - side, 2);
    const y0 = if (low) veilLow(g) + 100 else blk: {
        veil(g);
        break :blk @divTrunc(g.screen.y - side, 2) + 20;
    };
    const who: hero.Hero, const verb: [:0]const u8 = switch (g.placing) {
        .move => |id| .{ if (r.byId(id)) |m| m.hero else hero.Hero.of(.knight), "Move the" },
        .recruit => |c| .{ hero.Hero.of(c), "Place the" },
    };
    mid(g, fmt(&buf, "{s} {s}", .{ verb, who.name() }), y0 - (if (low) @as(i32, 96) else 110), font.TITLE, look.class(who.class));
    mid(g, "The front row follows the way the party moves; an archer fires out of the side its slot is on", y0 - (if (low) @as(i32, 32) else 40), font.SMALL, look.DIM);
    for (0..formation.SLOTS) |i| {
        const s: formation.Slot = @intCast(i);
        const o = formation.offset(s);
        const x = x0 + (o.x + 1) * (cell + PLACE_GAP);
        const y = y0 + (o.y + 1) * (cell + PLACE_GAP);
        const here = s == g.cursor;
        const edge = if (here) (if (g.refused > 0) look.FOE else look.BRIGHT) else if (formation.inFront(s, r.facing)) look.GOLD else look.EDGE;
        box(x, y, cell, cell, TILE, edge, if (here) 3 else 1);
        const cx = x + @divTrunc(cell, 2);
        if (r.memberAt(s)) |m| {
            g.face.mid(m.hero.name(), cx, y + @divTrunc(cell, 7), font.BODY, look.class(m.hero.class));
            g.face.mid(fmt(&buf, "Level {d}{s}", .{ m.hero.level, if (m.hero.rank > 1) " +" else "" }), cx, y + @divTrunc(cell, 3), font.SMALL, look.TEXT);
        } else g.face.mid("empty", cx, y + @divTrunc(cell, 4), font.SMALL, look.DIM);
        const p = game.placeOf(g, s);
        g.face.mid(placeWord(p), cx, y + cell - 30, font.BODY, if (p == .refused) look.DIM else look.BRIGHT);
    }
    mid(g, NAV ++ " slot   " ++ A ++ " place   " ++ B ++ " back", y0 + side + 24, font.BODY, look.DIM);
}

fn drawRecruit(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    mid(g, "A RECRUIT JOINS", cy - CARD_H / 2 - 110, font.TITLE, look.BRIGHT);
    mid(g, "Place it in an empty slot, or on a hero of its class to merge them", cy - CARD_H / 2 - 44, font.BODY, look.DIM);
    const x0 = cardsX(g, game.CHOICES);
    for (g.choices, 0..) |c, i| {
        const row = hero.class(c);
        const ok = g.run.canRecruit(c);
        const desc = ruleText(&buf, row);
        card(g, x0 + @as(i32, @intCast(i)) * (CARD_W + CARD_GAP), cy - CARD_H / 2, i == g.pick, !ok, g.sprites.heroes.get(c), row.name, desc, if (ok) "" else "No slot can take it", look.class(c));
    }
    mid(g, NAV ++ " choose   " ++ A ++ " take   " ++ B ++ " pass", cy + CARD_H / 2 + 30, font.BODY, look.DIM);
}

fn drawTitle(g: *Game) void {
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    mid(g, "AUTO SURVIVORS", cy - 210, font.TITLE + 24, look.BRIGHT);
    mid(g, "Steer the formation. Where each hero stands decides the run.", cy - 110, font.BODY, look.DIM);
    for (game.TITLE_ROWS, 0..) |row, i| {
        const label: [:0]const u8 = switch (row) {
            .start => "Start",
            .options => "Options",
            .quit => "Quit",
        };
        menuRow(g, label, cy, i, i == g.title_row);
    }
    mid(g, NAV ++ " choose   " ++ A ++ " select   " ++ input.FULLSCREEN_CAPTION ++ " fullscreen", cy + @as(i32, game.TITLE_ROWS.len) * MENU_STEP + 20, font.SMALL, look.DIM);
}

fn drawPause(g: *Game) void {
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    mid(g, "PAUSED", cy - 120, font.TITLE, look.TEXT);
    for (game.PAUSE_ROWS, 0..) |row, i| {
        const label: [:0]const u8 = switch (row) {
            .resume_play => "Resume",
            .restart => "Restart",
            .options => "Options",
            .quit => "Quit",
        };
        menuRow(g, label, cy, i, i == g.pause_row);
    }
}

fn drawOptions(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    var pips: [PIPS]u8 = undefined;
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    mid(g, "OPTIONS", cy - 120, font.TITLE, look.TEXT);
    for (game.OPTION_ROWS, 0..) |row, i| {
        const label: [:0]const u8 = switch (row) {
            .mute => fmt(&buf, "Sound: {s}", .{if (g.muted) "off" else "on"}),
            .music => fmt(&buf, "Music  < {s} >", .{bar(&pips, g.audio.music_vol)}),
            .sfx => fmt(&buf, "Effects  < {s} >", .{bar(&pips, g.audio.sfx_vol)}),
            .fullscreen => fmt(&buf, "Fullscreen: {s}", .{if (game.fullscreen()) "on" else "off"}),
            .back => "Back",
        };
        menuRow(g, label, cy, i, i == g.option_row);
    }
    mid(g, NAV ++ " left and right set a volume   " ++ input.FULLSCREEN_CAPTION ++ " toggles fullscreen anywhere", cy + @as(i32, game.OPTION_ROWS.len) * MENU_STEP + 10, font.SMALL, look.DIM);
}

/// A volume as a pip a step, ASCII.
fn bar(buf: *[PIPS]u8, v: f32) []const u8 {
    const on: usize = @intFromFloat(@round(std.math.clamp(v, 0, 1) * @as(f32, @floatFromInt(PIPS))));
    for (buf, 0..) |*c, i| c.* = if (i < on) '#' else '-';
    return buf;
}

fn drawOver(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    var t: [CLOCK]u8 = undefined;
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    const won = g.run.outcome == .won;
    mid(g, if (won) "VICTORY" else "THE PARTY HAS FALLEN", cy - 90, font.TITLE, if (won) look.BRIGHT else look.LIFE);
    mid(g, fmt(&buf, "{s}   {d} slain", .{ clock(&t, g.run.t), g.run.kills }), cy - 10, font.HEAD, look.TEXT);
    mid(g, A ++ " play again", cy + 40, font.BODY, look.DIM);
}

test "an arrow to something off screen sits on the edge toward it, and the minimap holds a far flag on its rim" {
    const size = mathx.V{ 1600, 900 };
    try std.testing.expectEqual(@as(?mathx.V, null), edgeOf(.{ 800, 450 }, size));
    const right = edgeOf(.{ 3000, 450 }, size).?;
    const corner = edgeOf(.{ 2400, 1350 }, size).?;
    const c = mathx.V{ 0, 0 };
    const far = mapAt(c, .{ 0, -10 * MAP_REACH });
    std.debug.print("beacon for a point far right: {d:.0},{d:.0}; far down-right: {d:.0},{d:.0}; a flag 10 reaches north on the map: {d:.0},{d:.0}\n", .{ right[0], right[1], corner[0], corner[1], far[0], far[1] });
    try std.testing.expectApproxEqAbs(size[0] - BEACON_PAD, right[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 450), right[1], 1e-3);
    try std.testing.expectApproxEqAbs(size[1] - BEACON_PAD, corner[1], 1e-3);
    try std.testing.expectApproxEqAbs(-(@as(f32, @floatFromInt(@divTrunc(MAP_PX, 2))) - MAP_INSET), far[1], 1e-3);
}

test "the clock reads minutes and seconds" {
    var buf: [CLOCK]u8 = undefined;
    try std.testing.expectEqualStrings("20:00", clock(&buf, director.BOSS_AT));
    try std.testing.expectEqualStrings("01:05", clock(&buf, 65.9));
}
