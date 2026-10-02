const std = @import("std");
const mathx = @import("../core/mathx.zig");
const formation = @import("formation.zig");
const hero = @import("hero.zig");
const foe = @import("foe.zig");
const director = @import("director.zig");

// ONE RUN: the party, the horde, every shot and orb. Steps at a fixed `STEP`; nothing here reads the screen.

const V = mathx.V;
const Slot = formation.Slot;
const Dir = mathx.Dir;

pub const STEP: f32 = 1.0 / 60.0;
pub const PARTY_SPEED: f32 = 3.4;
/// Cells between neighbouring slots.
pub const SPACING: f32 = 1.1;
pub const HERO_R: f32 = 0.36;
/// Stick deflection under which the party keeps its facing.
const TURN_DEFL: f32 = 0.35;
const GLIDE_RATE: f32 = 12;
pub const BITE_CD: f32 = 0.7;
/// Spits are judged as they cross the formation's edge.
pub const BLOCK_R: f32 = SPACING * 1.5 + 0.35;
const MAGNET_R: f32 = 2.6;
const ORB_SPEED: f32 = 10;
const COLLECT_R: f32 = 0.3;
const BANNER_R: f32 = 1.7;
pub const SPAWN_R: f32 = 17;
const DESPAWN_R: f32 = 27;
pub const FLASH_S: f32 = 0.14;
pub const SWING_S: f32 = 0.22;
const SPIT_SPEED: f32 = 4.6;
const SPIT_LIFE: f32 = 6;
const SPIT_R: f32 = 0.16;
const BOLT_R: f32 = 0.14;
/// A hero with no foe to strike looks again this soon.
const IDLE_CD: f32 = 0.08;
/// Radians between a volley's arrows and a cast's firebolts, and a shot's life as a share of its range's flight.
const VOLLEY_SPREAD: f32 = 0.11;
const CAST_SPREAD: f32 = VOLLEY_SPREAD * 2;
const BOLT_OVERSHOOT: f32 = 1.2;
/// Seconds between a swing and each echo of it.
const ECHO_GAP: f32 = 0.14;
/// Cells within which a foe is struck whatever the cone, it being up against the blade.
const POINT_BLANK: f32 = 0.3;
const SPLASH_SHARE: f32 = 0.5;
const BAT_WOBBLE: f32 = 0.7;
const SPITTER_WINDUP: f32 = 3;
const BOSS_BURST: usize = 16;
const BURST_SPEED: f32 = SPIT_SPEED * 0.8;
const BOSS_SUMMON_S: f32 = 9;
const BOSS_SUMMONS: usize = 5;
/// Cells from the lich its summons rise, and from the party a lich comes in.
const SUMMON_R: f32 = 1.8;
const BOSS_RING: f32 = SPAWN_R - 4;
const SURGE_RING: f32 = SPAWN_R - 2;
/// Cells past touching from which a bite still lands, and from the necromancer a skeleton rises.
const BITE_PAD: f32 = 0.05;
const RAISE_R: f32 = 0.9;
const KNOCK_MASS: f32 = 3;
/// Of an orb's xp, the share spread evenly over every hero but the one that took it.
pub const XP_SHARE: f32 = 0.25;
pub const JAB_S: f32 = 0.16;
/// Burning and poison are shown as one number this often, not one a step.
const DOT_SHOW_S: f32 = 0.5;

pub const MAX_FOES: usize = 640;
const MAX_BOLTS: usize = 256;
const MAX_SPITS: usize = 384;
const MAX_ORBS: usize = 1024;
pub const MAX_BANNERS: usize = 16;
pub const MAX_VINES: usize = 32;
const MAX_SHELLS: usize = 128;
const MAX_CLOUDS: usize = 16;
pub const MAX_SKELETONS: usize = 24;
/// Cells a charmed foe looks for a foe to bite, and a boss's share of a charm.
const CHARM_SIGHT: f32 = 8;
const BOSS_CHARM: f32 = 0.5;
pub const SKEL_R: f32 = 0.3;
const SKEL_SPEED: f32 = 2.6;
const SKEL_CD: f32 = 0.8;
/// Cells a skeleton looks for foes, and from the party it will stray before coming back.
const SKEL_SIGHT: f32 = 7;
const SKEL_LEASH: f32 = 8;
const SKEL_HOME: f32 = 2.5;
/// Cells a lobbed shell rises at the top of its arc, per cell it flies.
pub const LOB_ARC: f32 = 0.35;
const COMMIT_S: f32 = 0.9;
/// Seconds between a vine's lashes, and cells round a vine's tile no foe may stand in.
const LASH_CD: f32 = 0.55;
pub const VINE_R: f32 = 0.42;
pub const LASH_S: f32 = 0.18;
const MAX_EVENTS: usize = 768;
const MAX_LEVELS: usize = 64;

/// The slots a run's party starts in: north, centre, south.
pub const START_SLOTS = [_]Slot{ 1, 4, 7 };

pub const Member = struct {
    id: u32,
    hero: hero.Hero,
    slot: Slot,
    hp: f32,
    at: V,
    stats: hero.Stats,
    cd: f32 = 0,
    flash: f32 = 0,
    swing: f32 = 0,
    /// Its swing's share of a full strike, an echo's falling with each.
    swing_k: f32 = 1,
    echoes: u8 = 0,
    echo_t: f32 = 0,
    echo_dmg: f32 = 0,
    /// Heading of its last attack.
    aim: f32 = 0,
    /// The way its last wound drove it, for its recoil.
    kick: V = .{ 0, 0 },

    /// Everything but `.move`, which waits for a slot.
    pub fn apply(m: *Member, c: hero.Card) void {
        switch (c) {
            .up => |u| m.hero.ups.set(u, m.hero.ups.get(u) + 1),
            .branch => |b| m.hero.branch = b,
            .rest => m.hp = m.stats.max_hp,
            .move => return,
        }
        m.refresh();
    }

    fn refresh(m: *Member) void {
        const s = m.hero.stats();
        if (s.max_hp > m.stats.max_hp) m.hp += s.max_hp - m.stats.max_hp;
        m.stats = s;
        m.hp = @min(m.hp, s.max_hp);
    }
};

pub const Foe = struct {
    uid: u32,
    kind: foe.Kind,
    at: V,
    vel: V = .{ 0, 0 },
    hp: f32,
    max: f32,
    bite: f32 = 0,
    spit: f32 = 0,
    summon: f32 = 0,
    flash: f32 = 0,
    banner: bool = false,
    burn: Dot = .{},
    poison: Dot = .{},
    /// The way its last bite lunged.
    jab: V = .{ 0, 0 },
    /// The lich whose death ends the run, not one of the lesser.
    final: bool = true,
    /// Seconds a Time Stop still holds it, and the damage multiple the party deals it meanwhile.
    frozen: f32 = 0,
    /// Seconds it fights for the party.
    charm: f32 = 0,
    /// Heading it runs on, for a foe that turns slowly.
    heading: f32 = 0,
    /// Seconds it holds its heading after a bite, charging on through.
    commit: f32 = 0,
    lob: f32 = 0,
    shatter: f32 = 1,

    /// Alive and not charmed onto the party's side.
    pub fn hostile(f: Foe) bool {
        return f.hp > 0 and f.charm <= 0;
    }

    /// Cells from `p` to its edge.
    fn gap(f: Foe, p: V) f32 {
        return mathx.len(mathx.sub(f.at, p)) - foe.row(f.kind).radius;
    }
};

/// Harm over time: `dps` for `t` seconds more; `acc` dealt since it was last shown, `show` seconds until it is.
pub const Dot = struct {
    dps: f32 = 0,
    t: f32 = 0,
    acc: f32 = 0,
    show: f32 = 0,

    fn apply(d: *Dot, dps: f32, s: f32) void {
        d.dps = @max(d.dps, dps);
        d.t = s;
    }
};

pub const BoltKind = enum { arrow, fire };

pub const Bolt = struct {
    kind: BoltKind,
    at: V,
    vel: V,
    dmg: f32,
    pierce: u8,
    life: f32,
    splash: f32,
    crit: bool = false,
    big: f32 = 1,
    burn: f32 = 0,
    hits: [8]u32 = undefined,
    hit_n: u8 = 0,

    fn hit(b: *const Bolt, uid: u32) bool {
        return std.mem.indexOfScalar(u32, b.hits[0..b.hit_n], uid) != null;
    }
};

/// A druid's vine, rooted in the middle of a tile.
pub const Vine = struct {
    at: V,
    owner: u32,
    life: f32,
    reach: f32,
    dmg: f32,
    crit: f32,
    crit_mult: f32,
    poison: f32,
    cd: f32 = 0,
    /// Seconds left of its lash, and the way it lashed.
    lash: f32 = 0,
    aim: V = .{ 1, 0 },
};

/// How many of `items` are `id`'s.
fn owned(items: anytype, id: u32) usize {
    var n: usize = 0;
    for (items) |x| n += @intFromBool(x.owner == id);
    return n;
}

pub fn tileOf(p: V) V {
    return .{ @floor(p[0]) + 0.5, @floor(p[1]) + 0.5 };
}

/// A bard's music, lingering where it was played.
pub const Cloud = struct { at: V, owner: u32, life: f32, radius: f32, rate: f32, charm_s: f32 };

/// A necromancer's skeleton: it hunts on its own, and foes hunt it.
pub const Skeleton = struct {
    at: V,
    owner: u32,
    hp: f32,
    max: f32,
    dmg: f32,
    crit: f32,
    crit_mult: f32,
    cd: f32 = 0,
    flash: f32 = 0,
    jab: V = .{ 1, 0 },
    swing: f32 = 0,
};

