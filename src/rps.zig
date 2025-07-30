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
    random, // plays randomly
    lastmove, // assumes opponent plays the same move as last time
};

pub const MAX_HISTORY: usize = 3;

pub const RPSPlayer = struct {
    history: [MAX_HISTORY]Round,
    ptr: usize,
    count: usize,
    rand: std.Random,

    // Creates a new RPSPlayer with an empty history
    pub fn new(rand: std.Random) RPSPlayer {
        return RPSPlayer{
            .history = undefined,
            .ptr = 0,
            .count = 0,
            .rand = rand,
        };
    }

    // Add a round to history
    pub fn add_round(self: *RPSPlayer, round: Round) void {
        self.history[self.ptr] = round;
        self.ptr = (self.ptr + 1) % MAX_HISTORY;
        if (self.count < MAX_HISTORY) {
            self.count += 1;
        }
    }

    // Extracts rounds in the order they were played
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

    // Gets the nth last round
    pub fn nth_last_round(self: *const RPSPlayer, n: usize) ?Round {
        if (n >= self.count) return null; // Out of bounds
        const idx = (self.ptr + MAX_HISTORY - 1 - n) % MAX_HISTORY;
        return self.history[idx];
    }

    // Plays one move
    pub fn play(self: *const RPSPlayer, comptime player_type: PlayerType) Move {
        return switch (player_type) {
            .random => self.rand.enumValue(Move),
            .lastmove => {
                if (self.count == 0) {
                    // No history, play random
                    return self.rand.enumValue(Move);
                }
                // Find the last round played
                const last_round = self.nth_last_round(0) orelse unreachable;
                // Play the move that beats their last move
                return move_that_counters(last_round.their_move);
            },
        };
    }
};

// Unit tests
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
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };
    const round3 = Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win };

    player.add_round(round1);
    player.add_round(round2);
    player.add_round(round3);

    try testing.expect(player.count == 3);
    try testing.expect(player.ptr == 0); // wrapped around
}

test "RPSPlayer add_round replaces oldest when buffer is full" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };
    const round3 = Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win };
    const round4 = Round{ .my_move = Move.rock, .their_move = Move.paper, .outcome = Outcome.loss };

    player.add_round(round1);
    player.add_round(round2);
    player.add_round(round3);
    player.add_round(round4); // Should replace round1

    try testing.expect(player.count == 3); // Still MAX_HISTORY
    try testing.expect(player.ptr == 1); // Next position after round4

    // Verify round1 was replaced by round4
    try testing.expect(player.history[0].outcome == Outcome.loss); // round4's outcome
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
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };
    const round3 = Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win };

    player.add_round(round1);
    player.add_round(round2);
    player.add_round(round3);

    var buffer: [MAX_HISTORY]Round = undefined;
    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == 3);
    try testing.expect(rounds[0].my_move == Move.rock); // round1
    try testing.expect(rounds[1].my_move == Move.paper); // round2
    try testing.expect(rounds[2].my_move == Move.scissors); // round3
}

test "RPSPlayer get_rounds_in_order handles buffer overflow correctly" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };
    const round3 = Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win };
    const round4 = Round{ .my_move = Move.rock, .their_move = Move.paper, .outcome = Outcome.loss };
    const round5 = Round{ .my_move = Move.paper, .their_move = Move.scissors, .outcome = Outcome.loss };

    player.add_round(round1);
    player.add_round(round2);
    player.add_round(round3);
    player.add_round(round4); // Replaces round1
    player.add_round(round5); // Replaces round2

    var buffer: [MAX_HISTORY]Round = undefined;
    const rounds = player.get_rounds_in_order(&buffer);

    try testing.expect(rounds.len == 3);
    // Should return rounds 3, 4, 5 in that order (oldest to newest)
    try testing.expect(rounds[0].my_move == Move.scissors); // round3
    try testing.expect(rounds[1].outcome == Outcome.loss); // round4
    try testing.expect(rounds[2].outcome == Outcome.loss); // round5
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
    try testing.expect(rounds[0].my_move == Move.rock); // round1
    try testing.expect(rounds[1].my_move == Move.paper); // round2
}

test "RPSPlayer nth_last_round returns correct round" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round1 = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    const round2 = Round{ .my_move = Move.paper, .their_move = Move.rock, .outcome = Outcome.win };
    const round3 = Round{ .my_move = Move.scissors, .their_move = Move.paper, .outcome = Outcome.win };
    player.add_round(round1);
    player.add_round(round2);
    player.add_round(round3);
    // Most recent is round3
    const last = player.nth_last_round(0) orelse unreachable;
    try testing.expect(last.my_move == Move.scissors);
    // Second most recent is round2
    const second_last = player.nth_last_round(1) orelse unreachable;
    try testing.expect(second_last.my_move == Move.paper);
    // Third most recent is round1
    const third_last = player.nth_last_round(2) orelse unreachable;
    try testing.expect(third_last.my_move == Move.rock);
    // Out of bounds returns null
    try testing.expect(player.nth_last_round(3) == null);
}

test "RPSPlayer play .lastmove plays counter to last their_move" {
    const rand = std.crypto.random;
    var player = RPSPlayer.new(rand);
    const round = Round{ .my_move = Move.rock, .their_move = Move.scissors, .outcome = Outcome.win };
    player.add_round(round);
    // The last their_move was scissors, so play should return move_that_counters(scissors) == rock
    const move = player.play(.lastmove);
    try testing.expect(move == Move.rock);

    // Add another round where their_move is paper
    player.add_round(Round{ .my_move = Move.paper, .their_move = Move.paper, .outcome = Outcome.tie });
    // Now last their_move is paper, so play should return move_that_counters(paper) == scissors
    const move2 = player.play(.lastmove);
    try testing.expect(move2 == Move.scissors);
}
