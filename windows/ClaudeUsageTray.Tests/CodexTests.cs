using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class CodexAuthFileTests
{
    private static readonly FixedTimeProvider Now = new(new DateTimeOffset(2026, 11, 21, 18, 0, 0, TimeSpan.Zero));

    [Fact]
    public void AccessTokenExpiryIsReadFromTheExpClaim()
    {
        var expiry = new DateTimeOffset(2026, 11, 30, 17, 16, 17, TimeSpan.Zero);
        Assert.Equal(expiry, CodexAuthFile.AccessTokenExpiry(CodexAuth.AccessToken(expiry)));
        Assert.Null(CodexAuthFile.AccessTokenExpiry("not-a-jwt"));
        Assert.Null(CodexAuthFile.AccessTokenExpiry("a." + CodexAuth.Base64Url("""{"iat":1}""") + ".c"));
        Assert.Null(CodexAuthFile.AccessTokenExpiry("a.!!!.c"));
    }

    [Fact]
    public void ChatGPTLoginGivesTheAccessTokenAndAccountId()
    {
        using var home = new TemporaryFolder();
        var accessToken = CodexAuth.AccessToken(Now.UtcNow.AddDays(9));
        var configFolderPath = home.CreateFolder(".codex");
        home.WriteFile(CodexAuth.Json(accessToken, "account-7"), ".codex", "auth.json");

        Assert.True(CodexAuthFile.Exists(configFolderPath));
        Assert.Equal(new CodexLoginToken(accessToken, "account-7"), CodexAuthFile.ReadLoginToken(configFolderPath, Now));
        Assert.Equal(LoginStatus.Found, CodexAuthFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void AccessTokenPastItsExpIsExpired()
    {
        var error = Assert.Throws<UsageException>(() =>
            CodexAuthFile.LoginTokenFrom(CodexAuth.Json(CodexAuth.AccessToken(Now.UtcNow.AddSeconds(-1))), Now));
        Assert.Equal(LoginStatus.TokenExpired, error.LoginStatus);
        Assert.Equal("Codex login token expired. Use Codex with this account once to refresh it.", error.Message);
    }

    [Theory]
    [InlineData("""{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test","tokens":null}""")]
    [InlineData("""{"auth_mode":"chatgpt","tokens":{"access_token":"","account_id":"a"}}""")]
    [InlineData("""{"auth_mode":"chatgpt","tokens":{"access_token":"a.b.c"}}""")]
    public void NoChatGPTLoginIsNotFound(string authFileText)
    {
        var error = Assert.Throws<UsageException>(() => CodexAuthFile.LoginTokenFrom(authFileText, Now));
        Assert.Equal(LoginStatus.NotFound, error.LoginStatus);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("""{"tokens":{"access_token":"opaque-token","account_id":"a"}}""")]
    public void UnreadableLoginIsUnreadable(string authFileText)
    {
        var error = Assert.Throws<UsageException>(() => CodexAuthFile.LoginTokenFrom(authFileText, Now));
        Assert.Equal(LoginStatus.Unreadable, error.LoginStatus);
    }

    [Fact]
    public void FolderWithoutAuthFileHasNoLogin()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".codex");

        Assert.False(CodexAuthFile.Exists(configFolderPath));
        Assert.Equal(LoginStatus.NotFound, CodexAuthFile.ReadLoginStatus(configFolderPath, Now));
        Assert.Equal(LoginStatus.NotFound, CodexAuthFile.ReadLoginStatus(Path.Combine(home.Path, "missing"), Now));
    }
}