/// A lobbed shell on its way from `from` to the ground at `at`.
pub const Shell = struct {
    from: V,
    at: V,
    t: f32 = 0,
    fuse: f32,
    radius: f32,
    dmg: f32,
    warned: bool,
};

pub const Spit = struct { at: V, vel: V, dmg: f32, life: f32, big: bool };

pub const Orb = struct { at: V, xp: f32, to: ?u32 = null, speed: f32 = 0 };

pub const EventKind = enum { hit, kill, hurt, fall, block, heal, pulse, level, recruit, swing, merge, smite, loose, cast, spit, blast, boss, burn, lifeline, wave, stop, poison, sprout, lash, lob, boom, strum, charm, raise, crumble };

pub const Event = struct {
    kind: EventKind,
    at: V,
    dir: V = .{ 0, 0 },
    /// Where a lash or a lifeline comes from.
    from: V = .{ 0, 0 },
    foe: ?foe.Kind = null,
    class: ?hero.Class = null,
    big: bool = false,
    crit: bool = false,
    /// Damage or healing it shows.
    amount: f32 = 0,
};

pub const Outcome = enum { running, won, lost };

const BIN_N: i32 = 64;
const BINS: usize = BIN_N * BIN_N;

const Bins = struct {
    origin: mathx.P = .{ .x = 0, .y = 0 },
    head: [BINS]i32 = undefined,
    next: [MAX_FOES]i32 = undefined,

    fn index(b: *const Bins, p: V) ?usize {
        const x = @as(i32, @intFromFloat(@floor(p[0]))) - b.origin.x;
        const y = @as(i32, @intFromFloat(@floor(p[1]))) - b.origin.y;
        if (x < 0 or y < 0 or x >= BIN_N or y >= BIN_N) return null;
        return @intCast(y * BIN_N + x);
    }

    fn build(b: *Bins, centre: V, foes: []const Foe) void {
        b.origin = .{ .x = @as(i32, @intFromFloat(@floor(centre[0]))) - @divTrunc(BIN_N, 2), .y = @as(i32, @intFromFloat(@floor(centre[1]))) - @divTrunc(BIN_N, 2) };
        @memset(&b.head, -1);
        for (foes, 0..) |f, i| {
            const k = b.index(f.at) orelse {
                b.next[i] = -1;
                continue;
            };
            b.next[i] = b.head[k];
            b.head[k] = @intCast(i);
        }
    }

    /// Foes binned within `r` cells of `p`'s bin, a bin's worth loose.
    const Near = struct {
        b: *const Bins,
        x0: i32,
        x1: i32,
        y1: i32,
        x: i32,
        y: i32,
        cur: i32 = -1,

        pub fn next(n: *Near) ?usize {
            while (true) {
                if (n.cur >= 0) {
                    const i: usize = @intCast(n.cur);
                    n.cur = n.b.next[i];
                    return i;
                }
                if (n.y > n.y1) return null;
                if (n.x >= 0 and n.y >= 0 and n.x < BIN_N and n.y < BIN_N) n.cur = n.b.head[@intCast(n.y * BIN_N + n.x)];
                n.x += 1;
                if (n.x > n.x1) {
                    n.x = n.x0;
                    n.y += 1;
                }
            }
        }
    };

    fn near(b: *const Bins, p: V, r: f32) Near {
        const x0 = @as(i32, @intFromFloat(@floor(p[0] - r))) - b.origin.x;
        const y0 = @as(i32, @intFromFloat(@floor(p[1] - r))) - b.origin.y;
        return .{
            .b = b,
            .x0 = x0,
            .x1 = @as(i32, @intFromFloat(@floor(p[0] + r))) - b.origin.x,
            .y1 = @as(i32, @intFromFloat(@floor(p[1] + r))) - b.origin.y,
            .x = x0,
            .y = y0,
        };
    }
};

fn Pool(comptime T: type, comptime N: usize) type {
    return struct {
        items: [N]T = undefined,
        n: usize = 0,

        const Self = @This();

        pub fn slice(p: *Self) []T {
            return p.items[0..p.n];
        }

        pub fn constSlice(p: *const Self) []const T {
            return p.items[0..p.n];
        }

        pub fn push(p: *Self, v: T) ?*T {
            if (p.n == N) return null;
            p.items[p.n] = v;
            p.n += 1;
            return &p.items[p.n - 1];
        }

        pub fn full(p: *const Self) bool {
            return p.n == N;
        }

        pub fn remove(p: *Self, i: usize) void {
            p.n -= 1;
            p.items[i] = p.items[p.n];
        }
    };
}

pub const Run = struct {
    rng: mathx.Rng,
    seed: u64,
    t: f32,
    party: V,
    vel: V,
    facing: Dir,
    members: Pool(Member, formation.SLOTS),
    next_id: u32,
    foes: Pool(Foe, MAX_FOES),
    next_uid: u32,
    bolts: Pool(Bolt, MAX_BOLTS),
    spits: Pool(Spit, MAX_SPITS),
    orbs: Pool(Orb, MAX_ORBS),
    banners: Pool(V, MAX_BANNERS),
    vines: Pool(Vine, MAX_VINES),
    shells: Pool(Shell, MAX_SHELLS),
    clouds: Pool(Cloud, MAX_CLOUDS),
    skeletons: Pool(Skeleton, MAX_SKELETONS),
    levels: Pool(u32, MAX_LEVELS),
    recruits: u8,
    kills: u32,
    spawn_acc: f32,
    elites: usize,
    surges: usize,
    boss_due: bool,
    lessers: usize,
    outcome: Outcome,
    events: Pool(Event, MAX_EVENTS),
    bins: Bins,

    pub fn create(alloc: std.mem.Allocator, seed: u64) !*Run {
        const r = try alloc.create(Run);
        r.reset(seed);
        return r;
    }

    pub fn reset(r: *Run, seed: u64) void {
        r.rng = mathx.Rng.init(seed);
        r.seed = seed;
        r.t = 0;
        r.party = .{ 0, 0 };
        r.vel = .{ 0, 0 };
        r.facing = .n;
        r.members = .{};
        r.next_id = 1;
        r.foes = .{};
        r.next_uid = 1;
        r.bolts = .{};
        r.spits = .{};
        r.orbs = .{};
        r.banners = .{};
        r.vines = .{};
        r.shells = .{};
        r.clouds = .{};
        r.skeletons = .{};
        r.levels = .{};
        r.recruits = 0;
        r.kills = 0;
        r.spawn_acc = 0;
        r.elites = 0;
        r.surges = 0;
        r.boss_due = true;
        r.lessers = 0;
        r.outcome = .running;
        r.events = .{};
        r.bins = .{};
        for (hero.draft(START_SLOTS.len, &r.rng), START_SLOTS) |c, s| _ = r.enlist(hero.Hero.of(c), s);
    }

    fn emit(r: *Run, e: Event) void {
        _ = r.events.push(e);
    }

    pub fn slotAt(r: *const Run, s: Slot) V {
        const o = formation.offset(s);
        return mathx.add(r.party, .{ @as(f32, @floatFromInt(o.x)) * SPACING, @as(f32, @floatFromInt(o.y)) * SPACING });
    }

    fn enlist(r: *Run, h: hero.Hero, s: Slot) ?*Member {
        const stats = h.stats();
        const m = r.members.push(.{ .id = r.next_id, .hero = h, .slot = s, .hp = stats.max_hp, .at = r.slotAt(s), .stats = stats }) orelse return null;
        r.next_id += 1;
        return m;
    }

    pub fn memberAt(r: *Run, s: Slot) ?*Member {
        for (r.members.slice()) |*m| {
            if (m.slot == s) return m;
        }
        return null;
    }

    pub fn byId(r: *Run, id: u32) ?*Member {
        for (r.members.slice()) |*m| {
            if (m.id == id) return m;
        }
        return null;
    }

    pub fn drainEvents(r: *Run) []const Event {
        const out = r.events.constSlice();
        r.events.n = 0;
        return out;
    }

    pub fn step(r: *Run, move: V) void {
        if (r.outcome != .running) return;
        r.t += STEP;
        r.steer(move);
        r.tickMembers();
        r.spawn();
        r.moveFoes();
        r.attack();
        r.lashVines();
        r.sing();
        r.marchSkeletons();
        r.flyBolts();
        r.flySpits();
        r.landShells();
        r.reap();
        r.gather();
        r.bury();
        if (r.members.n == 0) r.outcome = .lost;
    }

    fn steer(r: *Run, move: V) void {
        const l = mathx.len(move);
        const m = if (l > 1) mathx.scale(move, 1 / l) else move;
        r.vel = mathx.scale(m, PARTY_SPEED);
        r.party = mathx.add(r.party, mathx.scale(r.vel, STEP));
        if (l > TURN_DEFL) r.facing = mathx.dirOf(mathx.headingOf(move), r.facing);
    }

    fn tickMembers(r: *Run) void {
        const k = mathx.easing(STEP, GLIDE_RATE);
        for (r.members.slice()) |*m| {
            m.at = mathx.lerpV(m.at, r.slotAt(m.slot), k);
            m.cd -= STEP;
            m.flash = @max(0, m.flash - STEP);
            m.swing = @max(0, m.swing - STEP);
            m.hp = @min(m.stats.max_hp, m.hp + m.stats.regen * r.healOf(m) * STEP);
        }
    }

    pub fn spawnAt(r: *Run, kind: foe.Kind, at: V) ?*Foe {
        const row = foe.row(kind);
        const hp = row.hp * director.hpScale(r.t, row.scales);
        const lob_cd = if (row.lob) |l| l.cd else 0;
        const f = r.foes.push(.{ .uid = r.next_uid, .kind = kind, .at = at, .hp = hp, .max = hp, .spit = row.spit_cd * r.rng.unit() + SPITTER_WINDUP, .lob = lob_cd * r.rng.unit() + SPITTER_WINDUP, .heading = mathx.headingOf(mathx.sub(r.party, at)) }) orelse return null;
        r.next_uid += 1;
        return f;
    }

    fn ringPoint(r: *Run, radius: f32) V {
        return mathx.add(r.party, mathx.scale(mathx.fromHeading(r.rng.unit() * mathx.TAU), radius));
    }

    fn spawn(r: *Run) void {
        r.spawn_acc += director.rate(r.t) * STEP;
        while (r.spawn_acc >= 1) {
            r.spawn_acc -= 1;
            if (r.foes.n >= director.ALIVE_MAX) break;
            _ = r.spawnAt(director.pick(r.t, &r.rng), r.ringPoint(SPAWN_R + r.rng.span(0, 2)));
        }
        while (r.elites < director.elitesBy(r.t)) {
            const f = r.spawnAt(.brute, r.ringPoint(SPAWN_R)) orelse break;
            f.banner = true;
            r.elites += 1;
        }
        while (r.surges < director.SURGES.len and r.t >= director.SURGES[r.surges].at) {
            const s = director.SURGES[r.surges];
            r.surges += 1;
            for (0..s.n) |i| {
                const h = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(s.n)) * mathx.TAU;
                _ = r.spawnAt(s.kind, mathx.add(r.party, mathx.scale(mathx.fromHeading(h), SURGE_RING)));
            }
        }
        while (r.lessers < director.LESSER.len and r.t >= director.LESSER[r.lessers].at) {
            const l = director.LESSER[r.lessers];
            const b = r.spawnAt(.boss, r.ringPoint(BOSS_RING)) orelse break;
            r.lessers += 1;
            b.hp *= l.hp;
            b.max *= l.hp;
            b.banner = true;
            b.final = false;
            r.emit(.{ .kind = .boss, .at = b.at, .foe = .boss });
        }
        if (r.boss_due and r.t >= director.BOSS_AT) {
            if (r.spawnAt(.boss, r.ringPoint(BOSS_RING))) |b| {
                r.boss_due = false;
                r.emit(.{ .kind = .boss, .at = b.at, .foe = .boss });
            }
        }
    }

