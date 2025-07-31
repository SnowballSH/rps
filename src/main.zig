const std = @import("std");

const lib = @import("rps_lib");

/// Interactive human vs AI rock-paper-scissors match
fn match_vs_human(ai_type: lib.rps.PlayerType) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

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

        const ai_move = player.play(ai_type);

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

        const ai_move_string = switch (ai_move) {
            .rock => "Rock",
            .paper => "Paper",
            .scissors => "Scissors",
        };
        try stdout.print("AI played {s}.\n", .{ai_move_string});

        const outcome = lib.rps.judge(player_move, ai_move);
        const outcome_string = switch (outcome) {
            .win => "You win!",
            .loss => "You lose!",
            .tie => "It's a tie!",
        };
        try stdout.print("{s}\n", .{outcome_string});

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

/// Simulates one game between two AI players and returns the outcome from ai_1's perspective
fn simulate_one_game(ai_1: *lib.rps.RPSPlayer, ai_1_strat: lib.rps.PlayerType, ai_2: *lib.rps.RPSPlayer, ai_2_strat: lib.rps.PlayerType) lib.rps.Outcome {
    const ai_1_move = ai_1.play(ai_1_strat);
    const ai_2_move = ai_2.play(ai_2_strat);
    const outcome = lib.rps.judge(ai_1_move, ai_2_move);
    const other_outcome = lib.rps.other_outcome(outcome);
    const round_ai_1 = lib.rps.Round{
        .my_move = ai_1_move,
        .their_move = ai_2_move,
        .outcome = outcome,
    };
    const round_ai_2 = lib.rps.Round{
        .my_move = ai_2_move,
        .their_move = ai_1_move,
        .outcome = other_outcome,
    };
    ai_1.add_round(round_ai_1);
    ai_2.add_round(round_ai_2);
    return outcome;
}

const Verdict = enum { ai1_better, ai2_better, no_difference, inconclusive };

/// Result of a Sequential Probability Ratio Test between two strategies
const SPRTResult = struct {
    verdict: Verdict,
    ai1_win_rate: f64,
    ai2_win_rate: f64,
    total_games: u32,
    non_tie_games: u32,
};

