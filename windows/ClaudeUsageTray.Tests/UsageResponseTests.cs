using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class UsageResponseTests
{
    [Fact]
    public void DecodesWindowsAndExtraUsageAndSkipsNullsAndNonWindows()
    {
        var response = UsageResponse.Decode("""
            {
              "five_hour": {"utilization": 38.5, "resets_at": "2026-11-03T22:00:00Z"},
              "seven_day": {"utilization": 55, "resets_at": null},
              "seven_day_opus": null,
              "seven_day_sonnet": {"resets_at": "2026-11-03T22:00:00Z"},
              "extra_usage": {"is_enabled": true, "used_credits": 1240, "monthly_limit": 5000},
              "note": "text"
            }
            """);

        Assert.Equal(["five_hour", "seven_day"], response.Windows.Keys.Order());
        Assert.Equal(38.5, response.Windows["five_hour"].Utilization);
        Assert.Null(response.Windows["seven_day"].ResetsAt);
        Assert.Equal(new ExtraUsage(true, 1240, 5000), response.ExtraUsage);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("[1,2]")]
    public void InvalidJsonIsANetworkError(string body)
    {
        var error = Assert.Throws<UsageException>(() => UsageResponse.Decode(body));
        Assert.Equal(UsageErrorKind.NetworkError, error.Kind);
        Assert.Null(error.LoginStatus);
    }

    [Theory]
    [InlineData("five_hour", "Session (5h)")]
    [InlineData("seven_day_opus", "Opus (7d)")]
    [InlineData("iguana_necktie", "Priority Tier")]
    [InlineData("seven_day_new_THING", "Seven Day New Thing")]
    public void LabelsUsageWindowKeys(string key, string expected)
    {
        Assert.Equal(expected, WindowDisplayInfo.LabelForKey(key));
    }

    [Fact]
    public void SecondaryWindowsLeaveOutSessionAndWeeklyAndSortByLabel()
    {
        var usage = new AccountUsage
        {
            Windows = new Dictionary<string, UsageWindow>
            {
                ["five_hour"] = new(1, null),
                ["seven_day"] = new(2, null),
                ["seven_day_sonnet"] = new(30, null),
                ["seven_day_opus"] = new(71, null),
            },
        };

        Assert.Equal(["Opus (7d)", "Sonnet (7d)"], usage.SecondaryWindows.Select(info => info.Label));
        Assert.Equal(29, usage.SecondaryWindows[0].Remaining);
        Assert.Equal(1, usage.SessionWindow!.Utilization);
        Assert.Equal(2, usage.WeeklyWindow!.Utilization);
    }
}