/// What a foe hunts: the nearest hero or skeleton.
    fn markOf(r: *Run, p: V) V {
        var best = if (r.nearestMember(p)) |m| m.at else r.party;
        var bd = mathx.dist2(best, p);
        for (r.skeletons.constSlice()) |k| {
            const d = mathx.dist2(k.at, p);
            if (d < bd) {
                bd = d;
                best = k.at;
            }
        }
        return best;
    }

    /// A charmed foe hunts the nearest foe that is not, and bites it.
    fn turned(r: *Run, f: *Foe) void {
        const row = foe.row(f.kind);
        var best: ?usize = null;
        var bd: f32 = CHARM_SIGHT * CHARM_SIGHT;
        for (r.foes.constSlice(), 0..) |o, i| {
            if (o.charm > 0 or o.hp <= 0 or o.uid == f.uid) continue;
            const d = mathx.dist2(o.at, f.at);
            if (d < bd) {
                bd = d;
                best = i;
            }
        }
        const i = best orelse {
            f.vel = .{ 0, 0 };
            return;
        };
        const o = &r.foes.items[i];
        const off = mathx.sub(o.at, f.at);
        const d = mathx.len(off);
        const dir = mathx.norm(off);
        f.vel = mathx.scale(dir, row.speed);
        const reach = row.radius + foe.row(o.kind).radius + BITE_PAD;
        if (d > reach) {
            f.at = mathx.add(f.at, mathx.scale(f.vel, STEP));
            return;
        }
        if (f.bite > 0) return;
        f.bite = BITE_CD;
        f.jab = dir;
        r.wound(o, row.dmg, dir, false, false);
    }

    fn nearestMember(r: *Run, p: V) ?*Member {
        var best: ?*Member = null;
        var bd: f32 = std.math.inf(f32);
        for (r.members.slice()) |*m| {
            const d = mathx.dist2(m.at, p);
            if (d < bd) {
                bd = d;
                best = m;
            }
        }
        return best;
    }

    fn moveFoes(r: *Run) void {
        r.bins.build(r.party, r.foes.constSlice());
        for (r.foes.slice()) |*f| {
            const row = foe.row(f.kind);
            f.flash = @max(0, f.flash - STEP);
            f.bite -= STEP;
            r.tickDot(f, &f.burn, .burn);
            r.tickDot(f, &f.poison, .poison);
            if (f.frozen > 0) {
                f.frozen -= STEP;
                f.vel = .{ 0, 0 };
                continue;
            }
            if (f.charm > 0) {
                f.charm -= STEP;
                r.turned(f);
                continue;
            }
            const mark = r.markOf(f.at);
            const to = mathx.sub(mark, f.at);
            const d = mathx.len(to);
            var dir = mathx.norm(to);
            if (row.keep > 0) {
                if (d < row.keep - 0.5) {
                    dir = mathx.scale(dir, -0.6);
                } else if (d < row.keep + 1) {
                    dir = mathx.scale(.{ -dir[1], dir[0] }, 0.4);
                }
            }
            if (f.kind == .bat) {
                const w = @sin(r.t * 5 + @as(f32, @floatFromInt(f.uid % 97))) * BAT_WOBBLE;
                const c = @cos(w);
                const s = @sin(w);
                dir = .{ dir[0] * c - dir[1] * s, dir[0] * s + dir[1] * c };
            }
            if (row.turn > 0) {
                const want = mathx.headingOf(dir);
                f.commit = @max(0, f.commit - STEP);
                if (f.commit <= 0) f.heading += std.math.clamp(mathx.angleDelta(want, f.heading), -row.turn * STEP, row.turn * STEP);
                dir = mathx.fromHeading(f.heading);
            }
            f.vel = mathx.scale(dir, row.speed);
            f.at = mathx.add(f.at, mathx.scale(f.vel, STEP));
            if (row.lob) |l| r.lobFrom(f, l, mark, d);
            if (row.spit_cd > 0) r.spitFrom(f, mark, d);
            if (f.kind == .boss) r.summon(f);
        }
        r.separate();
        for (r.foes.slice()) |*f| {
            const row = foe.row(f.kind);
            for (r.members.slice()) |*m| {
                const reach = row.radius + HERO_R;
                const off = mathx.sub(f.at, m.at);
                const d2 = mathx.len2(off);
                if (d2 >= reach * reach) continue;
                const d = @sqrt(d2);
                const n = if (d < 1e-4) mathx.fromHeading(@floatFromInt(f.uid)) else mathx.scale(off, 1 / d);
                if (f.commit <= 0) f.at = mathx.add(m.at, mathx.scale(n, reach));
                if (f.bite <= 0 and f.frozen <= 0 and f.charm <= 0) {
                    f.bite = BITE_CD;
                    f.jab = mathx.scale(n, -1);
                    if (row.turn > 0) f.commit = COMMIT_S;
                    r.hurtMember(m, row.dmg, f.jab);
                    if (m.stats.thorns > 0) r.wound(f, m.stats.thorns, n, true, false);
                }
            }
            for (r.skeletons.slice()) |*k| {
                const reach = row.radius + SKEL_R;
                const off = mathx.sub(f.at, k.at);
                const d2 = mathx.len2(off);
                if (d2 >= reach * reach or d2 < 1e-8) continue;
                const n = mathx.scale(off, 1 / @sqrt(d2));
                f.at = mathx.add(k.at, mathx.scale(n, reach));
                if (f.bite <= 0 and f.frozen <= 0 and f.charm <= 0) {
                    f.bite = BITE_CD;
                    f.jab = mathx.scale(n, -1);
                    k.hp -= row.dmg;
                    k.flash = FLASH_S;
                    r.emit(.{ .kind = .hurt, .at = k.at, .dir = f.jab, .class = .necromancer, .amount = row.dmg });
                }
            }
            for (r.vines.constSlice()) |v| {
                const reach = row.radius + VINE_R;
                const off = mathx.sub(f.at, v.at);
                const d2 = mathx.len2(off);
                if (d2 >= reach * reach or d2 < 1e-8) continue;
                f.at = mathx.add(v.at, mathx.scale(off, reach / @sqrt(d2)));
            }
            if (mathx.dist2(f.at, r.party) > DESPAWN_R * DESPAWN_R) f.at = r.ringPoint(SPAWN_R);
        }
    }

    fn tickDot(r: *Run, f: *Foe, d: *Dot, kind: EventKind) void {
        if (d.t <= 0) return;
        d.t -= STEP;
        f.hp -= d.dps * STEP;
        d.acc += d.dps * STEP;
        d.show -= STEP;
        if (d.show > 0 and f.hp > 0) return;
        r.emit(.{ .kind = kind, .at = f.at, .foe = f.kind, .amount = d.acc });
        d.acc = 0;
        d.show = DOT_SHOW_S;
    }

    fn separate(r: *Run) void {
        const foes = r.foes.slice();
        for (foes, 0..) |*a, i| {
            const ra = foe.row(a.kind);
            var it = r.bins.near(a.at, ra.radius + foe.MAX_RADIUS);
            while (it.next()) |j| {
                if (j <= i) continue;
                const b = &foes[j];
                const rb = foe.row(b.kind);
                const reach = ra.radius + rb.radius;
                const off = mathx.sub(b.at, a.at);
                const d2 = mathx.len2(off);
                if (d2 >= reach * reach or d2 < 1e-8) continue;
                const d = @sqrt(d2);
                const push = mathx.scale(off, (reach - d) / d);
                const wa = rb.mass / (ra.mass + rb.mass);
                a.at = mathx.sub(a.at, mathx.scale(push, wa));
                b.at = mathx.add(b.at, mathx.scale(push, 1 - wa));
            }
        }
    }

    fn spitFrom(r: *Run, f: *Foe, mark: V, d: f32) void {
        const row = foe.row(f.kind);
        if (d > row.keep + 4) return;
        f.spit -= STEP;
        if (f.spit > 0) return;
        f.spit = row.spit_cd;
        if (f.kind == .boss) {
            const turn = r.rng.unit();
            for (0..BOSS_BURST) |i| {
                const h = (@as(f32, @floatFromInt(i)) + turn) / @as(f32, @floatFromInt(BOSS_BURST)) * mathx.TAU;
                _ = r.spits.push(.{ .at = f.at, .vel = mathx.scale(mathx.fromHeading(h), BURST_SPEED), .dmg = row.spit_dmg, .life = SPIT_LIFE, .big = true });
            }
        }
        r.emit(.{ .kind = .spit, .at = f.at, .foe = f.kind, .big = f.kind == .boss });
        _ = r.spits.push(.{ .at = f.at, .vel = mathx.scale(mathx.norm(mathx.sub(mark, f.at)), SPIT_SPEED), .dmg = row.spit_dmg, .life = SPIT_LIFE, .big = f.kind == .boss });
    }

    fn lobFrom(r: *Run, f: *Foe, l: foe.Lob, mark: V, d: f32) void {
        if (d > l.range) return;
        f.lob -= STEP;
        if (f.lob > 0) return;
        f.lob = l.cd;
        _ = r.shells.push(.{ .from = f.at, .at = mark, .fuse = l.fuse, .radius = l.radius, .dmg = l.dmg, .warned = l.warned });
        r.emit(.{ .kind = .lob, .at = f.at, .foe = f.kind, .big = l.warned });
    }

    /// A shell arcs over the Shield Wall; where it lands, every hero within its radius is harmed.
    fn landShells(r: *Run) void {
        var i: usize = 0;
        while (i < r.shells.n) {
            const s = &r.shells.items[i];
            s.t += STEP;
            if (s.t < s.fuse) {
                i += 1;
                continue;
            }
            for (r.members.slice()) |*m| {
                const reach = s.radius + HERO_R;
                if (mathx.dist2(m.at, s.at) > reach * reach) continue;
                r.hurtMember(m, s.dmg, mathx.norm(mathx.sub(m.at, s.at)));
            }
            r.emit(.{ .kind = .boom, .at = s.at, .amount = s.radius, .big = s.warned });
            r.shells.remove(i);
        }
    }

    fn summon(r: *Run, f: *Foe) void {
        f.summon -= STEP;
        if (f.summon > 0) return;
        f.summon = BOSS_SUMMON_S;
        const at = f.at;
        for (0..BOSS_SUMMONS) |i| {
            const h = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(BOSS_SUMMONS)) * mathx.TAU;
            _ = r.spawnAt(.ghoul, mathx.add(at, mathx.scale(mathx.fromHeading(h), SUMMON_R)));
        }
    }

    fn hurtMember(r: *Run, m: *Member, dmg: f32, dir: V) void {
        const took = dmg * m.stats.taken * r.warded(m.slot);
        m.hp -= took;
        m.flash = FLASH_S;
        m.kick = dir;
        r.emit(.{ .kind = .hurt, .at = m.at, .dir = dir, .class = m.hero.class, .amount = took });
    }

    /// What of a blow reaches a hero in slot `s`, after every Aegis whose Sanctuary covers it.
    pub fn warded(r: *const Run, s: Slot) f32 {
        var k: f32 = 1;
        for (r.members.constSlice()) |c| {
            if (c.stats.aegis > 0 and formation.apart(c.slot, s) <= c.stats.aura) k *= 1 - c.stats.aegis;
        }
        return k;
    }

    /// `dmg`, made critical by `chance` for `mult` times as much.
    fn strike(r: *Run, f: *Foe, dmg: f32, chance: f32, mult: f32, dir: V) void {
        const crit = r.rng.chance(chance);
        r.wound(f, dmg * (if (crit) mult else 1), dir, false, crit);
    }

    fn wound(r: *Run, f: *Foe, dmg: f32, dir: V, big: bool, crit: bool) void {
        if (f.hp <= 0) return;
        const dealt = dmg * (if (f.frozen > 0) f.shatter else 1) * (1 - foe.row(f.kind).armor);
        f.hp -= dealt;
        f.flash = FLASH_S;
        r.emit(.{ .kind = .hit, .at = f.at, .dir = dir, .foe = f.kind, .big = big or crit, .crit = crit, .amount = dealt });
    }

    const Pick = struct { i: usize, d: f32 };

    /// A heading and how far either side of it counts.
    const Cone = struct { heading: f32, half: f32 };

    /// The nearest foe within `range` of `p`, and within `cone` of it if there is one.
    fn nearestFoe(r: *Run, p: V, range: f32, cone: ?Cone) ?Pick {
        var best: ?Pick = null;
        for (r.foes.constSlice(), 0..) |f, i| {
            if (!f.hostile()) continue;
            const d = f.gap(p);
            if (d > range) continue;
            if (cone) |c| {
                if (@abs(mathx.angleDelta(mathx.headingOf(mathx.sub(f.at, p)), c.heading)) > c.half) continue;
            }
            if (best == null or d < best.?.d) best = .{ .i = i, .d = d };
        }
        return best;
    }

    fn attack(r: *Run) void {
        for (r.members.slice()) |*m| {
            if (m.echoes > 0) {
                m.echo_t -= STEP;
                if (m.echo_t <= 0) {
                    m.echo_dmg *= hero.ECHO_FALLOFF;
                    m.swing_k *= hero.ECHO_FALLOFF;
                    r.cleave(m, m.echo_dmg);
                    m.echoes -= 1;
                    m.echo_t = ECHO_GAP;
                }
            }
            if (m.cd > 0) continue;
            const struck = switch (m.hero.class) {
                .knight => r.swing(m),
                .archer => r.volley(m),
                .cleric => r.pulse(m),
                .pyromancer => r.cast(m),
                .mystic => r.stopTime(m),
                .druid => r.plant(m),
                .bard => r.play(m),
                .necromancer => r.raise(m),
            };
            if (!struck) {
                m.cd = IDLE_CD;
                continue;
            }
            m.cd = m.stats.cd;
        }
    }

    fn swing(r: *Run, m: *Member) bool {
        const s = m.stats;
        const pick = r.nearestFoe(m.at, s.range, null) orelse return false;
        m.aim = mathx.headingOf(mathx.sub(r.foes.items[pick.i].at, m.at));
        const dmg = s.dmg * r.power(m);
        m.swing_k = 1;
        r.cleave(m, dmg);
        m.echoes = s.echoes;
        m.echo_t = ECHO_GAP;
        m.echo_dmg = dmg;
        return true;
    }

    /// Every foe in reach within the swing's cone of its aim, or up against the blade, takes `dmg`.
    fn cleave(r: *Run, m: *Member, dmg: f32) void {
        const s = m.stats;
        m.swing = SWING_S;
        r.emit(.{ .kind = .swing, .at = m.at, .dir = mathx.fromHeading(m.aim), .class = .knight });
        for (r.foes.slice()) |*f| {
            if (!f.hostile()) continue;
            const off = mathx.sub(f.at, m.at);
            const d = f.gap(m.at);
            if (d > s.range) continue;
            if (d > POINT_BLANK and @abs(mathx.angleDelta(mathx.headingOf(off), m.aim)) > s.cleave) continue;
            const dir = mathx.norm(off);
            r.strike(f, dmg, s.crit, s.crit_mult, dir);
            if (s.knock > 0) f.at = mathx.add(f.at, mathx.scale(dir, s.knock * @min(1, KNOCK_MASS / (foe.row(f.kind).mass + KNOCK_MASS - 1))));
        }
    }

    /// Volley: the half of the field the archer's slot faces out into, or all of it from the centre.
    pub fn field(m: *const Member) ?Cone {
        if (m.slot == formation.CENTRE) return null;
        const o = formation.offset(m.slot);
        return .{ .heading = mathx.headingOf(.{ @floatFromInt(o.x), @floatFromInt(o.y) }), .half = m.stats.arc };
    }

    fn volley(r: *Run, m: *Member) bool {
        if (!r.shoot(m, .arrow, field(m), VOLLEY_SPREAD)) return false;
        r.emit(.{ .kind = .loose, .at = m.at, .class = .archer });
        return true;
    }

    fn cast(r: *Run, m: *Member) bool {
        if (!r.shoot(m, .fire, null, CAST_SPREAD)) return false;
        r.emit(.{ .kind = .cast, .at = m.at, .class = .pyromancer });
        return true;
    }

    /// Its shots fanned `spread` apart, led onto the nearest foe in reach.
    fn shoot(r: *Run, m: *Member, kind: BoltKind, cone: ?Cone, spread: f32) bool {
        const s = m.stats;
        const pick = r.nearestFoe(m.at, s.range, cone) orelse return false;
        const f = r.foes.items[pick.i];
        const lead = mathx.add(f.at, mathx.scale(f.vel, pick.d / s.shot_speed));
        m.aim = mathx.headingOf(mathx.sub(lead, m.at));
        const dmg = s.dmg * r.power(m);
        const n: f32 = @floatFromInt(s.shots);
        for (0..s.shots) |i| {
            const h = m.aim + (@as(f32, @floatFromInt(i)) - (n - 1) / 2) * spread;
            const crit = r.rng.chance(s.crit);
            _ = r.bolts.push(.{ .kind = kind, .at = m.at, .vel = mathx.scale(mathx.fromHeading(h), s.shot_speed), .dmg = dmg * (if (crit) s.crit_mult else 1), .pierce = s.pierce, .life = s.range / s.shot_speed * BOLT_OVERSHOOT, .splash = s.splash, .crit = crit, .big = s.big, .burn = s.burn_dps });
        }
        return true;
    }

    /// Verdant: what every heal the party receives is multiplied by.
    pub fn healing(r: *const Run) f32 {
        var k: f32 = 1;
        for (r.members.constSlice()) |m| k += m.stats.verdant;
        return k;
    }

