const std = @import("std");
const mathx = @import("../core/mathx.zig");

// A HERO'S CLASS AND WHAT IT HAS BECOME: rank from merges, level, upgrades, branch. Where it stands and what it is
// doing in the field is `run.Member`'s.

pub const Class = enum { knight, archer, cleric, pyromancer, mystic, druid, bard, necromancer };
pub const CLASSES = std.enums.values(Class);

/// `n` different classes, drawn from all of them.
pub fn draft(comptime n: usize, rng: *mathx.Rng) [n]Class {
    var pool = CLASSES[0..CLASSES.len].*;
    var out: [n]Class = undefined;
    for (&out, 0..) |*c, i| {
        const j = i + rng.below(@intCast(pool.len - i));
        std.mem.swap(Class, &pool[i], &pool[j]);
        c.* = pool[i];
    }
    return out;
}

pub const Branch = enum { bulwark, vanguard, sniper, skirmisher, saint, martyr };

pub const Up = enum {
    blade,
    tower,
    cleave,
    echo,
    fortify,
    riposte,
    longsword,
    second_wind,
    executioner,
    fletching,
    quick_draw,
    split_arrow,
    longbow,
    keen_eye,
    hunters_mark,
    wide_volley,
    mending,
    vigor,
    smite,
    radiance,
    aegis,
    lifeline,
    consecrate,
    kindling,
    ember,
    fireball,
    twin_flame,
    immolate,
    quickening,
    stillness,
    expanse,
    shatter,
    long_tendrils,
    thicket,
    verdant,
    venom,
    enchanting_air,
    wide_song,
    crescendo,
    tempo,
    legion,
    bone_armor,
    grave_strength,
    deathly_precision,
    undying,
};

pub const PROMOTE_AT: u8 = 5;
pub const RANK_MAX: u8 = 4;
const RANK_DMG: f32 = 1.5;
const RANK_HP: f32 = 1.4;

/// Three of the eight sectors: the front row's arc.
pub const ARC: f32 = mathx.SECTOR * 1.5;
/// Five of the eight: the arc and both flanks.
pub const WIDE_ARC: f32 = mathx.SECTOR * 2.5;
/// A volley's half-field, and a swing's half-cone to start with and what each Cleave adds to it.
const VOLLEY_HALF: f32 = std.math.pi / 2.0;
const CLEAVE_HALF: f32 = std.math.pi / 6.0;
const CLEAVE_UP: f32 = std.math.pi / 12.0;
pub const ECHO_FALLOFF: f32 = 0.5;

const pct = std.fmt.comptimePrint;

pub const ClassRow = struct {
    name: [:0]const u8,
    rule: [:0]const u8,
    rule_desc: [:0]const u8,
    branches: ?[2]Branch,
    hp: f32,
    dmg: f32,
    cd: f32,
    range: f32,
    /// Chance a hit is critical.
    crit: f32,
};

pub fn class(c: Class) ClassRow {
    return switch (c) {
        .knight => .{
            .name = "Knight",
            .rule = "Shield Wall",
            .rule_desc = "In the front row, blocks every projectile from the front.",
            .branches = .{ .bulwark, .vanguard },
            .hp = 140,
            .dmg = 16,
            .cd = 0.85,
            .range = 1.9,
            .crit = 0.08,
        },
        .archer => .{
            .name = "Archer",
            .rule = "Volley",
            .rule_desc = "Fires at anything in the half of the field its slot faces; from the centre, all round.",
            .branches = .{ .sniper, .skirmisher },
            .hp = 70,
            .dmg = 10,
            .cd = 0.5,
            .range = 8,
            .crit = 0.12,
        },
        .cleric => .{
            .name = "Cleric",
            .rule = "Sanctuary",
            .rule_desc = "Heals itself and every adjacent hero.",
            .branches = .{ .saint, .martyr },
            .hp = 85,
            .dmg = 5,
            .cd = 2.6,
            .range = 1.8,
            .crit = 0.05,
        },
        .pyromancer => .{
            .name = "Pyromancer",
            .rule = "Firebolt",
            .rule_desc = "Hurls bursting fire at the nearest foe.",
            .branches = null,
            .hp = 70,
            .dmg = 10,
            .cd = 1.0,
            .range = 7,
            .crit = 0.06,
        },
        .mystic => .{
            .name = "Mystic",
            .rule = "Time Stop",
            .rule_desc = "Every so often, stops every foe within its reach.",
            .branches = null,
            .hp = 75,
            .dmg = 0,
            .cd = 9,
            .range = 3.5,
            .crit = 0,
        },
        .druid => .{
            .name = "Druid",
            .rule = "Vines",
            .rule_desc = "Plants vines that hold their ground and lash at foes in reach.",
            .branches = null,
            .hp = 80,
            .dmg = 8,
            .cd = 2.2,
            .range = 4.5,
            .crit = 0.05,
        },
        .bard => .{
            .name = "Bard",
            .rule = "Harp",
            .rule_desc = "Raises the damage of cardinally adjacent heroes; sows music that turns foes to the party's side.",
            .branches = null,
            .hp = 75,
            .dmg = 0,
            .cd = 8,
            .range = 5.5,
            .crit = 0,
        },
        .necromancer => .{
            .name = "Necromancer",
            .rule = "Grave Chill",
            .rule_desc = pct("Cardinally adjacent heroes are healed less; raises skeletons that fight on their own; while it lives, a fallen hero rises {d:.0}% of the time, at {d:.0}% max hp from then on.", .{ REVIVE * 100, REVIVED_HP * 100 }),
            .branches = null,
            .hp = 70,
            .dmg = 8,
            .cd = 4,
            .range = 0,
            .crit = 0,
        },
    };
}

