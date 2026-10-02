const std = @import("std");

pub const Kind = enum { ghoul, bat, spitter, husk, shellback, charger, hound, imp, warlock, brute, boss };
pub const KINDS = std.enums.values(Kind);

/// A shell it lobs at the ground where a hero stands: it lands after `fuse` seconds and harms every hero within
/// `radius`. A warned one marks the ground it will land on.
pub const Lob = struct { cd: f32, range: f32, fuse: f32, radius: f32, dmg: f32, warned: bool };

pub const Row = struct {
    name: [:0]const u8,
    hp: f32,
    /// Cells a second.
    speed: f32,
    /// Per bite.
    dmg: f32,
    radius: f32,
    xp: f32,
    /// Cells it keeps from its mark; 0 closes to bite.
    keep: f32 = 0,
    /// Seconds between spits; 0 never spits.
    spit_cd: f32 = 0,
    spit_dmg: f32 = 0,
    lob: ?Lob = null,
    /// Radians a second it can turn; 0 turns at once.
    turn: f32 = 0,
    /// Share of every blow it shrugs off.
    armor: f32 = 0,
    /// Weight its mass pushes others aside with.
    mass: f32 = 1,
    /// Share of the run's hp growth it takes.
    scales: f32 = 1,
    /// Hunter's Mark's quarry.
    big: bool = false,
};

pub fn row(k: Kind) Row {
    return switch (k) {
        .ghoul => .{ .name = "ghoul", .hp = 14, .speed = 1.7, .dmg = 13, .radius = 0.34, .xp = 1 },
        .bat => .{ .name = "bat", .hp = 6, .speed = 2.9, .dmg = 8, .radius = 0.28, .xp = 1, .mass = 0.6 },
        .spitter => .{ .name = "spitter", .hp = 20, .speed = 1.3, .dmg = 10, .radius = 0.38, .xp = 2, .keep = 5.5, .spit_cd = 6, .spit_dmg = 10 },
        .husk => .{ .name = "husk", .hp = 70, .speed = 1.0, .dmg = 16, .radius = 0.42, .xp = 3, .mass = 2.5 },
        .shellback => .{ .name = "shellback", .hp = 110, .speed = 0.85, .dmg = 18, .radius = 0.55, .xp = 5, .armor = 0.35, .mass = 3.5 },
        .charger => .{ .name = "charger", .hp = 26, .speed = 4.6, .dmg = 18, .radius = 0.38, .xp = 2, .turn = 1.3, .mass = 1.5 },
        .hound => .{ .name = "hound", .hp = 12, .speed = 3.9, .dmg = 9, .radius = 0.32, .xp = 1, .turn = 2.4 },
        .imp => .{ .name = "imp", .hp = 16, .speed = 1.6, .dmg = 8, .radius = 0.3, .xp = 2, .keep = 5, .lob = .{ .cd = 3.2, .range = 8, .fuse = 0.9, .radius = 0.8, .dmg = 12, .warned = false } },
        .warlock => .{ .name = "warlock", .hp = 34, .speed = 1.1, .dmg = 10, .radius = 0.38, .xp = 4, .keep = 7, .lob = .{ .cd = 6, .range = 10, .fuse = 1.8, .radius = 2.1, .dmg = 34, .warned = true } },
        .brute => .{ .name = "brute", .hp = 240, .speed = 1.2, .dmg = 20, .radius = 0.62, .xp = 12, .mass = 4, .scales = 0.4, .big = true },
        .boss => .{ .name = "lich", .hp = 14000, .speed = 1.1, .dmg = 75, .radius = 1.05, .xp = 0, .keep = 3.5, .spit_cd = 4.2, .spit_dmg = 34, .mass = 20, .scales = 0, .big = true },
    };
}

pub const MAX_RADIUS: f32 = blk: {
    var r: f32 = 0;
    for (KINDS) |k| r = @max(r, row(k).radius);
    break :blk r;
};

test "every foe can be outrun, or turns too slowly to hold a chase, or is a bat" {
    const run = @import("run.zig");
    for (KINDS) |k| {
        const r = row(k);
        try std.testing.expect(r.hp > 0 and r.radius > 0);
        if (k != .bat and r.turn == 0) try std.testing.expect(r.speed < run.PARTY_SPEED);
    }
}