/// Performs a Sequential Probability Ratio Test (SPRT) to determine if two AI strategies are significantly different.
/// Returns win rates and statistical verdict about which strategy is better.
fn sprt(
    ai_1_strat: lib.rps.PlayerType,
    ai_2_strat: lib.rps.PlayerType,
    silent: bool,
) !SPRTResult {
    const stdout = std.io.getStdOut().writer();

    const alpha: f64 = 0.005;
    const beta: f64 = 0.005;
    const p0: f64 = 0.5;
    const effect_size: f64 = 0.005;
    const p_high: f64 = p0 + effect_size;
    const p_low: f64 = p0 - effect_size;

    const lower_bound: f64 = @log(beta / (1.0 - alpha));
    const upper_bound: f64 = @log((1.0 - beta) / alpha);

    const log_ph_p0: f64 = @log(p_high / p0);
    const log_1ph_1p0: f64 = @log((1 - p_high) / (1 - p0));
    const log_pl_p0: f64 = @log(p_low / p0);
    const log_1pl_1p0: f64 = @log((1 - p_low) / (1 - p0));

    // Header
    if (!silent) {
        try stdout.print("Sequential Probability Ratio Test\n", .{});
        try stdout.print("==================================\n", .{});
        try stdout.print("Strategies: {s} vs {s}\n\n", .{ @tagName(ai_1_strat), @tagName(ai_2_strat) });
        try stdout.print("H0: p = {d:.3}\n", .{p0});
        try stdout.print("H1: AI1 better by ≥{d:.1}% (p = {d:.3})\n", .{ effect_size * 100, p_high });
        try stdout.print("H2: AI2 better by ≥{d:.1}% (p = {d:.3})\n\n", .{ effect_size * 100, p_low });
        try stdout.print("α = {d:.3}, β = {d:.3}\n", .{ alpha, beta });
        try stdout.print("Bounds: [{d:.3}, {d:.3}]\n\n", .{ lower_bound, upper_bound });
    }

    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand1 = prng.random();
    var ai_1 = lib.rps.RPSPlayer.new(rand1);

    try std.posix.getrandom(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);
    const rand2 = prng.random();
    var ai_2 = lib.rps.RPSPlayer.new(rand2);

    var total_games: u32 = 0;
    var non_tie_games: u32 = 0;
    var ai_1_wins: u32 = 0;
    var ai_2_wins: u32 = 0;
    var ties: u32 = 0;
    var llr_high: f64 = 0.0;
    var llr_low: f64 = 0.0;
    const max_games: u32 = 1_000_000;

    var verdict: Verdict = .inconclusive;

    while (total_games < max_games) {
        total_games += 1;
        const outcome = simulate_one_game(&ai_1, ai_1_strat, &ai_2, ai_2_strat);

        switch (outcome) {
            .win => {
                ai_1_wins += 1;
                non_tie_games += 1;
                llr_high += log_ph_p0;
                llr_low += log_pl_p0;
            },
            .loss => {
                ai_2_wins += 1;
                non_tie_games += 1;
                llr_high += log_1ph_1p0;
                llr_low += log_1pl_1p0;
            },
            .tie => {
                ties += 1;
            },
        }

        if (non_tie_games >= 10) {
            if (llr_high >= upper_bound) {
                if (!silent) try stdout.print("\n*** DECISION: AI1 ({s}) is better ***\n", .{@tagName(ai_1_strat)});
                verdict = .ai1_better;
                break;
            } else if (llr_low >= upper_bound) {
                if (!silent) try stdout.print("\n*** DECISION: AI2 ({s}) is better ***\n", .{@tagName(ai_2_strat)});
                verdict = .ai2_better;
                break;
            } else if (llr_high <= lower_bound and llr_low <= lower_bound) {
                if (!silent) try stdout.print("\n*** DECISION: No significant difference ***\n", .{});
                verdict = .no_difference;
                break;
            }
        }
    }

    if (total_games >= max_games and verdict == .inconclusive) {
        if (!silent) try stdout.print("\n*** INCONCLUSIVE: reached max games ***\n", .{});
    }

    if (!silent) {
        try stdout.print("\nFinal Statistics:\n=================\n", .{});
        try stdout.print("Total games: {d}\n", .{total_games});
        try stdout.print("Non-ties:    {d}\n", .{non_tie_games});
        try stdout.print("AI1 wins:    {d}\n", .{ai_1_wins});
        try stdout.print("AI2 wins:    {d}\n", .{ai_2_wins});
        try stdout.print("Ties:        {d}\n", .{ties});
    }

    var ai1_win_rate: f64 = 0.0;
    var ai2_win_rate: f64 = 0.0;

    if (non_tie_games > 0) {
        ai1_win_rate = @as(f64, @floatFromInt(ai_1_wins)) / @as(f64, @floatFromInt(non_tie_games));
        ai2_win_rate = @as(f64, @floatFromInt(ai_2_wins)) / @as(f64, @floatFromInt(non_tie_games));

        if (!silent) {
            const tie_rate = @as(f64, @floatFromInt(ties)) / @as(f64, @floatFromInt(total_games));

            try stdout.print("\nWin rates:\n", .{});
            try stdout.print(" AI1: {d:.1}%\n", .{ai1_win_rate * 100});
            try stdout.print(" AI2: {d:.1}%\n", .{ai2_win_rate * 100});
            try stdout.print(" Tie: {d:.1}%\n", .{tie_rate * 100});

            const diff = ai1_win_rate - ai2_win_rate;
            const se_rate1 = @sqrt((ai1_win_rate * (1.0 - ai1_win_rate)) / @as(f64, @floatFromInt(non_tie_games)));
            const se = 2.0 * se_rate1;
            const z = 1.96;
            const ci_lo = diff - z * se;
            const ci_hi = diff + z * se;
            try stdout.print("\n95% CI for rate difference: [{d:.3}, {d:.3}]\n", .{ ci_lo, ci_hi });
        }
    }

    return SPRTResult{
        .verdict = verdict,
        .ai1_win_rate = ai1_win_rate,
        .ai2_win_rate = ai2_win_rate,
        .total_games = total_games,
        .non_tie_games = non_tie_games,
    };
}