/// What an upgrade does for its hero, for spotting what a class lacks.
pub const Tag = enum { damage, rate, reach, area, count, crit, survival, healing, control, status };

pub const UpRow = struct { class: Class, name: [:0]const u8, desc: [:0]const u8, max: u8, tag: Tag };

const BLADE: f32 = 0.25;
const TOWER_HP: f32 = 25;
const FORTIFY: f32 = 0.88;
const FLETCH: f32 = 0.25;
const QUICK: f32 = 0.93;
const LONGBOW: f32 = 1.5;
const MENDING: f32 = 0.15;
const VIGOR_HP: f32 = 20;
const SMITE: f32 = 7;
const RADIANCE: f32 = 0.85;
const KINDLING: f32 = 0.25;
const EMBER: f32 = 0.85;
const RIPOSTE: f32 = 8;
const LONGSWORD: f32 = 0.3;
const SECOND_WIND: f32 = 1.5;
const KEEN: f32 = 0.1;
/// What a critical hit multiplies, and what each Executioner adds to it.
pub const CRIT_MULT: f32 = 2;
const EXECUTIONER: f32 = 0.5;
const HUNTERS_MARK: f32 = 0.4;
const WIDE_VOLLEY: f32 = mathx.SECTOR * 0.25;
const AEGIS: f32 = 0.06;
pub const LIFELINE: f32 = 0.5;
const CONSECRATE: f32 = 0.6;
const FIREBALL: f32 = 0.35;
const IMMOLATE_DPS: f32 = 4;
pub const BURN_S: f32 = 3;
const STOP_S: f32 = 1.6;
const QUICKENING: f32 = 0.85;
const STILLNESS: f32 = 0.5;
const EXPANSE: f32 = 0.75;
const SHATTER: f32 = 0.25;
const VINES: u8 = 2;
pub const VINE_S: f32 = 10;
const VINE_REACH: f32 = 1.6;
const LONG_TENDRILS: f32 = 0.5;
const VERDANT: f32 = 0.15;
const VENOM_DPS: f32 = 3;
pub const POISON_S: f32 = 3;
const HARP: f32 = 0.15;
const CRESCENDO: f32 = 0.1;
const CLOUD_R: f32 = 1.6;
const WIDE_SONG: f32 = 0.4;
const CHARM_RATE: f32 = 0.35;
const ENCHANTING: f32 = 0.15;
const CHARM_S: f32 = 4.5;
const TEMPO: f32 = 0.85;
pub const CLOUD_S: f32 = 5;
/// Share of healing taken from every hero beside a necromancer.
pub const CURSE: f32 = 0.3;
const SKELETONS: u8 = 2;
const SKEL_HP: f32 = 80;
const BONE_ARMOR: f32 = 0.3;
const GRAVE_STRENGTH: f32 = 0.25;
const SKEL_CRIT: f32 = 0.05;
const DEATHLY: f32 = 0.08;
/// A fallen hero's chance to rise while a necromancer lives, what each Undying adds, and its max hp once risen.
const REVIVE: f32 = 0.25;
const UNDYING: f32 = 0.1;
pub const REVIVED_HP: f32 = 0.5;

