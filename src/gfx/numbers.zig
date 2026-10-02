const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const run = @import("../play/run.zig");
const look = @import("look.zig");
const font = @import("font.zig");

// EVERY FLOATING NUMBER: what a hit, a burn or a heal came to, risen off the body it landed on.

const V = mathx.V;
const MAX: usize = 320;
const LIFE_S: f32 = 0.75;
/// Cells a second it rises, and cells it starts above the ground point.
const RISE: f32 = 1.1;
const LIFT: f32 = 0.7;
const SIZE: i32 = 18;
const CRIT_SIZE: i32 = 26;
/// Opacity at the smallest amount, and the amount from which a number is wholly opaque.
const FAINT_A: f32 = 0.3;
const FULL_AT: f32 = 60;
/// Under this, nothing is shown.
const SHOWN_MIN: f32 = 0.5;

pub const Kind = enum { hit, crit, party, burn, poison, heal };

pub fn colour(k: Kind) rl.Color {
    return switch (k) {
        .hit => rl.Color.white,
        .crit => look.BRIGHT,
        .party => look.HARM,
        .burn => look.rgb(0xff9a3a),
        .poison => look.rgb(0xc8e040),
        .heal => look.rgb(0xb8f0b0),
    };
}

/// A crit is always whole; the rest grow from faint toward whole as the amount does, on a log scale.
pub fn alphaOf(k: Kind, amount: f32) f32 {
    if (k == .crit) return 1;
    return std.math.clamp(FAINT_A + (1 - FAINT_A) * @log(1 + amount) / @log(1 + FULL_AT), FAINT_A, 1);
}

pub fn kindOf(e: run.Event) ?Kind {
    return switch (e.kind) {
        .hit => if (e.crit) .crit else .hit,
        .hurt => .party,
        .burn => .burn,
        .poison => .poison,
        .heal => .heal,
        else => null,
    };
}

const Number = struct { at: V, amount: f32, kind: Kind, life: f32 = 0, drift: f32 };

pub const Numbers = struct {
    items: [MAX]Number = undefined,
    head: usize = 0,
    rng: mathx.Rng = mathx.Rng.init(0xD16175),

    pub fn clear(self: *Numbers) void {
        for (&self.items) |*n| n.life = 0;
    }

    pub fn take(self: *Numbers, e: run.Event) void {
        const k = kindOf(e) orelse return;
        if (e.amount < SHOWN_MIN) return;
        self.items[self.head] = .{ .at = e.at, .amount = e.amount, .kind = k, .life = LIFE_S, .drift = self.rng.span(-0.35, 0.35) };
        self.head = (self.head + 1) % MAX;
    }

    pub fn step(self: *Numbers, dt: f32) void {
        for (&self.items) |*n| {
            if (n.life <= 0) continue;
            n.life -= dt;
            n.at[0] += n.drift * dt;
            n.at[1] -= RISE * dt * (n.life / LIFE_S);
        }
    }

    /// `cam` is the world pixel at the screen's top-left.
    pub fn draw(self: *const Numbers, face: font.Face, cam: V, cell: f32) void {
        var buf: [16]u8 = undefined;
        for (self.items) |n| {
            if (n.life <= 0) continue;
            const t = 1 - n.life / LIFE_S;
            const fade = 1 - mathx.smooth((t - 0.6) / 0.4);
            const pop: f32 = if (n.kind == .crit) 1 + 0.5 * (1 - mathx.smooth(t / 0.15)) else 1;
            const size: i32 = @intFromFloat(@as(f32, @floatFromInt(if (n.kind == .crit) CRIT_SIZE else SIZE)) * pop);
            const s = std.fmt.bufPrintZ(&buf, "{d:.0}", .{@max(1, @round(n.amount))}) catch continue;
            const x: i32 = @intFromFloat(n.at[0] * cell - cam[0]);
            const y: i32 = @intFromFloat((n.at[1] - LIFT) * cell - cam[1]);
            face.mid(s, x, y - @divTrunc(size, 2), size, look.fade(colour(n.kind), alphaOf(n.kind, n.amount) * fade));
        }
    }
};

test "a number's opacity grows with its amount, and a crit is whole" {
    std.debug.print("hit opacity by amount:", .{});
    var last: f32 = 0;
    for ([_]f32{ 1, 5, 15, 40, 60, 200 }) |a| {
        const o = alphaOf(.hit, a);
        std.debug.print(" {d}:{d:.2}", .{ a, o });
        try std.testing.expect(o >= last);
        last = o;
    }
    std.debug.print("\n", .{});
    try std.testing.expectEqual(@as(f32, 1), alphaOf(.crit, 1));
    try std.testing.expectEqual(@as(f32, 1), alphaOf(.hit, FULL_AT));
    try std.testing.expectEqual(Kind.crit, kindOf(.{ .kind = .hit, .at = .{ 0, 0 }, .crit = true }).?);
    try std.testing.expectEqual(Kind.party, kindOf(.{ .kind = .hurt, .at = .{ 0, 0 } }).?);
}
