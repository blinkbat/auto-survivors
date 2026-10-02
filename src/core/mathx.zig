const std = @import("std");

pub const TAU: f32 = std.math.tau;

pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// An eased value this near where it is going lands there exactly.
pub const SETTLE: f32 = 1e-3;

pub fn ease(v: f32, want: f32, up: f32, down: f32) f32 {
    const n = v + (want - v) * (if (want > v) up else down);
    return if (@abs(want - n) < SETTLE) want else n;
}

/// The share of the way an ease at `rate` per second goes in `dt`, the same whatever the frame rate.
pub fn easing(dt: f32, rate: f32) f32 {
    return 1 - @exp(-dt * rate);
}

pub fn smooth(t: f32) f32 {
    const c = std.math.clamp(t, 0, 1);
    return c * c * (3 - 2 * c);
}

/// `i` moved `by` round `n` places.
pub fn wrapIndex(i: usize, by: i32, n: usize) usize {
    return @intCast(@mod(@as(i32, @intCast(i)) + by, @as(i32, @intCast(n))));
}

/// A point or offset in cells, y-down.
pub const V = [2]f32;

pub fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1] };
}

pub fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1] };
}

pub fn scale(a: V, k: f32) V {
    return .{ a[0] * k, a[1] * k };
}

pub fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub fn len2(a: V) f32 {
    return dot(a, a);
}

pub fn len(a: V) f32 {
    return @sqrt(len2(a));
}

pub fn dist2(a: V, b: V) f32 {
    return len2(sub(a, b));
}

pub fn norm(a: V) V {
    const l = len(a);
    return if (l < 1e-6) .{ 0, 0 } else scale(a, 1 / l);
}

pub fn fromHeading(h: f32) V {
    return .{ @sin(h), -@cos(h) };
}

pub fn lerpV(a: V, b: V, t: f32) V {
    return .{ lerpF(a[0], b[0], t), lerpF(a[1], b[1], t) };
}

/// 0 is north, growing clockwise.
pub fn headingOf(v: V) f32 {
    const a = std.math.atan2(v[0], -v[1]);
    return if (a < 0) a + TAU else a;
}

pub fn angleDelta(a: f32, b: f32) f32 {
    var d = @mod(a - b, TAU);
    if (d > TAU / 2.0) d -= TAU;
    return d;
}

pub const P = struct {
    x: i32,
    y: i32,
};

/// Clockwise from north.
pub const Dir = enum(u3) {
    n,
    ne,
    e,
    se,
    s,
    sw,
    w,
    nw,

    pub fn delta(d: Dir) P {
        return DELTAS[@intFromEnum(d)];
    }

    pub fn heading(d: Dir) f32 {
        return @as(f32, @floatFromInt(@intFromEnum(d))) * SECTOR;
    }

    pub fn back(d: Dir) Dir {
        return @enumFromInt(@as(u3, @intFromEnum(d)) +% 4);
    }
};

pub const SECTOR: f32 = TAU / 8.0;

const DELTAS = [8]P{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 1 },
    .{ .x = -1, .y = 0 },
    .{ .x = -1, .y = -1 },
};

pub const ALL_DIRS = std.enums.values(Dir);

pub const HYST: f32 = 0.14;

/// `bias` is the sector held, kept for an extra `HYST` radians so a thumb on a boundary does not flicker.
pub fn dirOf(heading: f32, bias: ?Dir) Dir {
    const raw: Dir = @enumFromInt(@as(u3, @intCast(@mod(@as(i32, @intFromFloat(@floor(heading / SECTOR + 0.5))), 8))));
    const b = bias orelse return raw;
    if (raw == b) return b;
    return if (@abs(angleDelta(heading, b.heading())) <= SECTOR * 0.5 + HYST) b else raw;
}

pub const Rng = struct {
    impl: std.Random.DefaultPrng,

    pub fn init(seed: u64) Rng {
        return .{ .impl = std.Random.DefaultPrng.init(seed) };
    }

    pub fn below(self: *Rng, max: u32) u32 {
        std.debug.assert(max > 0);
        return self.impl.random().uintLessThan(u32, max);
    }

    pub fn chance(self: *Rng, p: f32) bool {
        return self.unit() < p;
    }

    /// [0, 1).
    pub fn unit(self: *Rng) f32 {
        return self.impl.random().float(f32);
    }

    pub fn span(self: *Rng, lo: f32, hi: f32) f32 {
        return lo + (hi - lo) * self.unit();
    }
};

pub fn hash(x: i32, y: i32, seed: u32) u32 {
    var h: u32 = @bitCast(x *% 73856093 ^ y *% 19349663);
    h = (h ^ seed) *% 0x9E3779B1;
    h ^= h >> 15;
    h *%= 0x85EBCA77;
    h ^= h >> 13;
    return h;
}

pub fn unitHash(x: i32, y: i32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) >> 8)) / @as(f32, 1 << 24);
}

test "headings run clockwise from north, y-down" {
    for (ALL_DIRS) |d| {
        const p = d.delta();
        const v = V{ @floatFromInt(p.x), @floatFromInt(p.y) };
        try std.testing.expectEqual(d, dirOf(headingOf(v), null));
        const back = fromHeading(d.heading());
        try std.testing.expectApproxEqAbs(@as(f32, 1), dot(norm(v), back), 1e-5);
    }
    try std.testing.expectEqual(Dir.s, Dir.n.back());
    try std.testing.expectEqual(Dir.nw, Dir.se.back());
}

test "the held sector survives a thumb resting on its boundary" {
    const past = Dir.n.heading() + SECTOR * 0.5 + 0.05;
    try std.testing.expectEqual(Dir.ne, dirOf(past, null));
    try std.testing.expectEqual(Dir.n, dirOf(past, .n));
    try std.testing.expectEqual(Dir.ne, dirOf(past + HYST, .n));
}