pub fn up(u: Up) UpRow {
    return switch (u) {
        .blade => .{ .class = .knight, .name = "Whetted Blade", .desc = pct("+{d:.0}% damage", .{BLADE * 100}), .max = 5, .tag = .damage },
        .tower => .{ .class = .knight, .name = "Tower Shield", .desc = pct("+{d} max hp", .{TOWER_HP}), .max = 5, .tag = .survival },
        .cleave => .{ .class = .knight, .name = "Cleave", .desc = pct("Swings sweep {d:.0} degrees wider", .{CLEAVE_UP * 2 * 180 / std.math.pi}), .max = 4, .tag = .area },
        .echo => .{ .class = .knight, .name = "Echo", .desc = pct("Each swing strikes once more, at {d:.0}% of the strike before", .{ECHO_FALLOFF * 100}), .max = 3, .tag = .damage },
        .fortify => .{ .class = .knight, .name = "Fortify", .desc = pct("Takes {d:.0}% less damage", .{(1 - FORTIFY) * 100}), .max = 4, .tag = .survival },
        .fletching => .{ .class = .archer, .name = "Fletching", .desc = pct("+{d:.0}% damage", .{FLETCH * 100}), .max = 5, .tag = .damage },
        .quick_draw => .{ .class = .archer, .name = "Quick Draw", .desc = pct("Fires {d:.0}% faster", .{(1 - QUICK) * 100}), .max = 4, .tag = .rate },
        .split_arrow => .{ .class = .archer, .name = "Split Arrow", .desc = "One more arrow a volley", .max = 3, .tag = .area },
        .longbow => .{ .class = .archer, .name = "Longbow", .desc = pct("+{d} range, arrows pierce one more", .{LONGBOW}), .max = 3, .tag = .reach },
        .mending => .{ .class = .cleric, .name = "Mending", .desc = pct("+{d:.0}% healing", .{MENDING * 100}), .max = 5, .tag = .healing },
        .vigor => .{ .class = .cleric, .name = "Vigor", .desc = pct("+{d} max hp", .{VIGOR_HP}), .max = 5, .tag = .survival },
        .smite => .{ .class = .cleric, .name = "Smite", .desc = pct("Each pulse burns foes within {d} cells for {d}", .{ SMITE_REACH, SMITE }), .max = 4, .tag = .damage },
        .radiance => .{ .class = .cleric, .name = "Radiance", .desc = pct("Pulses {d:.0}% faster", .{(1 - RADIANCE) * 100}), .max = 4, .tag = .rate },
        .kindling => .{ .class = .pyromancer, .name = "Kindling", .desc = pct("+{d:.0}% firebolt damage", .{KINDLING * 100}), .max = 5, .tag = .damage },
        .ember => .{ .class = .pyromancer, .name = "Ember", .desc = pct("Casts {d:.0}% faster", .{(1 - EMBER) * 100}), .max = 4, .tag = .rate },
        .riposte => .{ .class = .knight, .name = "Riposte", .desc = pct("Strikes back for {d} at whatever bites it", .{RIPOSTE}), .max = 4, .tag = .damage },
        .longsword => .{ .class = .knight, .name = "Longsword", .desc = pct("Reaches {d} further", .{LONGSWORD}), .max = 3, .tag = .reach },
        .second_wind => .{ .class = .knight, .name = "Second Wind", .desc = pct("Regains {d} hp a second", .{SECOND_WIND}), .max = 3, .tag = .healing },
        .keen_eye => .{ .class = .archer, .name = "Keen Eye", .desc = pct("+{d:.0}% critical hit chance", .{KEEN * 100}), .max = 4, .tag = .crit },
        .executioner => .{ .class = .knight, .name = "Executioner", .desc = pct("+{d:.0}% critical hit damage", .{EXECUTIONER * 100}), .max = 4, .tag = .crit },
        .hunters_mark => .{ .class = .archer, .name = "Hunter's Mark", .desc = pct("+{d:.0}% damage to brutes and the lich", .{HUNTERS_MARK * 100}), .max = 3, .tag = .damage },
        .wide_volley => .{ .class = .archer, .name = "Wide Volley", .desc = "The half of the field it fires into widens", .max = 2, .tag = .reach },
        .aegis => .{ .class = .cleric, .name = "Aegis", .desc = pct("Heroes in its Sanctuary take {d:.0}% less damage", .{AEGIS * 100}), .max = 3, .tag = .survival },
        .lifeline => .{ .class = .cleric, .name = "Lifeline", .desc = pct("Each pulse also heals the most wounded hero anywhere, for {d:.0}% of its heal", .{LIFELINE * 100}), .max = 1, .tag = .healing },
        .consecrate => .{ .class = .cleric, .name = "Consecrate", .desc = pct("Smite reaches {d} further", .{CONSECRATE}), .max = 3, .tag = .reach },
        .fireball => .{ .class = .pyromancer, .name = "Fireball", .desc = pct("Firebolts burst {d} wider", .{FIREBALL}), .max = 3, .tag = .area },
        .twin_flame => .{ .class = .pyromancer, .name = "Twin Flame", .desc = "One more firebolt a cast", .max = 2, .tag = .area },
        .immolate => .{ .class = .pyromancer, .name = "Immolate", .desc = pct("Firebolts set foes burning, {d} a second for {d}s", .{ IMMOLATE_DPS, BURN_S }), .max = 4, .tag = .status },
        .quickening => .{ .class = .mystic, .name = "Quickening", .desc = pct("Stops time {d:.0}% more often", .{(1 - QUICKENING) * 100}), .max = 4, .tag = .rate },
        .stillness => .{ .class = .mystic, .name = "Stillness", .desc = pct("Time stays stopped {d}s longer", .{STILLNESS}), .max = 4, .tag = .control },
        .expanse => .{ .class = .mystic, .name = "Expanse", .desc = pct("Time Stop reaches {d} further", .{EXPANSE}), .max = 4, .tag = .reach },
        .shatter => .{ .class = .mystic, .name = "Shatter", .desc = pct("The party deals {d:.0}% more damage to stopped foes", .{SHATTER * 100}), .max = 4, .tag = .damage },
        .long_tendrils => .{ .class = .druid, .name = "Long Tendrils", .desc = pct("Vines lash {d} further", .{LONG_TENDRILS}), .max = 4, .tag = .reach },
        .thicket => .{ .class = .druid, .name = "Thicket", .desc = "One more vine at a time", .max = 3, .tag = .count },
        .verdant => .{ .class = .druid, .name = "Verdant", .desc = pct("+{d:.0}% to all healing the party receives", .{VERDANT * 100}), .max = 4, .tag = .healing },
        .venom => .{ .class = .druid, .name = "Venom", .desc = pct("Lashes poison foes, {d} a second for {d}s", .{ VENOM_DPS, POISON_S }), .max = 4, .tag = .status },
        .enchanting_air => .{ .class = .bard, .name = "Enchanting Air", .desc = pct("Foes in its music are turned {d:.0}% more often", .{ENCHANTING / CHARM_RATE * 100}), .max = 4, .tag = .control },
        .wide_song => .{ .class = .bard, .name = "Wide Song", .desc = pct("Its music spreads {d} further", .{WIDE_SONG}), .max = 4, .tag = .reach },
        .crescendo => .{ .class = .bard, .name = "Crescendo", .desc = pct("+{d:.0}% damage to cardinally adjacent heroes", .{CRESCENDO * 100}), .max = 4, .tag = .damage },
        .tempo => .{ .class = .bard, .name = "Tempo", .desc = pct("Plays {d:.0}% more often", .{(1 - TEMPO) * 100}), .max = 4, .tag = .rate },
        .legion => .{ .class = .necromancer, .name = "Legion", .desc = "One more skeleton at a time", .max = 3, .tag = .count },
        .bone_armor => .{ .class = .necromancer, .name = "Bone Armor", .desc = pct("+{d:.0}% skeleton hp", .{BONE_ARMOR * 100}), .max = 4, .tag = .survival },
        .grave_strength => .{ .class = .necromancer, .name = "Grave Strength", .desc = pct("+{d:.0}% skeleton damage", .{GRAVE_STRENGTH * 100}), .max = 4, .tag = .damage },
        .deathly_precision => .{ .class = .necromancer, .name = "Deathly Precision", .desc = pct("+{d:.0}% skeleton critical chance", .{DEATHLY * 100}), .max = 4, .tag = .crit },
        .undying => .{ .class = .necromancer, .name = "Undying", .desc = pct("+{d:.0}% chance a fallen hero rises", .{UNDYING * 100}), .max = 4, .tag = .survival },
    };
}

