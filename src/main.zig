const std = @import("std");

const lib = @import("rps_lib");

fn match_vs_human(comptime ai_type: lib.rps.PlayerType) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // const rand = std.crypto.random;
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));

    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var player = lib.rps.RPSPlayer.new(rand);

    var rounds: usize = 0;
    var human_wins: usize = 0;
    var ai_wins: usize = 0;
    outer: while (true) {
        try stdout.print("Round {d}! Q to quit, or play R/P/S.\n", .{rounds + 1});

        // Get the AI's move
        const ai_move = player.play(ai_type);

        // Get the player's move from stdin
        var player_move: lib.rps.Move = undefined;
        inner: while (true) {
            const bare_line = try stdin.readUntilDelimiterAlloc(
                std.heap.page_allocator,
                '\n',
                8192,
            );
            defer std.heap.page_allocator.free(bare_line);
            const line = std.mem.trim(u8, bare_line, "\r");
            if (line.len != 1) {
                try stdout.print("Invalid input. Please enter Q, R, P, or S.\n", .{});
                continue;
            }
            switch (line[0]) {
                'Q' | 'q' => break :outer,
                'R' | 'r' => {
                    player_move = .rock;
                    try stdout.print("You played Rock.\n", .{});
                    break :inner;
                },
                'P' | 'p' => {
                    player_move = .paper;
                    try stdout.print("You played Paper.\n", .{});
                    break :inner;
                },
                'S' | 's' => {
                    player_move = .scissors;
                    try stdout.print("You played Scissors.\n", .{});
                    break :inner;
                },
                else => {
                    try stdout.print("Invalid input. Please enter Q, R, P, or S.\n", .{});
                    continue;
                },
            }
        }

        // Print AI Move
        const ai_move_string = switch (ai_move) {
            .rock => "Rock",
            .paper => "Paper",
            .scissors => "Scissors",
        };
        try stdout.print("AI played {s}.\n", .{ai_move_string});

        // Judge the outcome
        const outcome = lib.rps.judge(player_move, ai_move);
        const outcome_string = switch (outcome) {
            .win => "You win!",
            .loss => "You lose!",
            .tie => "It's a tie!",
        };
        try stdout.print("{s}\n", .{outcome_string});

        // Add this round
        const round = lib.rps.Round{
            .my_move = ai_move,
            .their_move = player_move,
            .outcome = lib.rps.other_outcome(outcome),
        };
        player.add_round(round);
        rounds += 1;
        if (outcome == .win) {
            human_wins += 1;
        } else if (outcome == .loss) {
            ai_wins += 1;
        }
    }

    try stdout.print("Game over! You won {d}/{d} rounds.\n", .{ human_wins, rounds });
    const w: f32 = @floatFromInt(human_wins);
    const aw: f32 = @floatFromInt(ai_wins);
    const t: f32 = @floatFromInt(rounds);
    try stdout.print("Your win %: {d:.2}\n", .{w / t * 100});
    try stdout.print("AI win %: {d:.2}\n", .{aw / t * 100});
    try stdout.print("Tie %: {d:.2}\n", .{(t - w - aw) / t * 100});
}

pub fn main() !void {
    const ai_type = lib.rps.PlayerType.lastmove;
    try match_vs_human(ai_type);
    return;
}
