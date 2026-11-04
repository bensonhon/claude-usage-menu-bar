using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class UsageDisplayTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 3, 20, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(null, null)]
    [InlineData(31.0, UsageColors.Green)]
    [InlineData(30.0, UsageColors.Amber)]
    [InlineData(10.5, UsageColors.Amber)]
    [InlineData(10.0, UsageColors.Red)]
    [InlineData(0.0, UsageColors.Red)]
    public void RemainingColorThresholdsMatchTheMacApp(double? remaining, string? expected)
    {
        Assert.Equal(expected, UsageColors.ForRemaining(remaining));
    }

    [Theory]
    [InlineData(999, "999")]
    [InlineData(1_000, "1.0K")]
    [InlineData(96_400, "96.4K")]
    [InlineData(4_212_000, "4.2M")]
    public void FormatsTokenCounts(long count, string expected)
    {
        Assert.Equal(expected, UsageText.FormatTokenCount(count));
    }

    [Theory]
    [InlineData(30, "now")]
    [InlineData(60 * 34, "34m")]
    [InlineData(60 * 60 * 3, "3h")]
    [InlineData(60 * 60 * 24 * 6, "6d")]
    [InlineData(60 * 60 * 24 * 65, "2mo")]
    public void RelativeTimeIsShort(int secondsAgo, string expected)
    {
        Assert.Equal(expected, UsageText.RelativeTime(Now.AddSeconds(-secondsAgo), Now));
    }

    [Fact]
    public void ModelNamesAndColors()
    {
        Assert.Equal("Opus", UsageText.ShortModel("claude-opus-5-5"));
        Assert.Equal("Sonnet", UsageText.ShortModel("claude-sonnet-5-5"));
        Assert.Equal("Haiku", UsageText.ShortModel("claude-haiku-5-5"));
        Assert.Equal("claude-fable-5-1", UsageText.ShortModel("claude-fable-5-1"));
        Assert.Equal(UsageColors.Accent, UsageText.ModelColorHex("claude-fable-5-1"));
    }

    [Fact]
    public void PercentTextTruncatesAndShowsQuestionMarkWithoutData()
    {
        Assert.Equal("62%", UsageText.PercentText(62.9));
        Assert.Equal("?", UsageText.PercentText(null));
        Assert.Equal("Session 62% left · Weekly ? left", UsageText.AccountTabTooltip(62, null));
    }

    [Fact]
    public void FriendlyErrorMessageForLoginErrors()
    {
        Assert.Equal("Requires Claude Code CLI. Sign in via claude to load usage data.", UsageText.FriendlyErrorMessage("Network error: HTTP 401: nope"));
        Assert.Equal("Network error: HTTP 500: oops", UsageText.FriendlyErrorMessage("Network error: HTTP 500: oops"));
    }

    [Fact]
    public void LastUpdatedText()
    {
        Assert.Equal("Updated 20 sec ago", UsageText.LastUpdatedText(Now.AddSeconds(-20), Now));
        Assert.Equal("Updated 3 min ago", UsageText.LastUpdatedText(Now.AddMinutes(-3), Now));
        Assert.Equal("Updated 2 hr ago", UsageText.LastUpdatedText(Now.AddHours(-2), Now));
    }

    [Fact]
    public void LoginFilePreviewNamesTheCredentialsFile()
    {
        var home = Path.Combine(Path.GetTempPath(), "home");
        Assert.Equal($"Login file: {Path.Combine(home, ".claude-work", ".credentials.json")}", UsageText.LoginFilePreview("~/.claude-work", home));
        Assert.Equal("Type the folder you set as CLAUDE_CONFIG_DIR", UsageText.LoginFilePreview("claude", home));
    }
}

public class TrayIconPlanTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 3, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task OneRingPerShownAccountWithAccountColorsOnlyWhenThereAreSeveral()
    {
        using var home = new TemporaryFolder();
        home.WriteFile(Credentials.Json("token"), ".claude", ".credentials.json");
        var store = new AccountStore(Path.Combine(home.Path, "accounts.json"), home.Path);
        var clock = new FixedTimeProvider(Now);
        var service = new UsageService(store, new FakeUsageApi(), clock, home.Path);
        await service.RefreshAsync();

        var single = TrayIconPlan.Entries(store, service, showLogo: false, showResetTime: true, clock);
        var ring = Assert.IsType<TrayIconEntry.AccountRing>(Assert.Single(single));
        Assert.Equal(60, ring.Remaining);
        Assert.Null(ring.AccountColorHex);
        Assert.Equal("claude\nSession 60% left, resets 8PM\nWeekly ? left", ring.TooltipText);

        store.AddFoundConfigFolders([Path.Combine(home.Path, ".claude-work")]);
        await service.ShownAccountsRefresh;
        var several = TrayIconPlan.Entries(store, service, showLogo: true, showResetTime: false, clock);
        Assert.IsType<TrayIconEntry.Logo>(several[0]);
        Assert.Equal([AccountColor.Hexes[0], AccountColor.Hexes[1]], several.OfType<TrayIconEntry.AccountRing>().Select(r => r.AccountColorHex));
        Assert.Equal("claude\nSession 60% left\nWeekly ? left", several.OfType<TrayIconEntry.AccountRing>().First().TooltipText);
    }

    [Fact]
    public void LogoIsShownWhenNoAccountIsShown()
    {
        using var home = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(home.Path, "accounts.json"), home.Path);
        store.SetShownInTray(false, store.Accounts[0].ConfigFolderPath);
        var service = new UsageService(store, new FakeUsageApi(), new FixedTimeProvider(Now), home.Path);

        Assert.IsType<TrayIconEntry.Logo>(Assert.Single(TrayIconPlan.Entries(store, service, false, true, new FixedTimeProvider(Now))));
    }

    [Fact]
    public void TooltipIsCutToTheWindowsLimit()
    {
        var account = new ClaudeAccount("C:\\x", new string('a', 200), true, false);
        var tooltip = TrayIconPlan.TooltipText(account, new AccountUsage(), true, new FixedTimeProvider(Now));
        Assert.Equal(TrayIconPlan.MaximumTooltipLength, tooltip.Length);
        Assert.EndsWith("…", tooltip);
    }

    [Fact]
    public void TooltipWithoutDataSaysWhy()
    {
        var account = new ClaudeAccount("C:\\x", "work", true, false);
        Assert.Equal("work\nNo usage data yet", TrayIconPlan.TooltipText(account, new AccountUsage(), true, new FixedTimeProvider(Now)));
        Assert.Equal("work\nLogin problem: open for details",
            TrayIconPlan.TooltipText(account, new AccountUsage { LoginStatus = LoginStatus.TokenExpired }, true, new FixedTimeProvider(Now)));
    }
}