/// What a hero's heals are multiplied by: every Verdant in the party, less every necromancer beside it.
    pub fn healOf(r: *const Run, m: *const Member) f32 {
        var k = r.healing();
        if (r.cursed(m.slot)) k *= 1 - hero.CURSE;
        return k;
    }

    pub fn cursed(r: *const Run, s: Slot) bool {
        for (r.members.constSlice()) |o| {
            if (o.hero.class == .necromancer and formation.beside(o.slot, s)) return true;
        }
        return false;
    }

    /// Harp: what a hero's damage is multiplied by, from every bard beside it.
    pub fn power(r: *const Run, m: *const Member) f32 {
        var k: f32 = 1;
        for (r.members.constSlice()) |o| {
            if (o.stats.harp > 0 and formation.beside(o.slot, m.slot)) k += o.stats.harp;
        }
        return k;
    }

    /// Music: played over the nearest foe in reach, one cloud a bard at a time.
    fn play(r: *Run, m: *Member) bool {
        const s = m.stats;
        const pick = r.nearestFoe(m.at, s.range, null) orelse return false;
        const at = r.foes.items[pick.i].at;
        var i: usize = 0;
        while (i < r.clouds.n) {
            if (r.clouds.items[i].owner == m.id) r.clouds.remove(i) else i += 1;
        }
        _ = r.clouds.push(.{ .at = at, .owner = m.id, .life = hero.CLOUD_S, .radius = s.cloud_r, .rate = s.charm_rate, .charm_s = s.charm_s }) orelse return false;
        r.emit(.{ .kind = .strum, .at = at, .amount = s.cloud_r, .class = .bard });
        return true;
    }

    /// Each foe in music is turned, at its cloud's rate a second, for its charm's length; a boss for half.
    fn sing(r: *Run) void {
        var i: usize = 0;
        while (i < r.clouds.n) {
            const c = &r.clouds.items[i];
            c.life -= STEP;
            if (c.life <= 0) {
                r.clouds.remove(i);
                continue;
            }
            i += 1;
            for (r.foes.slice()) |*f| {
                if (f.charm > 0 or mathx.dist2(f.at, c.at) > c.radius * c.radius) continue;
                if (!r.rng.chance(c.rate * STEP)) continue;
                f.charm = c.charm_s * (if (f.kind == .boss) BOSS_CHARM else 1);
                r.emit(.{ .kind = .charm, .at = f.at, .foe = f.kind });
            }
        }
    }

    /// Skeletons: one raised beside the necromancer while it has fewer than it may.
    fn raise(r: *Run, m: *Member) bool {
        const s = m.stats;
        if (owned(r.skeletons.constSlice(), m.id) >= s.skel_max) return false;
        const at = mathx.add(m.at, mathx.scale(mathx.fromHeading(r.rng.unit() * mathx.TAU), RAISE_R));
        _ = r.skeletons.push(.{ .at = at, .owner = m.id, .hp = s.skel_hp, .max = s.skel_hp, .dmg = s.skel_dmg * r.power(m), .crit = s.skel_crit, .crit_mult = s.crit_mult }) orelse return false;
        r.emit(.{ .kind = .raise, .at = at, .class = .necromancer });
        return true;
    }

    /// Each skeleton hunts the nearest foe it can see, comes back when it strays, and falls apart at 0 hp.
    fn marchSkeletons(r: *Run) void {
        var i: usize = 0;
        while (i < r.skeletons.n) {
            const k = &r.skeletons.items[i];
            if (k.hp <= 0) {
                r.emit(.{ .kind = .crumble, .at = k.at });
                r.skeletons.remove(i);
                continue;
            }
            i += 1;
            k.cd -= STEP;
            k.flash = @max(0, k.flash - STEP);
            k.swing = @max(0, k.swing - STEP);
            const home = mathx.sub(r.party, k.at);
            const pick = if (mathx.len2(home) > SKEL_LEASH * SKEL_LEASH) null else r.nearestFoe(k.at, SKEL_SIGHT, null);
            const p = pick orelse {
                if (mathx.len(home) > SKEL_HOME) k.at = mathx.add(k.at, mathx.scale(mathx.norm(home), SKEL_SPEED * STEP));
                continue;
            };
            const f = &r.foes.items[p.i];
            const off = mathx.sub(f.at, k.at);
            const dir = mathx.norm(off);
            if (mathx.len(off) > SKEL_R + foe.row(f.kind).radius + BITE_PAD) {
                k.at = mathx.add(k.at, mathx.scale(dir, SKEL_SPEED * STEP));
                continue;
            }
            if (k.cd > 0) continue;
            k.cd = SKEL_CD;
            k.jab = dir;
            k.swing = SWING_S;
            r.strike(f, k.dmg, k.crit, k.crit_mult, dir);
        }
    }

    /// Vines: one planted on the tile under the nearest foe in reach, while this druid has fewer than it may.
    fn plant(r: *Run, m: *Member) bool {
        const s = m.stats;
        if (owned(r.vines.constSlice(), m.id) >= s.vines) return false;
        const at = r.freeTile(m.at, s.range) orelse return false;
        _ = r.vines.push(.{ .at = at, .owner = m.id, .life = hero.VINE_S, .reach = s.vine_reach, .dmg = s.dmg * r.power(m), .crit = s.crit, .crit_mult = s.crit_mult, .poison = s.poison_dps }) orelse return false;
        r.emit(.{ .kind = .sprout, .at = at, .class = .druid });
        return true;
    }

    /// The tile under the nearest foe in reach that holds no vine yet.
    fn freeTile(r: *Run, p: V, range: f32) ?V {
        var best: ?V = null;
        var bd: f32 = std.math.inf(f32);
        outer: for (r.foes.constSlice()) |f| {
            if (!f.hostile()) continue;
            const d = f.gap(p);
            if (d > range or d >= bd) continue;
            const at = tileOf(f.at);
            for (r.vines.constSlice()) |v| {
                if (v.at[0] == at[0] and v.at[1] == at[1]) continue :outer;
            }
            bd = d;
            best = at;
        }
        return best;
    }

    fn lashVines(r: *Run) void {
        var i: usize = 0;
        while (i < r.vines.n) {
            const v = &r.vines.items[i];
            v.life -= STEP;
            if (v.life <= 0) {
                r.vines.remove(i);
                continue;
            }
            i += 1;
            if (r.byId(v.owner)) |m| {
                v.reach = m.stats.vine_reach;
                v.dmg = m.stats.dmg * r.power(m);
                v.crit = m.stats.crit;
                v.crit_mult = m.stats.crit_mult;
                v.poison = m.stats.poison_dps;
            }
            v.cd -= STEP;
            v.lash = @max(0, v.lash - STEP);
            if (v.cd > 0) continue;
            const pick = r.nearestFoe(v.at, v.reach, null) orelse {
                v.cd = IDLE_CD;
                continue;
            };
            v.cd = LASH_CD;
            const f = &r.foes.items[pick.i];
            const dir = mathx.norm(mathx.sub(f.at, v.at));
            v.aim = dir;
            v.lash = LASH_S;
            r.strike(f, v.dmg, v.crit, v.crit_mult, dir);
            if (v.poison > 0) f.poison.apply(v.poison, hero.POISON_S);
            r.emit(.{ .kind = .lash, .at = f.at, .from = v.at, .big = v.poison > 0 });
        }
    }

    /// Time Stop: every foe within the mystic's reach holds still, taking the Shatter multiple while it does.
    fn stopTime(r: *Run, m: *Member) bool {
        const s = m.stats;
        if (r.nearestFoe(m.at, s.range, null) == null) return false;
        for (r.foes.slice()) |*f| {
            if (f.gap(m.at) > s.range) continue;
            f.shatter = if (f.frozen > 0) @max(f.shatter, s.shatter) else s.shatter;
            f.frozen = @max(f.frozen, s.stop_s);
        }
        r.emit(.{ .kind = .stop, .at = m.at, .amount = s.range, .class = .mystic });
        return true;
    }

    /// Sanctuary, centred on the cleric's own slot.
    fn pulse(r: *Run, m: *Member) bool {
        const s = m.stats;
        const heal = s.heal;
        r.emit(.{ .kind = .pulse, .at = m.at, .class = .cleric, .amount = (@as(f32, @floatFromInt(s.aura)) + 0.5) * SPACING });
        const slot = m.slot;
        const id = m.id;
        const at = m.at;
        for (r.members.slice()) |*o| {
            if (formation.apart(o.slot, slot) > s.aura) continue;
            if (o.id == id and !s.self_heal) continue;
            if (o.hp >= o.stats.max_hp) continue;
            const was = o.hp;
            o.hp = @min(o.stats.max_hp, o.hp + heal * r.healOf(o));
            r.emit(.{ .kind = .heal, .at = o.at, .class = o.hero.class, .amount = o.hp - was });
        }
        if (s.lifeline) {
            var worst: ?*Member = null;
            for (r.members.slice()) |*o| {
                if (o.id == id or formation.apart(o.slot, slot) <= s.aura) continue;
                if (worst == null or o.hp / o.stats.max_hp < worst.?.hp / worst.?.stats.max_hp) worst = o;
            }
            if (worst) |o| {
                if (o.hp < o.stats.max_hp) {
                    const was = o.hp;
                    o.hp = @min(o.stats.max_hp, o.hp + heal * hero.LIFELINE * r.healOf(o));
                    r.emit(.{ .kind = .heal, .at = o.at, .class = o.hero.class, .amount = o.hp - was });
                    r.emit(.{ .kind = .lifeline, .at = o.at, .from = at });
                }
            }
        }
        if (s.smite > 0) {
            const crit = r.rng.chance(s.crit);
            r.emit(.{ .kind = .wave, .at = at, .amount = s.smite_reach });
            for (r.foes.slice()) |*f| {
                if (!f.hostile() or mathx.dist2(f.at, at) > s.smite_reach * s.smite_reach) continue;
                r.wound(f, s.smite * r.power(m) * (if (crit) s.crit_mult else 1), mathx.norm(mathx.sub(f.at, at)), false, crit);
                r.emit(.{ .kind = .smite, .at = f.at });
            }
        }
        return true;
    }

    fn flyBolts(r: *Run) void {
        var i: usize = 0;
        while (i < r.bolts.n) {
            const b = &r.bolts.items[i];
            b.at = mathx.add(b.at, mathx.scale(b.vel, STEP));
            b.life -= STEP;
            if (b.life <= 0 or r.boltHits(b)) {
                r.bolts.remove(i);
                continue;
            }
            i += 1;
        }
    }

    /// True when the bolt is spent.
    fn boltHits(r: *Run, b: *Bolt) bool {
        var it = r.bins.near(b.at, foe.MAX_RADIUS + BOLT_R);
        while (it.next()) |j| {
            if (j >= r.foes.n) continue;
            const f = &r.foes.items[j];
            if (!f.hostile() or b.hit(f.uid)) continue;
            const reach = foe.row(f.kind).radius + BOLT_R;
            if (mathx.dist2(f.at, b.at) > reach * reach) continue;
            const dir = mathx.norm(b.vel);
            const big = f.kind == .brute or f.kind == .boss;
            r.wound(f, b.dmg * (if (big) b.big else 1), dir, false, b.crit);
            if (b.burn > 0) f.burn.apply(b.burn, hero.BURN_S);
            if (b.kind == .fire) r.emit(.{ .kind = .blast, .at = b.at, .dir = dir, .big = b.crit, .amount = b.splash });
            if (b.splash > 0) {
                const at = b.at;
                const uid = f.uid;
                for (r.foes.slice()) |*o| {
                    if (o.uid == uid or o.charm > 0 or mathx.dist2(o.at, at) > b.splash * b.splash) continue;
                    r.wound(o, b.dmg * SPLASH_SHARE, mathx.norm(mathx.sub(o.at, at)), false, false);
                    if (b.burn > 0) o.burn.apply(b.burn, hero.BURN_S);
                }
            }
            if (b.pierce == 0) return true;
            b.pierce -= 1;
            if (b.hit_n < b.hits.len) {
                b.hits[b.hit_n] = f.uid;
                b.hit_n += 1;
            }
        }
        return false;
    }

    /// Shield Wall: half the widest arc of the facing a knight in the front row covers; 0 with none there.
    pub fn shieldArc(r: *const Run) f32 {
        var arc: f32 = 0;
        for (r.members.constSlice()) |m| {
            if (m.hero.class == .knight and formation.inFront(m.slot, r.facing)) arc = @max(arc, m.stats.arc);
        }
        return arc;
    }

    /// What crosses the formation's edge within the Shield Wall's arc is stopped.
    pub fn shielded(r: *const Run, at: V) bool {
        const arc = r.shieldArc();
        return arc > 0 and formation.inArc(mathx.headingOf(mathx.sub(at, r.party)), r.facing, arc);
    }

    fn flySpits(r: *Run) void {
        var i: usize = 0;
        outer: while (i < r.spits.n) {
            const s = &r.spits.items[i];
            const was = mathx.dist2(s.at, r.party);
            s.at = mathx.add(s.at, mathx.scale(s.vel, STEP));
            s.life -= STEP;
            const now = mathx.dist2(s.at, r.party);
            if (s.life <= 0) {
                r.spits.remove(i);
                continue;
            }
            if (was >= BLOCK_R * BLOCK_R and now < BLOCK_R * BLOCK_R and r.shielded(s.at)) {
                r.emit(.{ .kind = .block, .at = s.at, .dir = mathx.norm(s.vel) });
                r.spits.remove(i);
                continue;
            }
            for (r.members.slice()) |*m| {
                const reach = HERO_R + SPIT_R;
                if (mathx.dist2(m.at, s.at) > reach * reach) continue;
                r.hurtMember(m, s.dmg, mathx.norm(s.vel));
                r.spits.remove(i);
                continue :outer;
            }
            i += 1;
        }
    }

    fn reap(r: *Run) void {
        var i: usize = 0;
        while (i < r.foes.n) {
            const f = r.foes.items[i];
            if (f.hp > 0) {
                i += 1;
                continue;
            }
            const row = foe.row(f.kind);
            r.kills += 1;
            r.emit(.{ .kind = .kill, .at = f.at, .foe = f.kind });
            if (row.xp > 0) r.drop(f.at, row.xp);
            if (f.banner) _ = r.banners.push(f.at);
            if (f.kind == .boss and f.final) r.outcome = .won;
            if (f.kind == .boss and !f.final) r.drop(f.at, director.LESSER_XP);
            r.foes.remove(i);
        }
    }

    /// With every orb out, a random one takes the xp instead.
    fn drop(r: *Run, at: V, xp: f32) void {
        if (r.orbs.full()) {
            r.orbs.items[r.rng.below(MAX_ORBS)].xp += xp;
        } else _ = r.orbs.push(.{ .at = at, .xp = xp });
    }

    fn gather(r: *Run) void {
        var i: usize = 0;
        while (i < r.orbs.n) {
            const o = &r.orbs.items[i];
            const m = r.nearestMember(o.at) orelse return;
            const off = mathx.sub(m.at, o.at);
            const d = mathx.len(off);
            if (o.to == null and d > MAGNET_R) {
                i += 1;
                continue;
            }
            o.to = m.id;
            o.speed = @min(ORB_SPEED, o.speed + ORB_SPEED * 3 * STEP);
            const go = o.speed * STEP;
            if (d <= COLLECT_R + go) {
                r.collect(m, o.xp);
                r.orbs.remove(i);
                continue;
            }
            o.at = mathx.add(o.at, mathx.scale(off, go / d));
            i += 1;
        }
        i = 0;
        while (i < r.banners.n) {
            if (mathx.dist2(r.banners.items[i], r.party) > BANNER_R * BANNER_R) {
                i += 1;
                continue;
            }
            r.emit(.{ .kind = .recruit, .at = r.banners.items[i] });
            r.recruits += 1;
            r.banners.remove(i);
        }
    }

    /// The taker keeps most of an orb; the rest of the party splits `XP_SHARE` of it.
    pub fn collect(r: *Run, m: *Member, xp: f32) void {
        if (r.members.n == 1) return r.grant(m, xp);
        const share = xp * XP_SHARE / @as(f32, @floatFromInt(r.members.n - 1));
        const id = m.id;
        r.grant(m, xp * (1 - XP_SHARE));
        for (r.members.slice()) |*o| {
            if (o.id != id) r.grant(o, share);
        }
    }

    pub fn grant(r: *Run, m: *Member, xp: f32) void {
        const gained = m.hero.gain(xp);
        for (0..gained) |_| {
            _ = r.levels.push(m.id);
            r.emit(.{ .kind = .level, .at = m.at, .class = m.hero.class });
        }
    }

    fn bury(r: *Run) void {
        var i: usize = 0;
        while (i < r.members.n) {
            const m = r.members.items[i];
            if (m.hp > 0) {
                i += 1;
                continue;
            }
            r.emit(.{ .kind = .fall, .at = m.at, .class = m.hero.class });
            r.members.remove(i);
        }
    }

    /// The hero whose level-up is waiting, its stale entries dropped.
    pub fn levelHead(r: *Run) ?*Member {
        while (r.levels.n > 0) {
            if (r.byId(r.levels.items[0])) |m| return m;
            r.popLevel();
        }
        return null;
    }

    pub fn popLevel(r: *Run) void {
        if (r.levels.n == 0) return;
        std.mem.copyForwards(u32, r.levels.items[0 .. r.levels.n - 1], r.levels.items[1..r.levels.n]);
        r.levels.n -= 1;
    }

    pub const Place = enum { move, swap, merge, recruit, refused };

    /// What placing a hero of class `c` at `s` would do, the hero being `from` when it is moved rather than recruited.
    pub fn placing(r: *Run, c: hero.Class, s: Slot, from: ?u32) Place {
        const there = r.memberAt(s) orelse return if (from == null) .recruit else .move;
        if (from == there.id) return .refused;
        if (there.hero.class == c and there.hero.rank < hero.RANK_MAX) return .merge;
        return if (from == null) .refused else .swap;
    }

    pub fn moveTo(r: *Run, id: u32, s: Slot) Place {
        const m = r.byId(id) orelse return .refused;
        const p = r.placing(m.hero.class, s, id);
        switch (p) {
            .move => m.slot = s,
            .swap => {
                const o = r.memberAt(s).?;
                o.slot = m.slot;
                m.slot = s;
            },
            .merge => {
                const o = r.memberAt(s).?;
                r.mergeInto(o, m.hero, m.hp / m.stats.max_hp);
                r.reown(id, o.id);
                for (r.members.constSlice(), 0..) |x, i| {
                    if (x.id == id) {
                        r.members.remove(i);
                        break;
                    }
                }
            },
            .recruit, .refused => {},
        }
        return p;
    }

    /// Its waiting level-ups, and everything it left in the field, pass to the hero it merged into.
    fn reown(r: *Run, from: u32, to: u32) void {
        for (r.levels.slice()) |*l| {
            if (l.* == from) l.* = to;
        }
        for (r.vines.slice()) |*v| {
            if (v.owner == from) v.owner = to;
        }
        for (r.clouds.slice()) |*c| {
            if (c.owner == from) c.owner = to;
        }
        for (r.skeletons.slice()) |*k| {
            if (k.owner == from) k.owner = to;
        }
    }

    fn mergeInto(r: *Run, o: *Member, h: hero.Hero, share: f32) void {
        const keep = @max(share, o.hp / o.stats.max_hp);
        o.hero = hero.Hero.merged(o.hero, h);
        o.stats = o.hero.stats();
        o.hp = o.stats.max_hp * keep;
        r.emit(.{ .kind = .merge, .at = o.at, .class = o.hero.class });
    }

    pub fn recruit(r: *Run, c: hero.Class, s: Slot) Place {
        const p = r.placing(c, s, null);
        switch (p) {
            .recruit => _ = r.enlist(hero.Hero.of(c), s),
            .merge => r.mergeInto(r.memberAt(s).?, hero.Hero.of(c), 1),
            else => return p,
        }
        r.recruits -|= 1;
        return p;
    }

    pub fn canRecruit(r: *Run, c: hero.Class) bool {
        for (0..formation.SLOTS) |i| {
            if (r.placing(c, @intCast(i), null) != .refused) return true;
        }
        return false;
    }

    /// The lich if it has come, else a lesser one.
    pub fn boss(r: *const Run) ?*const Foe {
        var any: ?*const Foe = null;
        for (r.foes.constSlice()) |*f| {
            if (f.kind != .boss) continue;
            if (f.final) return f;
            any = any orelse f;
        }
        return any;
    }
};

