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
const SLOT_PX: i32 = 58;
const SLOT_GAP: i32 = 4;
const SLOT_STEP: i32 = SLOT_PX + SLOT_GAP;
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
const VEIL_FADE: i32 = 90;
const ZOOMED_PLACE_PX: i32 = 84;
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
    if (g.zoom < ZOOM_HUD) drawTop(g);
    drawPanel(g);
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
    const r = g.run;
    mid(g, clock(&buf, r.t), PAD - 6, font.HEAD + 6, look.TEXT);
    g.face.text(fmt(&buf, "{d} slain", .{r.kills}), PAD, PAD, font.BODY, look.DIM);
    if (r.boss()) |b| {
        const x = @divTrunc(g.screen.x - BOSS_W, 2);
        const y = PAD + font.HEAD + 14;
        mid(g, if (b.final) "THE LICH" else "A LESSER LICH", y, font.BODY, look.BOSS);
        box(x, y + LINE, BOSS_W, BOSS_H, look.LIFE_BG, look.EDGE, 1);
        rl.drawRectangle(x + 1, y + LINE + 1, @intFromFloat(@as(f32, @floatFromInt(BOSS_W - 2)) * std.math.clamp(b.hp / b.max, 0, 1)), BOSS_H - 2, look.BOSS);
    } else if (r.t < director.BOSS_AT) {
        mid(g, fmt(&buf, "The lich comes at {s}", .{clock(buf[80..], director.BOSS_AT)}), PAD + font.HEAD + 10, font.SMALL, look.DIM);
    }
}

fn slotXY(x0: i32, y0: i32, s: formation.Slot) mathx.P {
    const o = formation.offset(s);
    return .{ .x = x0 + (o.x + 1) * SLOT_STEP, .y = y0 + (o.y + 1) * SLOT_STEP };
}

/// The 3x3 as it stands: who is where and which slots are the front row.
fn drawPanel(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    const r = g.run;
    const x0 = PAD;
    const y0 = g.screen.y - PAD - LINE - 3 * SLOT_STEP;
    for (0..formation.SLOTS) |i| {
        const s: formation.Slot = @intCast(i);
        const p = slotXY(x0, y0, s);
        const edge = if (formation.inFront(s, r.facing)) look.GOLD else look.EDGE;
        const m = r.memberAt(s) orelse {
            box(p.x, p.y, SLOT_PX, SLOT_PX, look.fade(look.PANEL, 0.85), look.fade(edge, 0.7), 1);
            continue;
        };
        box(p.x, p.y, SLOT_PX, SLOT_PX, look.fade(look.RAISED, 0.92), edge, 1);
        const ch = [_:0]u8{m.hero.name()[0]};
        g.face.mid(&ch, p.x + @divTrunc(SLOT_PX, 2), p.y + 8, font.HEAD, look.class(m.hero.class));
        g.face.text(fmt(&buf, "{d}", .{m.hero.level}), p.x + 4, p.y + SLOT_PX - 22, font.SMALL, look.TEXT);
        for (1..m.hero.rank) |k| rl.drawCircle(p.x + SLOT_PX - 6 - @as(i32, @intCast(k - 1)) * 8, p.y + 7, 3, look.BRIGHT);
        rl.drawRectangle(p.x + 3, p.y + SLOT_PX - 5, @intFromFloat(@as(f32, @floatFromInt(SLOT_PX - 6)) * std.math.clamp(m.hp / m.stats.max_hp, 0, 1)), 3, look.LIFE);
    }
    g.face.text(fmt(&buf, "{s} move   {s} pause", .{ input.MOVE_CAPTION, input.Button.pause.caption() }), PAD, g.screen.y - PAD - font.SMALL, font.SMALL, look.DIM);
}

fn cardsX(g: *Game, n: usize) i32 {
    const w = @as(i32, @intCast(n)) * CARD_W + (@as(i32, @intCast(n)) - 1) * CARD_GAP;
    return @divTrunc(g.screen.x - w, 2);
}

fn card(g: *Game, x: i32, y: i32, on: bool, dim: bool, icon: ?rl.Texture2D, title: [:0]const u8, desc: []const u8, foot: [:0]const u8, tint: rl.Color) void {
    box(x, y, CARD_W, CARD_H, look.fade(look.RAISED, 0.96), if (on) look.BRIGHT else look.EDGE, if (on) 3 else 1);
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
    mid(g, fmt(&buf, "{s}: {s}", .{ row.rule, row.rule_desc }), top + 70, font.BODY, look.DIM);
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
    const side = 3 * cell + 2 * PLACE_GAP;
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
        box(x, y, cell, cell, look.fade(look.RAISED, 0.96), edge, if (here) 3 else 1);
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
        const desc = fmt(&buf, "{s}: {s}", .{ row.rule, row.rule_desc });
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
    mid(g, NAV ++ " choose   " ++ A ++ " select   Alt+Enter fullscreen", cy + @as(i32, game.TITLE_ROWS.len) * MENU_STEP + 20, font.SMALL, look.DIM);
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
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    mid(g, "OPTIONS", cy - 120, font.TITLE, look.TEXT);
    for (game.OPTION_ROWS, 0..) |row, i| {
        const label: [:0]const u8 = switch (row) {
            .mute => fmt(&buf, "Sound: {s}", .{if (g.muted) "off" else "on"}),
            .music => fmt(&buf, "Music  < {s} >", .{bar(buf[100..], g.audio.music_vol)}),
            .sfx => fmt(&buf, "Effects  < {s} >", .{bar(buf[100..], g.audio.sfx_vol)}),
            .fullscreen => fmt(&buf, "Fullscreen: {s}", .{if (game.fullscreen()) "on" else "off"}),
            .back => "Back",
        };
        menuRow(g, label, cy, i, i == g.option_row);
    }
    mid(g, NAV ++ " left and right set a volume   Alt+Enter toggles fullscreen anywhere", cy + @as(i32, game.OPTION_ROWS.len) * MENU_STEP + 10, font.SMALL, look.DIM);
}

/// A volume as a pip a step, ASCII.
fn bar(buf: []u8, v: f32) []const u8 {
    const on: usize = @intFromFloat(@round(std.math.clamp(v, 0, 1) * @as(f32, @floatFromInt(PIPS))));
    for (0..PIPS) |i| buf[i] = if (i < on) '#' else '-';
    return buf[0..PIPS];
}

fn drawOver(g: *Game) void {
    var buf: [BUF]u8 = undefined;
    var t: [16]u8 = undefined;
    veil(g);
    const cy = @divTrunc(g.screen.y, 2);
    const won = g.run.outcome == .won;
    mid(g, if (won) "VICTORY" else "THE PARTY HAS FALLEN", cy - 90, font.TITLE, if (won) look.BRIGHT else look.LIFE);
    mid(g, fmt(&buf, "{s}   {d} slain", .{ clock(&t, g.run.t), g.run.kills }), cy - 10, font.HEAD, look.TEXT);
    mid(g, A ++ " play again", cy + 40, font.BODY, look.DIM);
}

test "the clock reads minutes and seconds" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("20:00", clock(&buf, director.BOSS_AT));
    try std.testing.expectEqualStrings("01:05", clock(&buf, 65.9));
}