pub const BranchRow = struct { class: Class, name: [:0]const u8, desc: [:0]const u8 };

const BULWARK_HP: f32 = 1.5;
const BULWARK_ARMOR: f32 = 0.7;
const VANGUARD_DMG: f32 = 1.7;
const VANGUARD_REACH: f32 = 0.6;
const VANGUARD_KNOCK: f32 = 1.0;
const SNIPER_DMG: f32 = 2.6;
const SNIPER_CD: f32 = 1.7;
const SNIPER_RANGE: f32 = 1.4;
const SNIPER_PIERCE: u8 = 6;
pub const PIERCE_MAX: u8 = up(.longbow).max + SNIPER_PIERCE;
const SNIPER_SPEED: f32 = 1.5;
const SKIRMISH_CD: f32 = 0.8;
const SAINT_HEAL: f32 = 1.3;
const MARTYR_HEAL: f32 = 1.6;
const MARTYR_SMITE: f32 = 14;
const MARTYR_REACH: f32 = 2.4;
const SMITE_REACH: f32 = 1.8;

pub fn branch(b: Branch) BranchRow {
    return switch (b) {
        .bulwark => .{ .class = .knight, .name = "Bulwark", .desc = pct("Shield Wall covers the flanks too. x{d} hp, takes {d:.0}% less", .{ BULWARK_HP, (1 - BULWARK_ARMOR) * 100 }) },
        .vanguard => .{ .class = .knight, .name = "Vanguard", .desc = pct("x{d} damage, longer reach, swings knock foes back", .{VANGUARD_DMG}) },
        .sniper => .{ .class = .archer, .name = "Sniper", .desc = pct("x{d} damage, longer range, arrows pierce, slower", .{SNIPER_DMG}) },
        .skirmisher => .{ .class = .archer, .name = "Skirmisher", .desc = "Fires into the flanks too, faster, one more arrow" },
        .saint => .{ .class = .cleric, .name = "Saint", .desc = pct("Sanctuary reaches the whole formation, x{d} healing", .{SAINT_HEAL}) },
        .martyr => .{ .class = .cleric, .name = "Martyr", .desc = pct("x{d} healing to others, none to itself; pulses burn nearby foes", .{MARTYR_HEAL}) },
    };
}