fn testRun() !*Run {
    const r = try Run.create(std.testing.allocator, 7);
    r.members.n = 0;
    for ([_]hero.Class{ .knight, .cleric, .archer, .pyromancer }, [_]Slot{ 1, 4, 7, 3 }) |c, s| _ = r.enlist(hero.Hero.of(c), s);
    r.boss_due = false;
    r.lessers = 99;
    r.elites = 99;
    r.surges = 99;
    return r;
}

fn hold(r: *Run, move: V, steps: usize) void {
    for (0..steps) |_| {
        r.spawn_acc = 0;
        r.step(move);
    }
}

fn plant(r: *Run, kind: foe.Kind, at: V) *Foe {
    const f = r.spawnAt(kind, at).?;
    f.spit = 0;
    return f;
}

test "a starting party is three different classes, and seeds differ in which" {
    const r = try Run.create(std.testing.allocator, 0);
    defer std.testing.allocator.destroy(r);
    var seen = std.EnumSet(hero.Class).initEmpty();
    for (0..32) |seed| {
        r.reset(seed);
        try std.testing.expectEqual(START_SLOTS.len, r.members.n);
        var classes = std.EnumSet(hero.Class).initEmpty();
        for (r.members.constSlice()) |m| {
            try std.testing.expect(!classes.contains(m.hero.class));
            classes.insert(m.hero.class);
            seen.insert(m.hero.class);
        }
    }
    std.debug.print("classes seen across 32 starting parties: {d}\n", .{seen.count()});
    try std.testing.expectEqual(hero.CLASSES.len, seen.count());
}

