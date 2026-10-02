const std = @import("std");
const mathx = @import("../core/mathx.zig");
const foe = @import("foe.zig");

// WHAT COMES WHEN. Twenty minutes of rising pressure, a brute each minute carrying a recruit, then the lich.

pub const RUN_S: f32 = 1200;
pub const BOSS_AT: f32 = RUN_S;
/// Foes a second at the start, and what each second adds.
const RATE0: f32 = 0.45;
const RATE_PER_S: f32 = 0.009;
/// Under the boss the horde thins to this share.
const BOSS_RATE: f32 = 0.35;
pub const ALIVE_MAX: usize = 520;
pub const ELITE_EVERY: f32 = 60;
/// Of a foe's hp, gained per second of the run.
const HP_PER_S: f32 = 1.0 / 190.0;
pub const SURGES = [_]Surge{
    .{ .at = 200, .kind = .bat, .n = 16 },
    .{ .at = 330, .kind = .ghoul, .n = 48 },
    .{ .at = 450, .kind = .bat, .n = 60 },
    .{ .at = 540, .kind = .ghoul, .n = 72 },
    .{ .at = 690, .kind = .hound, .n = 40 },
    .{ .at = 840, .kind = .ghoul, .n = 90 },
    .{ .at = 990, .kind = .bat, .n = 90 },
    .{ .at = 1110, .kind = .husk, .n = 60 },
};

pub const Surge = struct { at: f32, kind: foe.Kind, n: usize };

/// Liches before the last, each at a share of its hp; killing one ends nothing but drops a recruit and xp.
pub const LESSER = [_]Lesser{
    .{ .at = 180, .hp = 0.25 },
    .{ .at = 420, .hp = 0.35 },
    .{ .at = 660, .hp = 0.5 },
    .{ .at = 900, .hp = 0.65 },
};
pub const LESSER_XP: f32 = 40;

pub const Lesser = struct { at: f32, hp: f32 };

pub fn rate(t: f32) f32 {
    const r = RATE0 + RATE_PER_S * t;
    return if (t >= BOSS_AT) r * BOSS_RATE else r;
}

pub fn hpScale(t: f32, share: f32) f32 {
    return 1 + HP_PER_S * t * share;
}

/// Each kind's share of the horde, from when it first comes, growing over `RAMP` seconds to its whole weight.
const MIX = [_]struct { kind: foe.Kind, from: f32, weight: f32 }{
    .{ .kind = .ghoul, .from = 0, .weight = 1 },
    .{ .kind = .bat, .from = 60, .weight = 0.45 },
    .{ .kind = .hound, .from = 240, .weight = 0.2 },
    .{ .kind = .husk, .from = 120, .weight = 0.3 },
    .{ .kind = .spitter, .from = 150, .weight = 0.25 },
    .{ .kind = .imp, .from = 150, .weight = 0.2 },
    .{ .kind = .charger, .from = 300, .weight = 0.15 },
    .{ .kind = .shellback, .from = 240, .weight = 0.15 },
    .{ .kind = .warlock, .from = 270, .weight = 0.1 },
};
const RAMP: f32 = 300;

pub fn pick(t: f32, rng: *mathx.Rng) foe.Kind {
    var total: f32 = 0;
    for (MIX) |m| total += m.weight * std.math.clamp((t - m.from) / RAMP, 0, 1);
    var u = rng.unit() * total;
    for (MIX) |m| {
        u -= m.weight * std.math.clamp((t - m.from) / RAMP, 0, 1);
        if (u <= 0) return m.kind;
    }
    return .ghoul;
}

/// Elites due by `t`, the first at a minute in.
pub fn elitesBy(t: f32) usize {
    if (t >= BOSS_AT) return @intFromFloat(@floor((BOSS_AT - 1) / ELITE_EVERY));
    return @intFromFloat(@floor(t / ELITE_EVERY));
}

test "pressure rises over the run and the boss thins the horde" {
    std.debug.print("foes a second by minute:", .{});
    var last: f32 = 0;
    for (0..20) |m| {
        const r = rate(@as(f32, @floatFromInt(m)) * 60);
        std.debug.print(" {d}:{d:.2}", .{ m, r });
        try std.testing.expect(r > last);
        last = r;
    }
    std.debug.print(" boss:{d:.2}\n", .{rate(BOSS_AT)});
    try std.testing.expect(rate(BOSS_AT) < rate(BOSS_AT - 1));
    try std.testing.expectEqual(@as(usize, 0), elitesBy(59));
    var rng = mathx.Rng.init(3);
    var seen = std.EnumSet(foe.Kind).initEmpty();
    for (0..2000) |_| seen.insert(pick(480, &rng));
    std.debug.print("kinds in the horde at 8:00: {d}\n", .{seen.count()});
    try std.testing.expectEqual(MIX.len, seen.count());
    try std.testing.expectEqual(foe.Kind.ghoul, pick(0, &rng));
    try std.testing.expectEqual(@as(usize, @intFromFloat((BOSS_AT - 1) / ELITE_EVERY)), elitesBy(BOSS_AT + 30));
}