pub const Stats = struct {
    max_hp: f32,
    dmg: f32,
    cd: f32,
    range: f32,
    /// Arrows a volley, firebolts a cast.
    shots: u8 = 1,
    pierce: u8 = 0,
    taken: f32 = 1,
    knock: f32 = 0,
    shot_speed: f32 = 0,
    /// Archer: half the field it fires into, about its slot's outward heading. Knight: half the front arc it blocks.
    arc: f32 = ARC,
    /// Knight: half the cone a swing sweeps, and the strikes that follow it.
    cleave: f32 = 0,
    echoes: u8 = 0,
    heal: f32 = 0,
    /// Slots, Chebyshev.
    aura: i32 = 0,
    self_heal: bool = true,
    smite: f32 = 0,
    smite_reach: f32 = SMITE_REACH,
    splash: f32 = 0,
    thorns: f32 = 0,
    regen: f32 = 0,
    crit: f32 = 0,
    crit_mult: f32 = CRIT_MULT,
    /// Damage multiple against brutes and the lich.
    big: f32 = 1,
    /// Share of damage taken it removes from every hero in its Sanctuary.
    aegis: f32 = 0,
    lifeline: bool = false,
    burn_dps: f32 = 0,
    /// Seconds a Time Stop holds, and the damage multiple the party deals into it.
    stop_s: f32 = 0,
    shatter: f32 = 1,
    vines: u8 = 0,
    vine_reach: f32 = 0,
    /// Share added to every heal the party receives.
    verdant: f32 = 0,
    poison_dps: f32 = 0,
    /// Bard: what its harp adds to the damage of each hero beside it, and its music.
    harp: f32 = 0,
    cloud_r: f32 = 0,
    charm_rate: f32 = 0,
    charm_s: f32 = 0,
    /// Necromancer: its skeletons.
    skel_max: u8 = 0,
    skel_hp: f32 = 0,
    skel_dmg: f32 = 0,
    skel_crit: f32 = 0,
    /// Chance a fallen hero rises while it lives.
    revive: f32 = 0,
};