public class CodexUsageResponseTests
{
    [Fact]
    public void WeeklyOnlyPlanHasOnlyTheWeeklyWindow()
    {
        var response = CodexUsageResponse.Decode("""
            {"plan_type":"self_serve_business_prolite",
             "rate_limit":{"allowed":true,"limit_reached":false,
               "primary_window":{"used_percent":34,"limit_window_seconds":604800,"reset_after_seconds":515491,"reset_at":1795799695},
               "secondary_window":null},
             "credits":{"has_credits":false}}
            """);

        Assert.Equal(["seven_day"], response.Windows.Keys);
        Assert.Equal(34, response.Windows["seven_day"].Utilization);
        Assert.Equal(66, response.Windows["seven_day"].Remaining);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1795799695), response.Windows["seven_day"].ResetDate);
        Assert.Equal("Business Prolite", response.PlanName);
    }

    [Fact]
    public void FiveHourAndSevenDayWindowsAreSessionAndWeekly()
    {
        var response = CodexUsageResponse.Decode("""
            {"plan_type":"plus","rate_limit":{
              "primary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_at":1795700000},
              "secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":1795799695}}}
            """);

        Assert.Equal(12.5, response.Windows["five_hour"].Utilization);
        Assert.Equal(40, response.Windows["seven_day"].Utilization);
        Assert.Equal("Plus", response.PlanName);
    }

    [Fact]
    public void SelfServeIsOnlyDroppedFromTheStartOfThePlanType()
    {
        Assert.Equal("Business Self Serve", CodexUsageResponse.PlanNameFor("business_self_serve"));
    }

    [Fact]
    public void WindowOfAnotherLengthIsNamedByItsHours()
    {
        Assert.Equal("720_hour", CodexUsageResponse.WindowKey(30 * 24 * 60 * 60));
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("""{"plan_type":"plus","rate_limit":null}""")]
    [InlineData("""{"rate_limit":{}}""")]
    [InlineData("""{"plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000}}}""")]
    public void MalformedReplyIsANetworkError(string body)
    {
        var error = Assert.Throws<UsageException>(() => CodexUsageResponse.Decode(body));
        Assert.Equal(UsageErrorKind.NetworkError, error.Kind);
    }
}

public class TrayRingWindowTests
{
    private static readonly UsageWindow Session = new(10, null);
    private static readonly UsageWindow Weekly = new(70, null);

    [Fact]
    public void TrayRingShowsSessionWhenThereIsOne()
    {
        var usage = new AccountUsage { Windows = new Dictionary<string, UsageWindow> { ["five_hour"] = Session, ["seven_day"] = Weekly } };
        Assert.Same(Session, usage.TrayRingWindow);
    }

    [Fact]
    public void TrayRingShowsWeeklyWhenThereIsNoSession()
    {
        var usage = new AccountUsage { Windows = new Dictionary<string, UsageWindow> { ["seven_day"] = Weekly } };
        Assert.Same(Weekly, usage.TrayRingWindow);
    }

    [Fact]
    public void TrayRingHasNoWindowWithoutUsage()
    {
        Assert.Null(new AccountUsage().TrayRingWindow);
    }
}

