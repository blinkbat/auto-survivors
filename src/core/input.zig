const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// THE ONLY FILE THAT TOUCHES A DEVICE. The pad is primary and the only one the UI names; the keyboard mirrors it.

const PAD: i32 = 0;
const DEAD: f32 = 0.18;
/// Menu steps: a stick past this fires one, held it repeats.
const NAV_FIRE: f32 = 0.6;
const NAV_REARM: f32 = 0.35;
const NAV_DAS: f32 = 0.32;
const NAV_ARR: f32 = 0.11;

pub const NAV_CAPTION = "D-pad";
pub const FULLSCREEN_CAPTION = "Alt+Enter";

pub const Button = enum {
    a,
    b,
    pause,

    fn pad(b: Button) rl.GamepadButton {
        return switch (b) {
            .a => .right_face_down,
            .b => .right_face_right,
            .pause => .middle_right,
        };
    }

    fn keys(b: Button) []const rl.KeyboardKey {
        return switch (b) {
            .a => &.{ .enter, .kp_enter, .space },
            .b => &.{ .backspace, .period },
            .pause => &.{.escape},
        };
    }

    pub fn caption(b: Button) [:0]const u8 {
        return switch (b) {
            .a => "A",
            .b => "B",
            .pause => "Menu",
        };
    }
};

const BUTTONS = std.enums.values(Button);

pub const Nav = enum { up, down, left, right };

const NAV_PAD = std.EnumArray(Nav, rl.GamepadButton).init(.{ .up = .left_face_up, .down = .left_face_down, .left = .left_face_left, .right = .left_face_right });
const NAV_KEYS = std.EnumArray(Nav, []const rl.KeyboardKey).init(.{
    .up = &.{ .up, .w },
    .down = &.{ .down, .s },
    .left = &.{ .left, .a },
    .right = &.{ .right, .d },
});

/// raylib closes the window on Esc unless its exit key is cleared. Needs the window open.
pub fn claimKeys() void {
    rl.setExitKey(.null);
}

pub const State = struct {
    pressed: std.EnumSet(Button) = .initEmpty(),
    /// Length at most 1.
    move: mathx.V = .{ 0, 0 },
    nav: ?Nav = null,
    held_nav: ?Nav = null,
    nav_t: f32 = 0,
    nav_due: f32 = 0,
    fullscreen: bool = false,

    pub fn hit(self: State, b: Button) bool {
        return self.pressed.contains(b);
    }

    pub fn update(self: *State, dt: f32) void {
        const pad = rl.isGamepadAvailable(PAD);
        const alt = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
        for (BUTTONS) |b| {
            var on = pad and rl.isGamepadButtonPressed(PAD, b.pad());
            if (!alt) {
                for (b.keys()) |k| on = on or rl.isKeyPressed(k);
            }
            self.pressed.setPresent(b, on);
        }
        self.fullscreen = alt and (rl.isKeyPressed(.enter) or rl.isKeyPressed(.kp_enter));

        var stick: mathx.V = .{ 0, 0 };
        if (pad) stick = .{ rl.getGamepadAxisMovement(PAD, .left_x), rl.getGamepadAxisMovement(PAD, .left_y) };
        const l = mathx.len(stick);
        var move: mathx.V = if (l < DEAD) .{ 0, 0 } else mathx.scale(stick, @min(1, (l - DEAD) / (1 - DEAD)) / l);
        var digital: mathx.V = .{ 0, 0 };
        for (std.enums.values(Nav)) |n| {
            var down = pad and rl.isGamepadButtonDown(PAD, NAV_PAD.get(n));
            for (NAV_KEYS.get(n)) |k| down = down or rl.isKeyDown(k);
            if (down) digital = mathx.add(digital, navDelta(n));
        }
        if (mathx.len2(digital) > 0) move = mathx.norm(digital);
        self.move = move;
        self.stepNav(dt, if (mathx.len2(digital) > 0) digital else stick);
    }

    fn stepNav(self: *State, dt: f32, v: mathx.V) void {
        self.nav = null;
        const l = mathx.len(v);
        if (l < NAV_REARM) {
            self.held_nav = null;
            return;
        }
        if (self.held_nav == null and l < NAV_FIRE) return;
        const now: Nav = if (@abs(v[0]) > @abs(v[1])) (if (v[0] > 0) .right else .left) else (if (v[1] > 0) .down else .up);
        if (self.held_nav != now) {
            self.held_nav = now;
            self.nav_t = 0;
            self.nav_due = NAV_DAS;
            self.nav = now;
            return;
        }
        self.nav_t += dt;
        if (self.nav_t >= self.nav_due) {
            self.nav_due = self.nav_t + NAV_ARR;
            self.nav = now;
        }
    }
};

fn navDelta(n: Nav) mathx.V {
    return switch (n) {
        .up => .{ 0, -1 },
        .down => .{ 0, 1 },
        .left => .{ -1, 0 },
        .right => .{ 1, 0 },
    };
}

test "a held menu direction steps once, waits, then repeats" {
    var s = State{};
    const dt: f32 = 1.0 / 120.0;
    var fired: usize = 0;
    var t: f32 = 0;
    while (t < NAV_DAS + NAV_ARR * 3 + dt) : (t += dt) {
        s.stepNav(dt, .{ 1, 0 });
        if (s.nav) |n| {
            try std.testing.expectEqual(Nav.right, n);
            fired += 1;
        }
    }
    std.debug.print("menu steps held {d:.2} s: {d}\n", .{ t, fired });
    try std.testing.expectEqual(@as(usize, 4), fired);
    s.stepNav(dt, .{ 0, 0 });
    s.stepNav(dt, .{ 0, 1 });
    try std.testing.expectEqual(@as(?Nav, .down), s.nav);
}
