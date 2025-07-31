const std = @import("std");

pub const Move = enum(u2) { rock, paper, scissors };

pub inline fn move_that_counters(move: Move) Move {
    return switch (move) {
        .rock => .paper,
        .paper => .scissors,
        .scissors => .rock,
    };
}

pub inline fn move_that_loses_to(move: Move) Move {
    return switch (move) {
        .rock => .scissors,
        .paper => .rock,
        .scissors => .paper,
    };
}

pub const Outcome = enum { win, loss, tie };

pub fn other_outcome(outcome: Outcome) Outcome {
    return switch (outcome) {
        .win => .loss,
        .loss => .win,
        .tie => .tie,
    };
}

pub fn judge(my_move: Move, their_move: Move) Outcome {
    if (my_move == their_move) return .tie;
    if (move_that_loses_to(my_move) == their_move) return .win;
    return .loss;
}

pub const Round = struct {
    my_move: Move,
    their_move: Move,
    outcome: Outcome,
};

pub const PlayerType = enum {
    random,
    lastmove,
    alwaysrock,
    freq1move,
    prob_30_40_30,
};

pub const MAX_HISTORY: usize = 10;

/// Rock-Paper-Scissors player with move history and frequency tracking
pub const RPSPlayer = struct {
    history: [MAX_HISTORY]Round,
    ptr: usize,
    count: usize,
    my_frequency: [3]usize = [_]usize{ 0, 0, 0 },
    their_frequency: [3]usize = [_]usize{ 0, 0, 0 },
    rand: std.Random,

    /// Creates a new RPSPlayer with empty history
    pub fn new(rand: std.Random) RPSPlayer {
        return RPSPlayer{
            .history = undefined,
            .ptr = 0,
            .count = 0,
            .my_frequency = [_]usize{ 0, 0, 0 },
            .their_frequency = [_]usize{ 0, 0, 0 },
            .rand = rand,
        };
    }

    /// Adds a round to the player's history and updates frequency tracking
    pub fn add_round(self: *RPSPlayer, round: Round) void {
        self.history[self.ptr] = round;
        self.ptr = (self.ptr + 1) % MAX_HISTORY;
        if (self.count < MAX_HISTORY) {
            self.count += 1;
        }

        self.my_frequency[@intFromEnum(round.my_move)] += 1;
        self.their_frequency[@intFromEnum(round.their_move)] += 1;
    }

    /// Extracts rounds in the order they were played
    pub fn get_rounds_in_order(self: *const RPSPlayer, buffer: []Round) []Round {
        if (self.count == 0) return buffer[0..0];

        const start_idx: usize = if (self.count < MAX_HISTORY)
            0
        else
            self.ptr;

        var i: usize = 0;
        var idx = start_idx;
        while (i < self.count) : (i += 1) {
            buffer[i] = self.history[idx];
            idx = (idx + 1) % MAX_HISTORY;
        }

        return buffer[0..self.count];
    }

    /// Gets the nth last round (0 = most recent)
    pub fn nth_last_round(self: *const RPSPlayer, n: usize) ?Round {
        if (n >= self.count) return null;
        const idx = (self.ptr + MAX_HISTORY - 1 - n) % MAX_HISTORY;
        return self.history[idx];
    }

    /// Plays one move according to the specified strategy
    pub fn play(self: *const RPSPlayer, player_type: PlayerType) Move {
        return switch (player_type) {
            .random => self.rand.enumValue(Move),
            .lastmove => {
                if (self.count == 0) {
                    return self.rand.enumValue(Move);
                }
                const last_round = self.nth_last_round(0) orelse unreachable;
                return move_that_counters(last_round.their_move);
            },
            .alwaysrock => Move.rock,
            .freq1move => {
                const total: usize = self.their_frequency[0] + self.their_frequency[1] + self.their_frequency[2];
                if (total == 0) {
                    return self.rand.enumValue(Move);
                }
                const rand_real: f32 = self.rand.float(f32);
                const rock_proportion: f32 = @as(f32, @floatFromInt(self.their_frequency[0])) / @as(f32, @floatFromInt(total));
                const paper_proportion: f32 = @as(f32, @floatFromInt(self.their_frequency[1])) / @as(f32, @floatFromInt(total));

                if (rand_real < rock_proportion) {
                    return move_that_counters(Move.rock);
                } else if (rand_real < rock_proportion + paper_proportion) {
                    return move_that_counters(Move.paper);
                } else {
                    return move_that_counters(Move.scissors);
                }
            },
            .prob_30_40_30 => {
                const rand_real: f32 = self.rand.float(f32);
                if (rand_real < 0.3) {
                    return Move.rock;
                } else if (rand_real < 0.7) {
                    return Move.paper;
                } else {
                    return Move.scissors;
                }
            },
        };
    }
};