public class CodexAccountTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 21, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public void AccountsSavedBeforeCodexSupportLoadAsClaudeCode()
    {
        using var folder = new TemporaryFolder();
        var workPath = Path.Combine(folder.Path, ".claude-work");
        var accountsFilePath = folder.WriteFile(
            $$"""[{"ConfigFolderPath":{{System.Text.Json.JsonSerializer.Serialize(workPath)}},"Label":"work","IsShownInTray":false,"IsFoundAutomatically":true}]""",
            "accounts.json");

        var store = new AccountStore(accountsFilePath, folder.Path);

        Assert.Equal(new Account(workPath, "work", false, true, CodingTool.ClaudeCode), store.Accounts[1]);
    }

    [Fact]
    public void FoundCodexFolderIsSavedAsACodexAccount()
    {
        using var folder = new TemporaryFolder();
        var accountsFilePath = Path.Combine(folder.Path, "accounts.json");
        var codexPath = Path.Combine(folder.Path, ".codex");
        var store = new AccountStore(accountsFilePath, folder.Path);

        store.AddFoundConfigFolders([codexPath], CodingTool.Codex);
        store.AddFoundConfigFolders([codexPath], CodingTool.Codex);

        Assert.Equal(new Account(codexPath, "codex", true, true, CodingTool.Codex), Assert.Single(store.Accounts, account => account.CodingTool == CodingTool.Codex));
        Assert.Contains("\"Codex\"", File.ReadAllText(accountsFilePath));
        Assert.Equal(CodingTool.Codex, new AccountStore(accountsFilePath, folder.Path).Accounts[1].CodingTool);
    }

    [Fact]
    public void FindsDotCodexFoldersThatHaveAnAuthFile()
    {
        using var home = new TemporaryFolder();
        home.WriteFile("{}", ".codex", "auth.json");
        home.WriteFile("{}", ".codex-work", "auth.json");
        home.CreateFolder(".codex-empty");
        home.WriteFile("{}", ".claude", "auth.json");

        Assert.Equal(
            [Path.Combine(home.Path, ".codex"), Path.Combine(home.Path, ".codex-work")],
            UsageService.FindCodexConfigFoldersWithAuthFile(home.Path));
        Assert.Empty(UsageService.FindClaudeConfigFoldersWithCredentialsFile(home.Path));
    }

    [Fact]
    public async Task RefreshLoadsCodexUsageWithTheChatGPTLogin()
    {
        using var home = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(home.Path, "AppData", "accounts.json"), home.Path);
        var api = new FakeUsageApi();
        var clock = new FixedTimeProvider(Now);
        var service = new UsageService(store, api, clock, home.Path);
        var accessToken = CodexAuth.AccessToken(Now.AddDays(9));
        home.WriteFile(CodexAuth.Json(accessToken, "account-7"), ".codex", "auth.json");

        await service.RefreshAsync();
        await service.ShownAccountsRefresh;

        var codexAccount = Assert.Single(store.Accounts, account => account.CodingTool == CodingTool.Codex);
        var usage = service.UsageFor(codexAccount);
        Assert.NotEmpty(api.RequestedCodexLoginTokens);
        Assert.All(api.RequestedCodexLoginTokens, loginToken => Assert.Equal(new CodexLoginToken(accessToken, "account-7"), loginToken));
        Assert.DoesNotContain(accessToken, api.RequestedAccessTokens);
        Assert.IsType<UsageLoadState.Loaded>(usage.LoadState);
        Assert.Equal(LoginStatus.Found, usage.LoginStatus);
        Assert.Equal("Plus", usage.PlanName);
        Assert.Null(usage.SessionWindow);
        Assert.Equal(70, usage.TrayRingWindow!.Remaining);
        Assert.Null(usage.ExtraUsage);
        Assert.True(usage.TokenActivityLoaded);
        Assert.Empty(usage.TokenActivity.RecentSessions);

        var ring = TrayIconPlan.Entries(store, service, showResetTime: false, clock)
            .OfType<TrayIconEntry.AccountRing>()
            .Single(entry => entry.Account.CodingTool == CodingTool.Codex);
        Assert.Equal(70, ring.Remaining);
    }

    [Fact]
    public async Task ExpiredCodexTokenIsALoginProblemAndIsNotSent()
    {
        using var home = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(home.Path, "AppData", "accounts.json"), home.Path);
        var api = new FakeUsageApi();
        var service = new UsageService(store, api, new FixedTimeProvider(Now), home.Path);
        home.WriteFile(CodexAuth.Json(CodexAuth.AccessToken(Now.AddMinutes(-1))), ".codex", "auth.json");

        await service.RefreshAsync();
        await service.ShownAccountsRefresh;

        var usage = service.UsageFor(Assert.Single(store.Accounts, account => account.CodingTool == CodingTool.Codex));
        Assert.Equal(LoginStatus.TokenExpired, usage.LoginStatus);
        Assert.IsType<UsageLoadState.Failed>(usage.LoadState);
        Assert.Empty(api.RequestedCodexLoginTokens);
    }

    [Fact]
    public async Task HiddenCodexAccountOnlyChecksItsLogin()
    {
        using var home = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(home.Path, "AppData", "accounts.json"), home.Path);
        var api = new FakeUsageApi();
        var service = new UsageService(store, api, new FixedTimeProvider(Now), home.Path);
        home.WriteFile(CodexAuth.Json(CodexAuth.AccessToken(Now.AddDays(1))), ".codex", "auth.json");
        await service.RefreshAsync();
        var codexAccount = Assert.Single(store.Accounts, account => account.CodingTool == CodingTool.Codex);
        store.SetShownInTray(false, codexAccount.ConfigFolderPath);
        await service.ShownAccountsRefresh;
        api.RequestedCodexLoginTokens.Clear();

        await service.RefreshAsync(force: true);

        Assert.Empty(api.RequestedCodexLoginTokens);
        Assert.Equal(LoginStatus.Found, service.UsageFor(codexAccount).LoginStatus);
    }
}