test "a druid's vines root on a tile, hold it, lash what comes in reach, and poison with Venom" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const m = r.enlist(hero.Hero.of(.druid), 5).?;
    m.hero.ups.set(.venom, 1);
    m.refresh();
    for (r.members.slice()) |*o| o.cd = if (o.id == m.id) 0 else 99;
    const f = plant(r, .brute, mathx.add(m.at, .{ 3, 0.2 }));
    f.hp = 10_000;
    f.max = 10_000;
    var lashes: usize = 0;
    var poison: f32 = 0;
    for (0..120) |_| {
        for (r.members.slice()) |*o| {
            if (o.id != m.id) o.cd = 99;
        }
        hold(r, .{ 0, 0 }, 1);
        for (r.drainEvents()) |e| {
            lashes += @intFromBool(e.kind == .lash);
            if (e.kind == .poison) poison += e.amount;
        }
    }
    const v = r.vines.items[0];
    const inside = mathx.len(mathx.sub(r.foes.items[0].at, v.at));
    m.hero.ups.set(.long_tendrils, 2);
    m.refresh();
    hold(r, .{ 0, 0 }, 1);
    std.debug.print("druid: {d} vine(s), {d} lashes in 2 s, poison dealt {d:.1}, brute held {d:.2} cells from the vine; two Long Tendrils taken later reach the planted vine: {d:.2}\n", .{ r.vines.n, lashes, poison, inside, r.vines.items[0].reach });
    try std.testing.expectApproxEqAbs(m.stats.vine_reach, r.vines.items[0].reach, 1e-5);
    try std.testing.expect(r.vines.n >= 1 and r.vines.n <= m.stats.vines);
    try std.testing.expect(lashes > 0 and poison > 0);
    try std.testing.expect(inside >= VINE_R + foe.row(.brute).radius - 1e-3);
    try std.testing.expectEqual(v.at[0], @floor(v.at[0]) + 0.5);
}

