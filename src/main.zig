const std = @import("std");
const rl = @import("raylib");

const WinSize: i32 = 480;
const GridCount: i32 = 10;
const CellSize: i32 = WinSize / GridCount;
const HalfCellSize: i32 = CellSize / 2;
const MaxPositions: usize = @intCast(GridCount * GridCount);

const colors = struct {
    const grass = rl.Color.init(194, 211, 104, 255);
    const darkGrass = rl.Color.init(138, 176, 96, 255);
    const red = rl.Color.init(180, 82, 82, 255);
    const caterpillarBody = rl.Color.init(86, 123, 121, 255);
    const brown = rl.Color.init(128, 73, 58, 255);
    const leaf = rl.Color.init(123, 114, 67, 255);
    const eye = rl.Color.init(242, 240, 229, 255);
    const black = rl.Color.init(33, 33, 35, 255);
    const overlay = rl.Color.init(33, 33, 35, 100);
    const yellow = rl.Color.init(237, 225, 158, 255);
};

const Direction = enum { up, down, right, left };
const State = enum { playing, paused, won, game_over };

const Vec2 = struct {
    x: i32,
    y: i32,
};

const Caterpillar = struct {
    positions: std.ArrayList(Vec2),
    direction: Direction,
};

const Game = struct {
    state: State,
    caterpillar: Caterpillar,
    apple: Vec2,
    score: u16,
    prng: std.Random.DefaultPrng,
    music: rl.Music,
    sound_eat: rl.Sound,
    sound_bite: rl.Sound,
    sound_gameover: rl.Sound,
    sound_win: rl.Sound,
    update_counter: u8,
    should_close: bool,
};

fn vec2Equals(a: Vec2, b: Vec2) bool {
    return a.x == b.x and a.y == b.y;
}

fn vec2Wrap(v: Vec2) Vec2 {
    var x = @rem(v.x, GridCount);
    var y = @rem(v.y, GridCount);
    if (x < 0) x += GridCount;
    if (y < 0) y += GridCount;
    return .{ .x = x, .y = y };
}

fn drawGrass() void {
    for (0..@intCast(GridCount)) |x| {
        for (0..@intCast(GridCount)) |y| {
            const color = if ((x + y) % 2 == 0) colors.grass else colors.darkGrass;
            rl.drawRectangle(@intCast(x * CellSize), @intCast(y * CellSize), CellSize, CellSize, color);
        }
    }
}

fn placeNewApple(game: *Game) void {
    var rand = game.prng.random();
    while (true) {
        const candidate = Vec2{
            .x = rand.intRangeAtMost(i32, 0, GridCount - 1),
            .y = rand.intRangeAtMost(i32, 0, GridCount - 1),
        };
        var occupied = false;
        for (game.caterpillar.positions.items) |seg| {
            if (vec2Equals(seg, candidate)) {
                occupied = true;
                break;
            }
        }
        if (!occupied) {
            game.apple = candidate;
            return;
        }
    }
}

fn loadSounds(game: *Game) void {
    game.music = rl.loadMusicStream("assets/sounds/background_music.wav") catch undefined;
    game.sound_eat = rl.loadSound("assets/sounds/eats_apple.wav") catch undefined;
    game.sound_bite = rl.loadSound("assets/sounds/self_bite.wav") catch undefined;
    game.sound_gameover = rl.loadSound("assets/sounds/game_over.wav") catch undefined;
    game.sound_win = rl.loadSound("assets/sounds/win.wav") catch undefined;
}

fn unloadSounds(game: *Game) void {
    rl.unloadMusicStream(game.music);
    rl.unloadSound(game.sound_eat);
    rl.unloadSound(game.sound_bite);
    rl.unloadSound(game.sound_gameover);
    rl.unloadSound(game.sound_win);
}

fn createCaterpillar() !Caterpillar {
    const positions = std.ArrayList(Vec2).initCapacity(std.heap.page_allocator, 3) catch unreachable;
    var cat = Caterpillar{
        .positions = positions,
        .direction = .right,
    };
    try cat.positions.append(std.heap.page_allocator, .{ .x = 3, .y = 5 });
    try cat.positions.append(std.heap.page_allocator, .{ .x = 4, .y = 5 });
    try cat.positions.append(std.heap.page_allocator, .{ .x = 5, .y = 5 }); // head
    return cat;
}

