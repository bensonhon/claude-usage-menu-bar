using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class ResetClockTests
{
    private static readonly TimeZoneInfo PacificTime = TimeZoneInfo.CreateCustomTimeZone("Test-8", TimeSpan.FromHours(-8), "Test-8", "Test-8");
    private static readonly FixedTimeProvider NoonPacific = new(new DateTimeOffset(2026, 11, 3, 20, 0, 0, TimeSpan.Zero), PacificTime);

    [Theory]
    [InlineData("2026-11-03T22:59:00Z", "3PM")]
    [InlineData("2026-11-03T22:29:00Z", "2PM")]
    [InlineData("2026-11-03T22:30:00Z", "3PM")]
    [InlineData("2026-11-03T22:00:00.123Z", "2PM")]
    [InlineData("2026-11-03T16:10:00Z", "8AM")]
    public void ResetClockShortRoundsToTheNearestHour(string resetsAt, string expected)
    {
        Assert.Equal(expected, ResetClock.ResetClockShort(new UsageWindow(10, resetsAt), NoonPacific));
    }

    [Fact]
    public void ResetClockStringSaysTodayTomorrowOrTheDate()
    {
        Assert.Equal("3PM", ResetClock.ResetClockString(new UsageWindow(10, "2026-11-03T23:00:00Z"), NoonPacific));
        Assert.Equal("Tomorrow 9AM", ResetClock.ResetClockString(new UsageWindow(10, "2026-11-04T17:00:00Z"), NoonPacific));
        Assert.Equal("Nov 6, 7PM", ResetClock.ResetClockString(new UsageWindow(10, "2026-11-07T03:00:00+00:00"), NoonPacific));
    }

    [Fact]
    public void MissingOrUnparseableResetTimeShowsADash()
    {
        Assert.Equal("—", ResetClock.ResetClockShort(null, NoonPacific));
        Assert.Equal("—", ResetClock.ResetClockString(new UsageWindow(10, null), NoonPacific));
        Assert.Equal("—", ResetClock.ResetClockString(new UsageWindow(10, "not a date"), NoonPacific));
    }

    [Theory]
    [InlineData(38, 62)]
    [InlineData(-5, 100)]
    [InlineData(130, 0)]
    public void RemainingIsClampedBetweenZeroAndOneHundred(double utilization, double expectedRemaining)
    {
        Assert.Equal(expectedRemaining, new UsageWindow(utilization, null).Remaining);
    }
}