test "verdant raises every heal the party receives" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const base = r.healing();
    const m = r.enlist(hero.Hero.of(.druid), 5).?;
    m.hero.ups.set(.verdant, 2);
    m.refresh();
    std.debug.print("party healing multiple: {d:.2} without verdant, {d:.2} with two ranks\n", .{ base, r.healing() });
    try std.testing.expectApproxEqAbs(base + 2 * 0.15, r.healing(), 1e-5);
}

test "a swing strikes everything in its cone, and each echo strikes again for half" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const k = r.memberAt(1).?;
    k.hero.ups.set(.echo, 2);
    k.refresh();
    for (r.members.slice()) |*o| o.cd = if (o.id == k.id) 0 else 99;
    const ahead = plant(r, .ghoul, mathx.add(k.at, .{ 0, -1.0 }));
    ahead.hp = 10_000;
    const beside = plant(r, .ghoul, mathx.add(k.at, .{ 0.75, -1.55 }));
    beside.hp = 10_000;
    const wide = plant(r, .ghoul, mathx.add(k.at, .{ 1.6, 0.2 }));
    wide.hp = 10_000;
    k.stats.crit = 0;
    hold(r, .{ 0, 0 }, 1);
    k.cd = 99;
    hold(r, .{ 0, 0 }, 30);
    _ = r.drainEvents();
    const took = [3]f32{ 10_000 - r.foes.items[0].hp, 10_000 - r.foes.items[1].hp, 10_000 - r.foes.items[2].hp };
    std.debug.print("one swing and two echoes: ahead {d:.1}, beside {d:.1}, out of the cone {d:.1}\n", .{ took[0], took[1], took[2] });
    try std.testing.expectApproxEqAbs(k.stats.dmg * 1.75, took[0], 1e-2);
    try std.testing.expectApproxEqAbs(took[0], took[1], 1e-2);
    try std.testing.expectEqual(@as(f32, 0), took[2]);
}

test "a slow-turning charger overshoots, and a warned shell harms only who stands where it lands" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    for (r.members.slice()) |*o| o.cd = 99;
    const c = plant(r, .charger, mathx.add(r.party, .{ -8, 0 }));
    c.heading = mathx.headingOf(.{ 1, 0.6 });
    var nearest: f32 = 99;
    var past = false;
    for (0..180) |_| {
        hold(r, .{ 0, 0 }, 1);
        if (r.foes.n == 0) break;
        const d = mathx.len(mathx.sub(r.foes.items[0].at, r.party));
        nearest = @min(nearest, d);
        past = past or (nearest < 3 and d > nearest + 2);
    }
    std.debug.print("charger: came within {d:.2} cells, then swung back out past {d:.2}: {any}\n", .{ nearest, nearest + 2, past });
    try std.testing.expect(past);
    r.foes.n = 0;
    const knight = r.memberAt(1).?;
    const archer = r.memberAt(7).?;
    const hk = knight.hp;
    const ha = archer.hp;
    _ = r.shells.push(.{ .from = mathx.add(r.party, .{ 0, -8 }), .at = knight.at, .fuse = 1, .radius = 0.8, .dmg = 30, .warned = true });
    hold(r, .{ 0, 0 }, 70);
    std.debug.print("a warned shell on the knight: knight lost {d:.0}, archer two slots away lost {d:.0}\n", .{ hk - knight.hp, ha - archer.hp });
    try std.testing.expect(knight.hp < hk);
    try std.testing.expectEqual(ha, archer.hp);
}

test "a bard's harp lifts only the heroes beside it, and its music turns foes on their own" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const b = r.enlist(hero.Hero.of(.bard), 0).?;
    const beside = r.memberAt(1).?;
    const diagonal = r.memberAt(4).?;
    std.debug.print("harp: hero beside x{d:.2}, diagonal x{d:.2}\n", .{ r.power(beside), r.power(diagonal) });
    try std.testing.expectApproxEqAbs(1 + b.stats.harp, r.power(beside), 1e-5);
    try std.testing.expectEqual(@as(f32, 1), r.power(diagonal));
    b.hero.ups.set(.enchanting_air, 4);
    b.refresh();
    for (r.members.slice()) |*o| o.cd = if (o.id == b.id) 0 else 99;
    const a = plant(r, .brute, mathx.add(r.party, .{ -5, -3 }));
    a.hp = 10_000;
    const victim = plant(r, .ghoul, mathx.add(r.party, .{ -6.5, -3 }));
    victim.hp = 10_000;
    var charmed = false;
    for (0..240) |_| {
        for (r.members.slice()) |*o| {
            if (o.id != b.id) o.cd = 99;
        }
        hold(r, .{ 0, 0 }, 1);
        charmed = charmed or r.foes.items[0].charm > 0;
    }
    std.debug.print("music: the brute was turned {any}, its ghoul neighbour took {d:.0}\n", .{ charmed, 10_000 - r.foes.items[1].hp });
    try std.testing.expect(charmed);
}