/// Result of comparing two strategies including win rate and statistical verdict
const ComparisonResult = struct {
    win_rate: f64,
    verdict: Verdict,

    fn format_verdict(verdict: Verdict) []const u8 {
        return switch (verdict) {
            .ai1_better => "W",
            .ai2_better => "L",
            .no_difference => "D",
            .inconclusive => "?",
        };
    }

    fn reverse_verdict(verdict: Verdict) Verdict {
        return switch (verdict) {
            .ai1_better => .ai2_better,
            .ai2_better => .ai1_better,
            .no_difference => .no_difference,
            .inconclusive => .inconclusive,
        };
    }
};

/// Runs SPRT tests between all strategy pairs and displays results in a comparison table
fn run_all_strategy_comparisons() !void {
    const stdout = std.io.getStdOut().writer();

    const StrategyInfo = struct {
        kind: lib.rps.PlayerType,
        name: []const u8,
    };

    const all_strategies = [_]StrategyInfo{
        .{ .kind = .random, .name = "random" },
        .{ .kind = .lastmove, .name = "lastmove" },
        .{ .kind = .alwaysrock, .name = "alwaysrock" },
        .{ .kind = .freq1move, .name = "freq1move" },
        .{ .kind = .prob_30_40_30, .name = "30_40_30" },
    };

    var results: [all_strategies.len][all_strategies.len]ComparisonResult = undefined;

    try stdout.print("Running SPRT comparisons between all strategies...\n\n", .{});

    for (all_strategies, 0..) |ai1_info, i| {
        for (all_strategies, 0..) |ai2_info, j| {
            if (i <= j) {
                try stdout.print("Testing {s} vs {s}... ", .{ ai1_info.name, ai2_info.name });

                const result = try sprt(ai1_info.kind, ai2_info.kind, true);

                const win_rate_i = if (result.verdict == .inconclusive)
                    std.math.nan(f32)
                else
                    result.ai1_win_rate;

                results[i][j] = ComparisonResult{
                    .win_rate = win_rate_i,
                    .verdict = result.verdict,
                };

                if (i != j) {
                    const win_rate_j = if (result.verdict == .inconclusive)
                        std.math.nan(f32)
                    else
                        result.ai2_win_rate;

                    results[j][i] = ComparisonResult{
                        .win_rate = win_rate_j,
                        .verdict = ComparisonResult.reverse_verdict(result.verdict),
                    };
                }

                try stdout.print("Done\n", .{});
            }
        }
    }

    try stdout.print("\nStrategy Comparison Table\n", .{});
    try stdout.print("=========================\n\n", .{});
    try stdout.print("Each cell shows: Win Rate% (Verdict)\n", .{});
    try stdout.print("Verdicts: W=Win, L=Loss, D=Draw, ?=Inconclusive\n\n", .{});

    try stdout.print("{s:>13}", .{""});
    for (all_strategies) |s| {
        try stdout.print(" | {s:>11}", .{s.name});
    }
    try stdout.print(" | {s:>9}", .{"Average"});
    try stdout.print("\n", .{});

    try stdout.print("{s:->13}", .{""});
    for (all_strategies) |_| {
        try stdout.print("-+-{s:->11}", .{""});
    }
    try stdout.print("-+-{s:->9}", .{""});
    try stdout.print("\n", .{});

    for (all_strategies, 0..) |s, i| {
        try stdout.print("{s:>13}", .{s.name});

        var total_win_rate: f64 = 0.0;
        var valid_games: u32 = 0;

        for (all_strategies, 0..) |_, j| {
            const result = results[i][j];

            if (!std.math.isNan(result.win_rate)) {
                total_win_rate += result.win_rate;
                valid_games += 1;
            }

            const verdict_str = ComparisonResult.format_verdict(result.verdict);
            try stdout.print(" | {d:>6.1}% ({s:>1})", .{ result.win_rate * 100, verdict_str });
        }

        const avg_win_rate = if (valid_games == 0)
            std.math.nan(f32)
        else
            total_win_rate / @as(f32, @floatFromInt(valid_games));

        try stdout.print(" | {d:>7.1}%", .{avg_win_rate * 100});

        try stdout.print("\n", .{});
    }

    try stdout.print("\n", .{});
}

pub fn main() !void {
    try run_all_strategy_comparisons();

    return;
}