fn drawApple(pos: *const Vec2) void {
    const cx = pos.x * CellSize + HalfCellSize;
    const cy = pos.y * CellSize + HalfCellSize;
    const appleSize = HalfCellSize - 8;
    const leafSize = appleSize / 2;
    rl.drawEllipse(cx, cy + 5, appleSize, appleSize - 2, colors.red);
    rl.drawRectangle(cx - 3, cy - HalfCellSize + 10, 5, 10, colors.brown);
    rl.drawEllipse(cx + 3, cy - HalfCellSize + 8, leafSize, leafSize - 4, colors.leaf);
}

fn drawCaterpillar(cat: *const Caterpillar) void {
    const bodySize = HalfCellSize;
    for (cat.positions.items, 0..) |pos, i| {
        const cx: i32 = pos.x * CellSize + HalfCellSize;
        const cy: i32 = pos.y * CellSize + HalfCellSize;
        rl.drawEllipse(cx, cy, bodySize, bodySize - 2, colors.caterpillarBody);

        if (i == cat.positions.items.len - 1) { // head
            switch (cat.direction) {
                .right => {
                    rl.drawCircle(cx + 10, cy - 7, 6, colors.eye);
                    rl.drawCircle(cx + 10, cy + 7, 6, colors.eye);
                    rl.drawCircle(cx + 12, cy - 8, 2, colors.black);
                    rl.drawCircle(cx + 12, cy + 8, 2, colors.black);
                },
                .left => {
                    rl.drawCircle(cx - 10, cy - 7, 6, colors.eye);
                    rl.drawCircle(cx - 10, cy + 7, 6, colors.eye);
                    rl.drawCircle(cx - 12, cy - 8, 2, colors.black);
                    rl.drawCircle(cx - 12, cy + 8, 2, colors.black);
                },
                .up => {
                    rl.drawCircle(cx - 7, cy - 10, 6, colors.eye);
                    rl.drawCircle(cx + 7, cy - 10, 6, colors.eye);
                    rl.drawCircle(cx - 8, cy - 12, 2, colors.black);
                    rl.drawCircle(cx + 8, cy - 12, 2, colors.black);
                },
                .down => {
                    rl.drawCircle(cx - 7, cy + 10, 6, colors.eye);
                    rl.drawCircle(cx + 7, cy + 10, 6, colors.eye);
                    rl.drawCircle(cx - 8, cy + 12, 2, colors.black);
                    rl.drawCircle(cx + 8, cy + 12, 2, colors.black);
                },
            }
        }
    }
}

fn drawScore(score: u16) void {
    var buf: [32:0]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "Score: {}", .{score}) catch "Score: 0";
    const fontSize: i32 = 24;
    const textWidth = rl.measureText(text, fontSize);
    rl.drawText(text, WinSize - textWidth - 10, 10, fontSize, colors.yellow);
}

fn drawOverlay(game: *const Game) void {
    if (game.state == .playing) return;

    var buf: [32:0]u8 = undefined;
    const text_str = switch (game.state) {
        .paused => "Paused",
        .game_over => "Game Over",
        .won => "You Win!",
        .playing => unreachable,
    };
    const text = std.fmt.bufPrintZ(&buf, "{s}", .{text_str}) catch "";
    const fontSize: i32 = 48;
    const textWidth = rl.measureText(text, fontSize);
    const x = @divTrunc(WinSize, 2) - @divTrunc(textWidth, 2);
    const y = @divTrunc(WinSize, 2) - @divTrunc(fontSize, 2);
    rl.drawRectangle(0, 0, WinSize, WinSize, colors.overlay);
    rl.drawText(text, x, y, fontSize, colors.yellow);
}

fn restartGame(game: *Game) !void {
    game.caterpillar.positions.deinit(std.heap.page_allocator);
    game.caterpillar = try createCaterpillar();
    placeNewApple(game);

    game.score = 0;
    game.state = .playing;
}