test "a necromancer's skeletons fight on their own, and its neighbours are healed less" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const n = r.enlist(hero.Hero.of(.necromancer), 5).?;
    try std.testing.expect(r.cursed(4) and r.cursed(2) and !r.cursed(1));
    std.debug.print("grave chill: the centre heals x{d:.2}, a diagonal x{d:.2}\n", .{ r.healOf(r.memberAt(4).?), r.healOf(r.memberAt(1).?) });
    for (r.members.slice()) |*o| o.cd = if (o.id == n.id) 0 else 99;
    const f = plant(r, .brute, mathx.add(r.party, .{ 5, 0 }));
    f.hp = 10_000;
    for (0..300) |_| {
        for (r.members.slice()) |*o| {
            if (o.id != n.id) o.cd = 99;
        }
        hold(r, .{ 0, 0 }, 1);
    }
    std.debug.print("skeletons: {d} raised, the brute took {d:.0}\n", .{ r.skeletons.n, 10_000 - r.foes.items[0].hp });
    try std.testing.expect(r.skeletons.n > 0 and r.skeletons.n <= n.stats.skel_max);
    try std.testing.expect(r.foes.items[0].hp < 10_000);
}

test "time stop holds every foe in reach still, and the party hits them harder for it" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const m = r.enlist(hero.Hero.of(.mystic), 5).?;
    m.hero.ups.set(.shatter, 2);
    m.refresh();
    const near = plant(r, .brute, mathx.add(m.at, .{ 2.5, 0 }));
    const far = plant(r, .brute, mathx.add(m.at, .{ 9, 0 }));
    near.hp = 10_000;
    far.hp = 10_000;
    for (r.members.slice()) |*o| o.cd = if (o.id == m.id) 0 else 99;
    hold(r, .{ 0, 0 }, 1);
    const held = r.foes.items[0].at;
    hold(r, .{ 0, 0 }, 30);
    const moved = mathx.len(mathx.sub(r.foes.items[0].at, held));
    const other = r.foes.items[1].frozen;
    r.wound(&r.foes.items[0], 10, .{ 1, 0 }, false, false);
    const took = 10_000 - r.foes.items[0].hp;
    std.debug.print("time stop: held foe moved {d:.3} cells in half a second, took {d:.1} of a 10 hit; one out of reach frozen {d:.1} s\n", .{ moved, took, other });
    try std.testing.expect(moved < 1e-4);
    try std.testing.expectApproxEqAbs(m.stats.shatter * 10, took, 1e-3);
    try std.testing.expectEqual(@as(f32, 0), other);
}

test "the archer fires into the half of the field its slot faces" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const f = plant(r, .brute, mathx.add(r.party, .{ 0, -5 }));
    f.hp = 10_000;
    f.max = 10_000;
    const fired = struct {
        fn count(run: *Run) usize {
            var n: usize = 0;
            for (0..60) |_| {
                const was = run.memberAt(7).?.cd;
                hold(run, .{ 0, 0 }, 1);
                const now = run.memberAt(7).?.cd;
                n += @intFromBool(now > was and now > IDLE_CD);
            }
            return n;
        }
    }.count;
    const away = fired(r);
    r.foes.items[0].at = mathx.add(r.party, .{ 0.5, 5 });
    const toward = fired(r);
    std.debug.print("volleys in a second from the south slot: at a foe north {d}, south {d}\n", .{ away, toward });
    try std.testing.expectEqual(@as(usize, 0), away);
    try std.testing.expect(toward > 0);
}

test "a knight in the front row blocks spits from the front and not from behind" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    _ = r.spits.push(.{ .at = mathx.add(r.party, .{ 0.3, -6 }), .vel = .{ 0, SPIT_SPEED }, .dmg = 10, .life = SPIT_LIFE, .big = false });
    _ = r.spits.push(.{ .at = mathx.add(r.party, .{ 0.2, 6 }), .vel = .{ 0, -SPIT_SPEED }, .dmg = 10, .life = SPIT_LIFE, .big = false });
    var blocks: usize = 0;
    var hurts: usize = 0;
    for (0..120) |_| {
        r.step(.{ 0, 0 });
        for (r.drainEvents()) |e| {
            blocks += @intFromBool(e.kind == .block);
            hurts += @intFromBool(e.kind == .hurt);
        }
    }
    std.debug.print("two spits, facing n with the knight in front: {d} blocked, {d} landed\n", .{ blocks, hurts });
    try std.testing.expectEqual(@as(usize, 1), blocks);
    try std.testing.expectEqual(@as(usize, 1), hurts);
    _ = r.moveTo(r.memberAt(1).?.id, 0);
    r.facing = .s;
    _ = r.spits.push(.{ .at = mathx.add(r.party, .{ 0, 6 }), .vel = .{ 0, -SPIT_SPEED }, .dmg = 10, .life = SPIT_LIFE, .big = false });
    blocks = 0;
    for (0..120) |_| {
        r.step(.{ 0, 0 });
        for (r.drainEvents()) |e| blocks += @intFromBool(e.kind == .block);
    }
    try std.testing.expectEqual(@as(usize, 0), blocks);
}

test "an orb goes to the nearest hero" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    _ = r.orbs.push(.{ .at = mathx.add(r.party, .{ -2.6, 0.1 }), .xp = 3 });
    hold(r, .{ 0, 0 }, 90);
    const pyro = r.memberAt(3).?;
    std.debug.print("orb of 3 west of the party: pyromancer xp {d:.2}, knight {d:.2}, archer {d:.2}\n", .{ pyro.hero.xp, r.memberAt(1).?.hero.xp, r.memberAt(7).?.hero.xp });
    try std.testing.expectApproxEqAbs(3 * (1 - XP_SHARE), pyro.hero.xp, 1e-5);
    try std.testing.expectApproxEqAbs(3 * XP_SHARE / 3, r.memberAt(1).?.hero.xp, 1e-5);
    try std.testing.expectEqual(@as(usize, 0), r.orbs.n);
}

test "sanctuary heals within one slot of the cleric" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    _ = r.moveTo(r.memberAt(4).?.id, 0);
    for (r.members.slice()) |*m| m.hp = 1;
    const c = r.memberAt(0).?;
    c.cd = 0;
    hold(r, .{ 0, 0 }, 1);
    const knight = r.memberAt(1).?;
    const archer = r.memberAt(7).?;
    std.debug.print("a pulse from the corner: knight beside {d:.0} hp, archer two away {d:.0} hp\n", .{ knight.hp, archer.hp });
    try std.testing.expect(knight.hp > 1);
    try std.testing.expectEqual(@as(f32, 1), archer.hp);
}

test "a recruit of a held class merges, and moving onto another class swaps" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    try std.testing.expectEqual(Run.Place.merge, r.recruit(.archer, 7));
    try std.testing.expectEqual(@as(u8, 2), r.memberAt(7).?.hero.rank);
    try std.testing.expectEqual(Run.Place.refused, r.recruit(.archer, 1));
    const k = r.memberAt(1).?.id;
    try std.testing.expectEqual(Run.Place.swap, r.moveTo(k, 7));
    try std.testing.expectEqual(hero.Class.knight, r.memberAt(7).?.hero.class);
    try std.testing.expectEqual(hero.Class.archer, r.memberAt(1).?.hero.class);
    try std.testing.expectEqual(@as(usize, 4), r.members.n);
}

test "the lich waits for a free foe slot rather than never coming" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    while (!r.foes.full()) _ = r.spawnAt(.ghoul, mathx.add(r.party, .{ 12, 0 }));
    r.boss_due = true;
    r.t = director.BOSS_AT;
    r.spawn();
    const blocked = r.boss() != null;
    r.foes.n -= 1;
    r.spawn();
    std.debug.print("lich due with every foe slot taken: came {any}; one slot later: came {any}\n", .{ blocked, r.boss() != null });
    try std.testing.expect(!blocked and r.boss().?.final);
}

test "a ghoul pressed against the lich is pushed out of it" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    _ = r.spawnAt(.ghoul, mathx.add(r.party, .{ 10.95, 0.5 }));
    _ = r.spawnAt(.boss, mathx.add(r.party, .{ 12.15, 0.5 }));
    r.bins.build(r.party, r.foes.constSlice());
    r.separate();
    const d = mathx.len(mathx.sub(r.foes.items[1].at, r.foes.items[0].at));
    std.debug.print("ghoul and lich 1.20 apart, touching at {d:.2}: {d:.2} after one separation\n", .{ foe.row(.ghoul).radius + foe.row(.boss).radius, d });
    try std.testing.expectApproxEqAbs(foe.row(.ghoul).radius + foe.row(.boss).radius, d, 1e-4);
}

test "a martyr's lifeline never heals the martyr" {
    const r = try testRun();
    defer std.testing.allocator.destroy(r);
    const c = r.memberAt(4).?;
    c.hero.branch = .martyr;
    c.hero.ups.set(.lifeline, 1);
    c.refresh();
    for (r.members.slice()) |*m| m.hp = m.stats.max_hp;
    c.hp = 1;
    c.cd = 0;
    for (r.members.slice()) |*o| {
        if (o.id != c.id) o.cd = 99;
    }
    hold(r, .{ 0, 0 }, 1);
    std.debug.print("a martyr at 1 hp pulses with Lifeline: {d:.2} hp after\n", .{r.memberAt(4).?.hp});
    try std.testing.expect(r.memberAt(4).?.hp < 1.01);
}