const ARROW_SPEED: f32 = 13;
const BOLT_SPEED: f32 = 9;
const BOLT_SPLASH: f32 = 0.9;
const HEAL: f32 = 2;

pub const Hero = struct {
    class: Class,
    rank: u8 = 1,
    level: u8 = 1,
    xp: f32 = 0,
    ups: std.EnumArray(Up, u8) = .initFill(0),
    branch: ?Branch = null,

    pub fn of(c: Class) Hero {
        return .{ .class = c };
    }

    pub fn n(h: Hero, u: Up) f32 {
        return @floatFromInt(h.ups.get(u));
    }

    /// Its branch's name once promoted, its class's before.
    pub fn name(h: Hero) [:0]const u8 {
        return if (h.branch) |b| branch(b).name else class(h.class).name;
    }

    pub fn is(h: Hero, b: Branch) bool {
        return h.branch == b;
    }

    pub fn stats(h: Hero) Stats {
        const row = class(h.class);
        const r: f32 = @floatFromInt(h.rank - 1);
        const dk = std.math.pow(f32, RANK_DMG, r);
        const hk = std.math.pow(f32, RANK_HP, r);
        var s = Stats{ .max_hp = row.hp * hk, .dmg = row.dmg * dk, .cd = row.cd, .range = row.range, .crit = row.crit };
        switch (h.class) {
            .knight => {
                s.dmg *= 1 + BLADE * h.n(.blade);
                s.max_hp += TOWER_HP * h.n(.tower) * hk;
                s.cleave = CLEAVE_HALF + CLEAVE_UP * h.n(.cleave);
                s.echoes = h.ups.get(.echo);
                s.taken = std.math.pow(f32, FORTIFY, h.n(.fortify));
                s.thorns = RIPOSTE * h.n(.riposte) * dk;
                s.range += LONGSWORD * h.n(.longsword);
                s.regen = SECOND_WIND * h.n(.second_wind) * hk;
                s.crit_mult += EXECUTIONER * h.n(.executioner);
                if (h.is(.bulwark)) {
                    s.max_hp *= BULWARK_HP;
                    s.taken *= BULWARK_ARMOR;
                    s.arc = WIDE_ARC;
                }
                if (h.is(.vanguard)) {
                    s.dmg *= VANGUARD_DMG;
                    s.range += VANGUARD_REACH;
                    s.knock = VANGUARD_KNOCK;
                }
            },
            .archer => {
                s.dmg *= 1 + FLETCH * h.n(.fletching);
                s.cd *= std.math.pow(f32, QUICK, h.n(.quick_draw));
                s.shots += h.ups.get(.split_arrow);
                s.range += LONGBOW * h.n(.longbow);
                s.pierce = h.ups.get(.longbow);
                s.shot_speed = ARROW_SPEED;
                s.arc = VOLLEY_HALF;
                s.crit += KEEN * h.n(.keen_eye);
                s.big = 1 + HUNTERS_MARK * h.n(.hunters_mark);
                s.arc += WIDE_VOLLEY * h.n(.wide_volley);
                if (h.is(.sniper)) {
                    s.dmg *= SNIPER_DMG;
                    s.cd *= SNIPER_CD;
                    s.range *= SNIPER_RANGE;
                    s.pierce += SNIPER_PIERCE;
                    s.shot_speed *= SNIPER_SPEED;
                }
                if (h.is(.skirmisher)) {
                    s.arc = @max(s.arc, WIDE_ARC);
                    s.cd *= SKIRMISH_CD;
                    s.shots += 1;
                }
            },
            .cleric => {
                s.heal = HEAL * dk * (1 + MENDING * h.n(.mending));
                s.max_hp += VIGOR_HP * h.n(.vigor) * hk;
                s.smite = SMITE * h.n(.smite) * dk;
                s.cd *= std.math.pow(f32, RADIANCE, h.n(.radiance));
                s.aura = 1;
                s.aegis = AEGIS * h.n(.aegis);
                s.lifeline = h.ups.get(.lifeline) > 0;
                s.smite_reach += CONSECRATE * h.n(.consecrate);
                if (h.is(.saint)) {
                    s.aura = 2;
                    s.heal *= SAINT_HEAL;
                }
                if (h.is(.martyr)) {
                    s.heal *= MARTYR_HEAL;
                    s.self_heal = false;
                    s.smite += MARTYR_SMITE * dk;
                    s.smite_reach += MARTYR_REACH - SMITE_REACH;
                }
            },
            .pyromancer => {
                s.dmg *= 1 + KINDLING * h.n(.kindling);
                s.cd *= std.math.pow(f32, EMBER, h.n(.ember));
                s.shot_speed = BOLT_SPEED;
                s.splash = BOLT_SPLASH + FIREBALL * h.n(.fireball);
                s.shots += h.ups.get(.twin_flame);
                s.burn_dps = IMMOLATE_DPS * h.n(.immolate) * dk;
            },
            .mystic => {
                s.cd *= std.math.pow(f32, QUICKENING, h.n(.quickening));
                s.stop_s = STOP_S + STILLNESS * h.n(.stillness);
                s.range += EXPANSE * h.n(.expanse);
                s.shatter = 1 + SHATTER * h.n(.shatter) * dk;
            },
            .druid => {
                s.vines = VINES + h.ups.get(.thicket);
                s.vine_reach = VINE_REACH + LONG_TENDRILS * h.n(.long_tendrils);
                s.verdant = VERDANT * h.n(.verdant);
                s.poison_dps = VENOM_DPS * h.n(.venom) * dk;
            },
            .bard => {
                s.harp = (HARP + CRESCENDO * h.n(.crescendo)) * dk;
                s.cloud_r = CLOUD_R + WIDE_SONG * h.n(.wide_song);
                s.charm_rate = CHARM_RATE + ENCHANTING * h.n(.enchanting_air);
                s.charm_s = CHARM_S;
                s.cd *= std.math.pow(f32, TEMPO, h.n(.tempo));
            },
            .necromancer => {
                s.skel_max = SKELETONS + h.ups.get(.legion);
                s.skel_hp = SKEL_HP * hk * (1 + BONE_ARMOR * h.n(.bone_armor));
                s.skel_dmg = s.dmg * (1 + GRAVE_STRENGTH * h.n(.grave_strength));
                s.skel_crit = SKEL_CRIT + DEATHLY * h.n(.deathly_precision);
                s.revive = REVIVE + UNDYING * h.n(.undying);
            },
        }
        return s;
    }

    /// Levels gained.
    pub fn gain(h: *Hero, xp: f32) u8 {
        h.xp += xp;
        var gained: u8 = 0;
        while (h.xp >= xpFor(h.level)) {
            h.xp -= xpFor(h.level);
            h.level += 1;
            gained += 1;
        }
        return gained;
    }

    pub fn promotable(h: Hero) bool {
        return h.branch == null and h.level >= PROMOTE_AT and class(h.class).branches != null;
    }

    /// Two of a class become one: ranks add, the better of each upgrade and level is kept.
    pub fn merged(a: Hero, b: Hero) Hero {
        std.debug.assert(a.class == b.class);
        var m = a;
        m.rank = @min(RANK_MAX, a.rank + b.rank);
        if (b.level > a.level or (b.level == a.level and b.xp > a.xp)) {
            m.level = b.level;
            m.xp = b.xp;
        }
        for (std.enums.values(Up)) |u| m.ups.set(u, @max(a.ups.get(u), b.ups.get(u)));
        m.branch = a.branch orelse b.branch;
        return m;
    }

    pub fn maxed(h: Hero, u: Up) bool {
        return h.ups.get(u) >= up(u).max;
    }
};