fn gameUpdate(game: *Game) !void {
    if ((rl.isKeyPressed(.enter) or rl.isKeyPressed(.space)) and (game.state == .game_over or game.state == .won)) {
        try restartGame(game);
        return;
    }
    var cat = &game.caterpillar;

    if (rl.isKeyPressed(.escape)) {
        game.state = switch (game.state) {
            .playing => .paused,
            .paused => .playing,
            else => game.state,
        };
    }

    if (game.state == .playing) {
        rl.updateMusicStream(game.music);
    }
    if (game.state != .playing) return;

    var next_direction = cat.direction;
    if (rl.isKeyDown(.right) or rl.isKeyDown(.d) or rl.isKeyDown(.l)) {
        if (cat.direction != .left) next_direction = .right;
    } else if (rl.isKeyDown(.left) or rl.isKeyDown(.a) or rl.isKeyDown(.h)) {
        if (cat.direction != .right) next_direction = .left;
    } else if (rl.isKeyDown(.up) or rl.isKeyDown(.w) or rl.isKeyDown(.k)) {
        if (cat.direction != .down) next_direction = .up;
    } else if (rl.isKeyDown(.down) or rl.isKeyDown(.s) or rl.isKeyDown(.j)) {
        if (cat.direction != .up) next_direction = .down;
    }
    cat.direction = next_direction;

    game.update_counter += 1;
    if (game.update_counter < 3) return;
    game.update_counter = 0;

    var dx: i32 = 0;
    var dy: i32 = 0;
    switch (cat.direction) {
        .right => dx = 1,
        .left => dx = -1,
        .up => dy = -1,
        .down => dy = 1,
    }

    const current_head = cat.positions.items[cat.positions.items.len - 1];
    var new_head = current_head;
    new_head.x += dx;
    new_head.y += dy;
    new_head = vec2Wrap(new_head);

    const ate = vec2Equals(new_head, game.apple);
    if (ate) {
        game.score += 10;
        rl.playSound(game.sound_eat);
        placeNewApple(game);
    }

    if (!ate) {
        _ = cat.positions.orderedRemove(0);
    }
    cat.positions.append(std.heap.page_allocator, new_head) catch unreachable;

    const head_pos = cat.positions.items[cat.positions.items.len - 1];
    for (cat.positions.items[0 .. cat.positions.items.len - 1]) |seg| {
        if (vec2Equals(seg, head_pos)) {
            rl.playSound(game.sound_bite);
            game.state = .game_over;
            return;
        }
    }

    if (cat.positions.items.len >= MaxPositions) {
        rl.playSound(game.sound_win);
        game.state = .won;
    }
}

fn gameDraw(game: *const Game) void {
    rl.clearBackground(colors.grass);
    drawGrass();
    drawApple(&game.apple);
    drawCaterpillar(&game.caterpillar);
    drawScore(game.score);
    drawOverlay(game);
}

pub fn main() !void {
    rl.initWindow(WinSize, WinSize, "Caterpillar");
    defer rl.closeWindow();

    rl.setExitKey(.null);
    rl.setConfigFlags(.{ .window_resizable = false });
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch undefined;

    var game = Game{
        .state = .playing,
        .caterpillar = try createCaterpillar(),
        .apple = undefined,
        .score = 0,
        .prng = std.Random.DefaultPrng.init(seed),
        .music = undefined,
        .sound_eat = undefined,
        .sound_bite = undefined,
        .sound_gameover = undefined,
        .sound_win = undefined,
        .update_counter = 0,
        .should_close = false,
    };

    loadSounds(&game);
    defer unloadSounds(&game);

    placeNewApple(&game);

    rl.setTargetFPS(12);
    rl.playMusicStream(game.music);

    while (!rl.windowShouldClose()) {
        try gameUpdate(&game);

        rl.beginDrawing();
        defer rl.endDrawing();

        gameDraw(&game);
    }

    defer game.caterpillar.positions.deinit(std.heap.page_allocator);
}
