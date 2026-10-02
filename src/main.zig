const std = @import("std");
const game = @import("game.zig");
const roster = @import("roster.zig");

pub fn main() void {
    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch return game.play();
    defer std.process.argsFree(alloc, argv);
    for (argv[1..]) |a| {
        // DEV ONLY.
        if (std.mem.eql(u8, a, "--shot")) return game.shot();
        if (std.mem.eql(u8, a, "--roster")) return roster.dump();
    }
    game.play();
}

test {
    _ = @import("core/mathx.zig");
    _ = @import("core/input.zig");
    _ = @import("play/formation.zig");
    _ = @import("play/hero.zig");
    _ = @import("play/foe.zig");
    _ = @import("play/director.zig");
    _ = @import("play/run.zig");
    _ = @import("gfx/look.zig");
    _ = @import("gfx/font.zig");
    _ = @import("gfx/light.zig");
    _ = @import("gfx/fx.zig");
    _ = @import("gfx/numbers.zig");
    _ = @import("ui/hud.zig");
    _ = @import("sound/audio.zig");
    _ = @import("game.zig");
    _ = @import("roster.zig");
}
