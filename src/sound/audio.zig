const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const run = @import("../play/run.zig");

// THE ONLY FILE THAT TOUCHES THE SPEAKERS. Every cue is `assets/sfx_<cue>.wav`, the music `assets/music.ogg`, both
// written by `tools/sound.py`. Nothing in the simulation reads any of it.

pub const Cue = enum { hit, kill, hurt, fall, loose, cast, blast, spit, block, heal, pulse, level, recruit, merge, swing, stop, sprout, lash, lob, boom, quake, strum, charm, raise, crumble, boss, defeat, victory, tick, confirm };
const CUES = std.enums.values(Cue);
const N = CUES.len;
/// Copies of a cue that can sound at once.
const VOICES: usize = 4;
pub const MUSIC_VOL: f32 = 0.42;
const SFX_VOL: f32 = 0.8;

const Row = struct {
    /// Seconds a cue waits before it may sound again, so a horde's hundred hits a second stay a patter.
    gap: f32,
    vol: f32,
    /// Share of pitch each play may wander either way.
    jitter: f32 = 0,
};

fn row(c: Cue) Row {
    return switch (c) {
        .hit => .{ .gap = 0.045, .vol = 0.5, .jitter = 0.12 },
        .kill => .{ .gap = 0.04, .vol = 0.55, .jitter = 0.15 },
        .hurt => .{ .gap = 0.09, .vol = 0.7, .jitter = 0.08 },
        .fall => .{ .gap = 0.2, .vol = 0.9 },
        .loose => .{ .gap = 0.06, .vol = 0.35, .jitter = 0.1 },
        .cast => .{ .gap = 0.08, .vol = 0.45, .jitter = 0.08 },
        .blast => .{ .gap = 0.06, .vol = 0.5, .jitter = 0.12 },
        .spit => .{ .gap = 0.1, .vol = 0.35, .jitter = 0.1 },
        .block => .{ .gap = 0.06, .vol = 0.55, .jitter = 0.06 },
        .heal => .{ .gap = 0.18, .vol = 0.35 },
        .pulse => .{ .gap = 0.3, .vol = 0.3 },
        .level => .{ .gap = 0.15, .vol = 0.6 },
        .recruit => .{ .gap = 0.3, .vol = 0.7 },
        .merge => .{ .gap = 0.3, .vol = 0.7 },
        .swing => .{ .gap = 0.07, .vol = 0.45, .jitter = 0.1 },
        .stop => .{ .gap = 0.3, .vol = 0.7 },
        .sprout => .{ .gap = 0.15, .vol = 0.5 },
        .lash => .{ .gap = 0.07, .vol = 0.4, .jitter = 0.1 },
        .lob => .{ .gap = 0.12, .vol = 0.35, .jitter = 0.1 },
        .boom => .{ .gap = 0.08, .vol = 0.5, .jitter = 0.1 },
        .quake => .{ .gap = 0.2, .vol = 0.8, .jitter = 0.05 },
        .strum => .{ .gap = 0.3, .vol = 0.55 },
        .charm => .{ .gap = 0.1, .vol = 0.4, .jitter = 0.08 },
        .raise => .{ .gap = 0.2, .vol = 0.5 },
        .crumble => .{ .gap = 0.1, .vol = 0.5, .jitter = 0.1 },
        .boss => .{ .gap = 1, .vol = 1 },
        .defeat => .{ .gap = 1, .vol = 0.8 },
        .victory => .{ .gap = 1, .vol = 0.8 },
        .tick => .{ .gap = 0.03, .vol = 0.4 },
        .confirm => .{ .gap = 0.05, .vol = 0.5 },
    };
}

pub fn cueOf(k: run.EventKind) ?Cue {
    return switch (k) {
        .hit => .hit,
        .kill => .kill,
        .hurt => .hurt,
        .fall => .fall,
        .loose => .loose,
        .cast => .cast,
        .blast => .blast,
        .spit => .spit,
        .block => .block,
        .heal => .heal,
        .pulse => .pulse,
        .level => .level,
        .recruit => .recruit,
        .merge => .merge,
        .swing => .swing,
        .stop => .stop,
        .sprout => .sprout,
        .lash => .lash,
        .lob => .lob,
        .boom => .boom,
        .strum => .strum,
        .charm => .charm,
        .raise => .raise,
        .crumble => .crumble,
        .boss => .boss,
        .smite, .burn, .poison, .lifeline, .wave => null,
    };
}

