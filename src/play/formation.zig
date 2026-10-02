const std = @import("std");
const mathx = @import("../core/mathx.zig");

// THE 3x3. Slots hold their place on the ground; the facing is the way the party moves, so turning changes which
// slots are the front row, never where anyone stands.

pub const SLOTS: usize = 9;
pub const Slot = u4;
pub const CENTRE: Slot = 4;
pub const Dir = mathx.Dir;

/// Occupied slots, bit per slot.
pub const Mask = std.bit_set.IntegerBitSet(SLOTS);

pub fn offset(s: Slot) mathx.P {
    return .{ .x = @as(i32, s % 3) - 1, .y = @as(i32, s / 3) - 1 };
}

pub fn at(p: mathx.P) ?Slot {
    if (p.x < -1 or p.x > 1 or p.y < -1 or p.y > 1) return null;
    return @intCast((p.y + 1) * 3 + (p.x + 1));
}

pub fn frontCentre(f: Dir) Slot {
    return at(f.delta()).?;
}

/// Within 45 degrees of the facing: three slots, whichever of the eight ways it faces.
pub fn inFront(s: Slot, f: Dir) bool {
    if (s == CENTRE) return false;
    const a = offset(s);
    const b = f.delta();
    const d: f32 = @floatFromInt(a.x * b.x + a.y * b.y);
    const la = @sqrt(@as(f32, @floatFromInt(a.x * a.x + a.y * a.y)));
    const lb = @sqrt(@as(f32, @floatFromInt(b.x * b.x + b.y * b.y)));
    return d / (la * lb) > std.math.sqrt1_2 - 1e-4;
}

/// Next to each other up, down, left or right; never on a diagonal.
pub fn beside(a: Slot, b: Slot) bool {
    const p = offset(a);
    const q = offset(b);
    return @abs(p.x - q.x) + @abs(p.y - q.y) == 1;
}

/// Chebyshev, on the 3x3.
pub fn apart(a: Slot, b: Slot) i32 {
    const p = offset(a);
    const q = offset(b);
    return @intCast(@max(@abs(p.x - q.x), @abs(p.y - q.y)));
}

/// A world heading lies within `half` of the way `f` faces.
pub fn inArc(heading: f32, f: Dir, half: f32) bool {
    return @abs(mathx.angleDelta(heading, f.heading())) <= half;
}

test "the front row is the three slots toward the facing, for all eight facings" {
    for (mathx.ALL_DIRS) |f| {
        var n: usize = 0;
        for (0..SLOTS) |i| {
            const s: Slot = @intCast(i);
            if (inFront(s, f)) n += 1;
            try std.testing.expect(!(inFront(s, f) and inFront(s, f.back())));
        }
        try std.testing.expectEqual(@as(usize, 3), n);
        try std.testing.expect(inFront(frontCentre(f), f));
    }
    try std.testing.expect(inFront(0, .n) and inFront(1, .n) and inFront(2, .n));
    try std.testing.expect(inFront(1, .ne) and inFront(2, .ne) and inFront(5, .ne));
    try std.testing.expect(inFront(7, .s) and !inFront(3, .s));
}

test "turning moves the front-centre round the ring, one slot per eighth" {
    var seen = Mask.initEmpty();
    for (mathx.ALL_DIRS) |f| seen.set(frontCentre(f));
    try std.testing.expectEqual(@as(usize, 8), seen.count());
    try std.testing.expect(!seen.isSet(CENTRE));
    try std.testing.expectEqual(@as(Slot, 1), frontCentre(.n));
    try std.testing.expectEqual(@as(Slot, 5), frontCentre(.e));
}