const testing = std.testing;

test "RPSPlayer new creates empty player" {
    const rand = std.crypto.random;
    const player = RPSPlayer.new(rand);
    try testing.expect(player.count == 0);
}

test "RPSPlayer add_round adds first round correctly" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round = Round{
        .my_move = Move.rock,
        .their_move = Move.scissors,
        .outcome = Outcome.win,
    };

    player.add_round(round);

    try testing.expect(player.count == 1);
    try testing.expect(player.ptr == 1);
    try testing.expect(player.history[0].my_move == Move.rock);
    try testing.expect(player.history[0].their_move == Move.scissors);
    try testing.expect(player.history[0].outcome == Outcome.win);
}

test "RPSPlayer add_round handles multiple rounds" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    var rounds: [MAX_HISTORY]Round = undefined;
    for (0..MAX_HISTORY) |i| {
        rounds[i] = Round{ .my_move = @enumFromInt(i % 3), .their_move = @enumFromInt((i + 1) % 3), .outcome = Outcome.win };
        player.add_round(rounds[i]);
    }

    try testing.expect(player.count == MAX_HISTORY);
    try testing.expect(player.ptr == 0);
}

test "RPSPlayer add_round replaces oldest when buffer is full" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    for (0..MAX_HISTORY) |i| {
        const round = Round{ .my_move = @enumFromInt(i % 3), .their_move = @enumFromInt((i + 1) % 3), .outcome = Outcome.win };
        player.add_round(round);
    }

    const replacement_round = Round{ .my_move = Move.rock, .their_move = Move.paper, .outcome = Outcome.loss };
    player.add_round(replacement_round);

    try testing.expect(player.count == MAX_HISTORY);
    try testing.expect(player.ptr == 1);

    try testing.expect(player.history[0].outcome == Outcome.loss);
}

test "RPSPlayer get_rounds_in_order returns empty for empty player" {
    const rand = std.crypto.random;
    const player = RPSPlayer.new(rand);
    var buffer: [MAX_HISTORY]Round = undefined;

    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == 0);
}

test "RPSPlayer get_rounds_in_order returns rounds in correct order" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    var expected_rounds: [MAX_HISTORY]Round = undefined;
    for (0..MAX_HISTORY) |i| {
        expected_rounds[i] = Round{ .my_move = @enumFromInt(i % 3), .their_move = @enumFromInt((i + 1) % 3), .outcome = Outcome.win };
        player.add_round(expected_rounds[i]);
    }

    var buffer: [MAX_HISTORY]Round = undefined;
    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == MAX_HISTORY);
    for (0..MAX_HISTORY) |i| {
        try testing.expect(rounds[i].my_move == expected_rounds[i].my_move);
        try testing.expect(rounds[i].their_move == expected_rounds[i].their_move);
    }
}