const WAVS = blk: {
    var w: [N][]const u8 = undefined;
    for (CUES, 0..) |c, i| w[i] = @embedFile("sfx_" ++ @tagName(c) ++ ".wav");
    break :blk w;
};

/// Silent until `load` finds a device.
pub const Audio = struct {
    sounds: [N][VOICES]?rl.Sound = @splat(@splat(null)),
    next: [N]usize = @splat(0),
    last: [N]f32 = @splat(-1),
    t: f32 = 0,
    music: ?rl.Music = null,
    rng: mathx.Rng = mathx.Rng.init(0xA0D10),
    /// The player's, 0 to 1.
    music_vol: f32 = 1,
    sfx_vol: f32 = 1,

    pub fn load() Audio {
        rl.initAudioDevice();
        var a = Audio{};
        if (!rl.isAudioDeviceReady()) return a;
        for (CUES, 0..) |_, i| {
            const w = rl.loadWaveFromMemory(".wav", WAVS[i]) catch continue;
            defer rl.unloadWave(w);
            const s = rl.loadSoundFromWave(w);
            a.sounds[i][0] = s;
            for (1..VOICES) |v| a.sounds[i][v] = rl.loadSoundAlias(s);
        }
        if (rl.loadMusicStreamFromMemory(".ogg", @embedFile("music.ogg"))) |m| {
            rl.setMusicVolume(m, MUSIC_VOL);
            rl.playMusicStream(m);
            a.music = m;
        } else |_| {}
        return a;
    }

    pub fn unload(a: *Audio) void {
        if (!rl.isAudioDeviceReady()) return;
        for (&a.sounds) |*voices| {
            for (voices[1..]) |v| {
                if (v) |s| rl.unloadSoundAlias(s);
            }
            if (voices[0]) |s| rl.unloadSound(s);
        }
        if (a.music) |m| rl.unloadMusicStream(m);
        a.* = .{};
        rl.closeAudioDevice();
    }

    pub fn setMusic(a: *Audio, v: f32) void {
        a.music_vol = std.math.clamp(v, 0, 1);
        if (a.music) |m| rl.setMusicVolume(m, MUSIC_VOL * a.music_vol);
    }

    pub fn setSfx(a: *Audio, v: f32) void {
        a.sfx_vol = std.math.clamp(v, 0, 1);
    }

    pub fn mute(_: *Audio, on: bool) void {
        if (rl.isAudioDeviceReady()) rl.setMasterVolume(if (on) 0 else 1);
    }

    pub fn update(a: *Audio, dt: f32) void {
        a.t += dt;
        if (a.music) |m| rl.updateMusicStream(m);
    }

    pub fn play(a: *Audio, c: Cue) void {
        const i = @intFromEnum(c);
        const r = row(c);
        const s = a.sounds[i][a.next[i]] orelse return;
        if (!a.due(i, r.gap)) return;
        a.next[i] = (a.next[i] + 1) % VOICES;
        rl.setSoundVolume(s, r.vol * SFX_VOL * a.sfx_vol);
        rl.setSoundPitch(s, 1 + (a.rng.unit() * 2 - 1) * r.jitter);
        rl.playSound(s);
    }

    fn due(a: *Audio, i: usize, gap: f32) bool {
        if (a.last[i] >= 0 and a.t - a.last[i] < gap) return false;
        a.last[i] = a.t;
        return true;
    }

    pub fn take(a: *Audio, e: run.Event) void {
        if (e.kind == .boom and e.big) return a.play(.quake);
        a.play(cueOf(e.kind) orelse return);
    }
};

test "a cue waits out its gap however often it is asked for" {
    var a = Audio{};
    var heard: usize = 0;
    const dt: f32 = 1.0 / 240.0;
    for (0..240) |_| {
        a.t += dt;
        heard += @intFromBool(a.due(@intFromEnum(Cue.hit), row(.hit).gap));
    }
    std.debug.print("hits asked for every frame for a second: {d} heard\n", .{heard});
    try std.testing.expect(heard <= @as(usize, @intFromFloat(1 / row(.hit).gap)) + 1);
}
