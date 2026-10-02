const std = @import("std");
const hero = @import("play/hero.zig");
const foe = @import("play/foe.zig");
const run = @import("play/run.zig");
const look = @import("gfx/look.zig");

// DEV ONLY. Every class, its rule, upgrades and branches, and every foe, as JSON on stdout, straight from the tables
// the game plays by: `tools/roster.py` renders it into `docs/roster.html`.

const Named = struct { name: []const u8, desc: []const u8, max: u8 = 0, tag: []const u8 = "" };

const ClassOut = struct {
    name: []const u8,
    colour: []const u8,
    rule: []const u8,
    rule_desc: []const u8,
    hp: f32,
    dmg: f32,
    cd: f32,
    range: f32,
    crit: f32,
    branches: []const Named,
    ups: []const Named,
};

const FoeOut = struct {
    name: []const u8,
    hp: f32,
    speed: f32,
    dmg: f32,
    xp: f32,
    armor: f32,
    turn: f32,
    keep: f32,
    spit_dmg: f32,
    lob_dmg: f32,
    lob_radius: f32,
    warned: bool,
    scales: f32,
};

pub fn write(alloc: std.mem.Allocator, out: anytype) !void {
    var classes = std.ArrayList(ClassOut).init(alloc);
    defer classes.deinit();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    for (hero.CLASSES) |c| {
        const row = hero.class(c);
        var branches = std.ArrayList(Named).init(a);
        if (row.branches) |bs| {
            for (bs) |b| try branches.append(.{ .name = hero.branch(b).name, .desc = hero.branch(b).desc });
        }
        var ups = std.ArrayList(Named).init(a);
        for (hero.ups(c)) |u| try ups.append(.{ .name = hero.up(u).name, .desc = hero.up(u).desc, .max = hero.up(u).max, .tag = @tagName(hero.up(u).tag) });
        const col = look.class(c);
        try classes.append(.{
            .name = row.name,
            .colour = try std.fmt.allocPrint(a, "#{x:0>2}{x:0>2}{x:0>2}", .{ col.r, col.g, col.b }),
            .rule = row.rule,
            .rule_desc = row.rule_desc,
            .hp = row.hp,
            .dmg = row.dmg,
            .cd = row.cd,
            .range = row.range,
            .crit = row.crit,
            .branches = branches.items,
            .ups = ups.items,
        });
    }
    var foes = std.ArrayList(FoeOut).init(alloc);
    defer foes.deinit();
    for (foe.KINDS) |k| {
        const r = foe.row(k);
        try foes.append(.{
            .name = r.name,
            .hp = r.hp,
            .speed = r.speed,
            .dmg = r.dmg,
            .xp = r.xp,
            .armor = r.armor,
            .turn = r.turn,
            .keep = r.keep,
            .spit_dmg = r.spit_dmg,
            .lob_dmg = if (r.lob) |l| l.dmg else 0,
            .lob_radius = if (r.lob) |l| l.radius else 0,
            .warned = if (r.lob) |l| l.warned else false,
            .scales = r.scales,
        });
    }
    try std.json.stringify(.{ .party_speed = run.PARTY_SPEED, .tags = std.meta.fieldNames(hero.Tag), .classes = classes.items, .foes = foes.items }, .{ .whitespace = .indent_2 }, out);
}

pub fn dump() void {
    write(std.heap.c_allocator, std.io.getStdOut().writer()) catch |e| std.debug.print("roster FAILED ({s})\n", .{@errorName(e)});
}

test "the roster names every class and foe" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try write(std.testing.allocator, buf.writer());
    for (hero.CLASSES) |c| try std.testing.expect(std.mem.indexOf(u8, buf.items, hero.class(c).name) != null);
    for (foe.KINDS) |k| try std.testing.expect(std.mem.indexOf(u8, buf.items, foe.row(k).name) != null);
}
