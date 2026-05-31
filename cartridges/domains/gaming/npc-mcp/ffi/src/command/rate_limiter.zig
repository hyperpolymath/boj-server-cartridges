// SPDX-License-Identifier: MPL-2.0
const std = @import("std");
const testing = std.testing;

pub const RateLimiterConfig = struct {
    rate_per_sec: f64,
    burst: u32,
};

/// Simple token bucket. `tryAcquire(now_nanos)` returns true if a token was
/// available. Thread-safe via internal mutex.
pub const RateLimiter = struct {
    rate_per_sec: f64,
    burst: u32,
    tokens: f64,
    last_nanos: i64,
    mutex: std.Thread.Mutex = .{},

    pub fn init(cfg: RateLimiterConfig) RateLimiter {
        return .{
            .rate_per_sec = cfg.rate_per_sec,
            .burst = cfg.burst,
            .tokens = @as(f64, @floatFromInt(cfg.burst)),
            .last_nanos = 0,
        };
    }

    pub fn tryAcquire(self: *RateLimiter, now_nanos: i64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const elapsed_nanos = now_nanos - self.last_nanos;
        if (elapsed_nanos > 0) {
            const elapsed_sec = @as(f64, @floatFromInt(elapsed_nanos)) / 1_000_000_000.0;
            self.tokens = @min(
                @as(f64, @floatFromInt(self.burst)),
                self.tokens + elapsed_sec * self.rate_per_sec,
            );
            self.last_nanos = now_nanos;
        }

        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }
        return false;
    }
};

test "rate limiter — allows up to burst then denies" {
    var rl = RateLimiter.init(.{ .rate_per_sec = 2.0, .burst = 5 });

    // First 5 calls allowed (burst)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try testing.expect(rl.tryAcquire(0));
    }
    // 6th denied at the same instant
    try testing.expect(!rl.tryAcquire(0));
}

test "rate limiter — refills over time" {
    var rl = RateLimiter.init(.{ .rate_per_sec = 10.0, .burst = 1 });

    try testing.expect(rl.tryAcquire(0));
    try testing.expect(!rl.tryAcquire(0));
    // 100ms later — should have one token back
    try testing.expect(rl.tryAcquire(100_000_000));
}