test "RPSPlayer get_rounds_in_order handles buffer overflow correctly" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    const total_rounds = MAX_HISTORY + 2;
    var all_rounds: [total_rounds]Round = undefined;

    for (0..total_rounds) |i| {
        all_rounds[i] = Round{ .my_move = @enumFromInt(i % 3), .their_move = @enumFromInt((i + 1) % 3), .outcome = if (i >= MAX_HISTORY) Outcome.loss else Outcome.win };
        player.add_round(all_rounds[i]);
    }

    var buffer: [MAX_HISTORY]Round = undefined;
    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == MAX_HISTORY);

    for (0..MAX_HISTORY) |i| {
        const expected_round_idx = total_rounds - MAX_HISTORY + i;
        try testing.expect(rounds[i].my_move == all_rounds[expected_round_idx].my_move);
        try testing.expect(rounds[i].outcome == all_rounds[expected_round_idx].outcome);
    }
}

test "RPSPlayer partial buffer get_rounds_in_order" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };

    player.add_round(round1);
    player.add_round(round2);

    var buffer: [MAX_HISTORY]Round = undefined;
    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == 2);
    try testing.expect(rounds[0].my_move == Move.rock);
    try testing.expect(rounds[1].my_move == Move.paper);
}

test "RPSPlayer nth_last_round returns correct round" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    var test_rounds: [MAX_HISTORY]Round = undefined;
    for (0..MAX_HISTORY) |i| {
        test_rounds[i] = Round{ .my_move = @enumFromInt(i % 3), .their_move = @enumFromInt((i + 1) % 3), .outcome = Outcome.win };
        player.add_round(test_rounds[i]);
    }

    for (0..MAX_HISTORY) |i| {
        const round = player.nth_last_round(i) orelse unreachable;
        const expected_idx = MAX_HISTORY - 1 - i;
        try testing.expect(round.my_move == test_rounds[expected_idx].my_move);
    }

    try testing.expect(player.nth_last_round(MAX_HISTORY) == null);
}

test "RPSPlayer play .lastmove plays counter to last their_move" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    player.add_round(round);
    const move = player.play(.lastmove);
    try testing.expect(move == Move.rock);

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.paper, .outcome = Outcome.tie });
    const move2 = player.play(.lastmove);
    try testing.expect(move2 == Move.scissors);
}

test "RPSPlayer play .alwaysrock always returns rock" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    const move1 = player.play(.alwaysrock);
    try testing.expect(move1 == Move.rock);

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.scissors, .outcome = Outcome.loss });
    player.add_round(Round{ .my_move = Move.scissors, .their_move = Move.rock, .outcome = Outcome.loss });
    player.add_round(Round{ .my_move = Move.rock, .their_move = Move.paper, .outcome = Outcome.loss });

    const move2 = player.play(.alwaysrock);
    try testing.expect(move2 == Move.rock);

    for (0..10) |_| {
        const move = player.play(.alwaysrock);
        try testing.expect(move == Move.rock);
    }
}

test "RPSPlayer play .freq1move with empty history returns random" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    const move = player.play(.freq1move);
    try testing.expect(move == Move.rock or move == Move.paper or move == Move.scissors);
}

test "RPSPlayer play .freq1move with single move type in history" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });

    try testing.expect(player.their_frequency[0] == 3);
    try testing.expect(player.their_frequency[1] == 0);
    try testing.expect(player.their_frequency[2] == 0);

    for (0..20) |_| {
        const move = player.play(.freq1move);
        try testing.expect(move == Move.paper);
    }
}