pub fn xpFor(level: u8) f32 {
    const l: f32 = @floatFromInt(level);
    return 8 + 6 * l + 0.6 * l * l;
}

const UPS = blk: {
    var a = std.EnumArray(Class, []const Up).initFill(&.{});
    for (std.enums.values(Up)) |u| a.set(up(u).class, a.get(up(u).class) ++ [_]Up{u});
    break :blk a;
};

pub fn ups(c: Class) []const Up {
    return UPS.get(c);
}

pub const Card = union(enum) {
    up: Up,
    branch: Branch,
    move,
    rest,

    pub fn name(c: Card) [:0]const u8 {
        return switch (c) {
            .up => |u| up(u).name,
            .branch => |b| branch(b).name,
            .move => "Move",
            .rest => "Rest",
        };
    }

    pub fn desc(c: Card) [:0]const u8 {
        return switch (c) {
            .up => |u| up(u).desc,
            .branch => |b| branch(b).desc,
            .move => "Take this hero to another slot: swap, or merge with its own class",
            .rest => "Heal to full",
        };
    }
};

pub const OFFER_MAX: usize = 4;
const POOL_MAX: usize = blk: {
    var n: usize = 0;
    for (CLASSES) |c| n = @max(n, ups(c).len);
    break :blk n;
};
pub const Offer = struct {
    cards: [OFFER_MAX]Card = undefined,
    n: usize = 0,

    fn put(o: *Offer, c: Card) void {
        o.cards[o.n] = c;
        o.n += 1;
    }

    pub fn slice(o: *const Offer) []const Card {
        return o.cards[0..o.n];
    }
};

/// A promotion is the two branches alone; otherwise upgrades not at their max, Move taking the last card.
pub fn offer(h: Hero, rng: *mathx.Rng) Offer {
    var o = Offer{};
    if (h.promotable()) {
        for (class(h.class).branches.?) |b| o.put(.{ .branch = b });
        return o;
    }
    var pool: [POOL_MAX]Up = undefined;
    var n: usize = 0;
    for (ups(h.class)) |u| {
        if (h.maxed(u)) continue;
        pool[n] = u;
        n += 1;
    }
    while (n > 0 and o.n < OFFER_MAX - 1) {
        const i = rng.below(@intCast(n));
        o.put(.{ .up = pool[i] });
        pool[i] = pool[n - 1];
        n -= 1;
    }
    if (o.n == 0) o.put(.rest);
    o.put(.move);
    return o;
}

test "every class has at least four upgrades, and its branches are its own" {
    var owned: usize = 0;
    for (CLASSES) |c| {
        try std.testing.expect(ups(c).len >= 4);
        owned += ups(c).len;
        if (class(c).branches) |bs| {
            for (bs) |b| try std.testing.expectEqual(c, branch(b).class);
        }
    }
    try std.testing.expectEqual(std.enums.values(Up).len, owned);
}

test "xp to reach each level" {
    var total: f32 = 0;
    std.debug.print("xp to reach level:", .{});
    for (1..12) |l| {
        total += xpFor(@intCast(l));
        if (l == PROMOTE_AT - 1 or l % 5 == 4) std.debug.print(" {d}:{d:.0}", .{ l + 1, total });
    }
    std.debug.print("\n", .{});
    try std.testing.expect(xpFor(2) > xpFor(1));
}

test "the fifth level offers the two branches and nothing else" {
    var rng = mathx.Rng.init(1);
    var h = Hero.of(.archer);
    var gained: u8 = 0;
    while (h.level < PROMOTE_AT) gained += h.gain(1);
    try std.testing.expectEqual(PROMOTE_AT - 1, gained);
    const o = offer(h, &rng);
    try std.testing.expectEqual(@as(usize, 2), o.n);
    try std.testing.expectEqual(Card{ .branch = .sniper }, o.cards[0]);
    h.branch = .sniper;
    const next = offer(h, &rng);
    try std.testing.expectEqual(@as(usize, 4), next.n);
    try std.testing.expectEqual(Card.move, next.cards[3]);
    var p = Hero.of(.pyromancer);
    p.level = PROMOTE_AT;
    try std.testing.expect(!p.promotable());
}

test "a merge is stronger than either copy" {
    var a = Hero.of(.knight);
    a.ups.set(.blade, 2);
    var b = Hero.of(.knight);
    b.level = 4;
    b.ups.set(.tower, 1);
    const m = Hero.merged(a, b);
    const sa = a.stats();
    const sm = m.stats();
    std.debug.print("knight dmg {d:.1} -> merged {d:.1}, hp {d:.0} -> {d:.0}, rank {d}, level {d}\n", .{ sa.dmg, sm.dmg, sa.max_hp, sm.max_hp, m.rank, m.level });
    try std.testing.expectEqual(@as(u8, 2), m.rank);
    try std.testing.expectEqual(@as(u8, 4), m.level);
    try std.testing.expect(sm.dmg > sa.dmg and sm.max_hp > b.stats().max_hp);
}