test "RPSPlayer play .freq1move with mixed move types in history" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });

    try testing.expect(player.their_frequency[0] == 2);
    try testing.expect(player.their_frequency[1] == 1);
    try testing.expect(player.their_frequency[2] == 1);

    var paper_count: u32 = 0;
    var scissors_count: u32 = 0;
    var rock_count: u32 = 0;

    const iterations = 1000;
    for (0..iterations) |_| {
        const move = player.play(.freq1move);
        switch (move) {
            .paper => paper_count += 1,
            .scissors => scissors_count += 1,
            .rock => rock_count += 1,
        }
    }

    const paper_ratio = @as(f32, @floatFromInt(paper_count)) / iterations;
    const scissors_ratio = @as(f32, @floatFromInt(scissors_count)) / iterations;
    const rock_ratio = @as(f32, @floatFromInt(rock_count)) / iterations;

    try testing.expect(paper_ratio > 0.40 and paper_ratio < 0.60);
    try testing.expect(scissors_ratio > 0.15 and scissors_ratio < 0.35);
    try testing.expect(rock_ratio > 0.15 and rock_ratio < 0.35);
}

test "RPSPlayer play .freq1move with equal frequencies" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win });

    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win });
    player.add_round(Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win });

    try testing.expect(player.their_frequency[0] == 2);
    try testing.expect(player.their_frequency[1] == 2);
    try testing.expect(player.their_frequency[2] == 2);

    var paper_count: u32 = 0;
    var scissors_count: u32 = 0;
    var rock_count: u32 = 0;

    const iterations = 1500;
    for (0..iterations) |_| {
        const move = player.play(.freq1move);
        switch (move) {
            .paper => paper_count += 1,
            .scissors => scissors_count += 1,
            .rock => rock_count += 1,
        }
    }

    const paper_ratio = @as(f32, @floatFromInt(paper_count)) / iterations;
    const scissors_ratio = @as(f32, @floatFromInt(scissors_count)) / iterations;
    const rock_ratio = @as(f32, @floatFromInt(rock_count)) / iterations;

    try testing.expect(paper_ratio > 0.25 and paper_ratio < 0.42);
    try testing.expect(scissors_ratio > 0.25 and scissors_ratio < 0.42);
    try testing.expect(rock_ratio > 0.25 and rock_ratio < 0.42);
}

test "RPSPlayer play .freq1move frequency tracking with history overflow" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    for (0..5) |_| {
        player.add_round(Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win });
    }

    for (0..3) |_| {
        player.add_round(Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win });
    }

    try testing.expect(player.their_frequency[0] == 5);
    try testing.expect(player.their_frequency[1] == 3);
    try testing.expect(player.their_frequency[2] == 0);
    try testing.expect(player.count == @min(8, MAX_HISTORY));

    var paper_count: u32 = 0;
    var scissors_count: u32 = 0;

    const iterations = 1000;
    for (0..iterations) |_| {
        const move = player.play(.freq1move);
        switch (move) {
            .paper => paper_count += 1,
            .scissors => scissors_count += 1,
            .rock => {},
        }
    }

    const paper_ratio = @as(f32, @floatFromInt(paper_count)) / iterations;
    const scissors_ratio = @as(f32, @floatFromInt(scissors_count)) / iterations;

    try testing.expect(paper_ratio > 0.55 and paper_ratio < 0.70);
    try testing.expect(scissors_ratio > 0.30 and scissors_ratio < 0.45);
}

test "RPSPlayer play .prob_30_40_30 returns expected move distribution" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);

    var rock_count: u32 = 0;
    var paper_count: u32 = 0;
    var scissors_count: u32 = 0;

    const iterations = 1000;
    for (0..iterations) |_| {
        const move = player.play(.prob_30_40_30);
        switch (move) {
            .rock => rock_count += 1,
            .paper => paper_count += 1,
            .scissors => scissors_count += 1,
        }
    }

    const rock_ratio = @as(f32, @floatFromInt(rock_count)) / iterations;
    const paper_ratio = @as(f32, @floatFromInt(paper_count)) / iterations;
    const scissors_ratio = @as(f32, @floatFromInt(scissors_count)) / iterations;

    try testing.expect(rock_ratio > 0.25 and rock_ratio < 0.35);
    try testing.expect(paper_ratio > 0.35 and paper_ratio < 0.45);
    try testing.expect(scissors_ratio > 0.25 and scissors_ratio < 0.35);
}
