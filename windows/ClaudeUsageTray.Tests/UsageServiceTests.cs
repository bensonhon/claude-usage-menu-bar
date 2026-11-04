using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class UsageServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 3, 20, 0, 0, TimeSpan.Zero);

    private static (TemporaryFolder Home, AccountStore Store, FakeUsageApi Api, FixedTimeProvider Clock, UsageService Service) CreateService()
    {
        var home = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(home.Path, "AppData", "accounts.json"), home.Path);
        var api = new FakeUsageApi();
        var clock = new FixedTimeProvider(Now);
        return (home, store, api, clock, new UsageService(store, api, clock, home.Path));
    }

    [Fact]
    public void FindsDotClaudeFoldersThatHaveACredentialsFile()
    {
        using var home = new TemporaryFolder();
        home.WriteFile("{}", ".claude-work", ".credentials.json");
        home.WriteFile("{}", ".claude", ".credentials.json");
        home.CreateFolder(".claude-empty");
        home.WriteFile("{}", "other", ".credentials.json");

        Assert.Equal(
            [Path.Combine(home.Path, ".claude"), Path.Combine(home.Path, ".claude-work")],
            UsageService.FindConfigFoldersWithCredentialsFile(home.Path));
    }

    [Fact]
    public async Task RefreshLoadsUsageForShownAccountsAndLoginStatusForHiddenOnes()
    {
        var (home, store, api, _, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("default-token"), ".claude", ".credentials.json");
        home.WriteFile(Credentials.Json("work-token", Now.AddHours(-1).ToUnixTimeMilliseconds()), ".claude-work", ".credentials.json");
        await service.RefreshAsync();
        var workAccount = store.Accounts.Single(account => account.ConfigFolderPath.EndsWith(".claude-work"));
        store.SetShownInTray(false, workAccount.ConfigFolderPath);
        await service.ShownAccountsRefresh;
        await service.RefreshAsync(force: true);

        var defaultUsage = service.UsageFor(store.Accounts[0]);
        Assert.IsType<UsageLoadState.Loaded>(defaultUsage.LoadState);
        Assert.Equal(LoginStatus.Found, defaultUsage.LoginStatus);
        Assert.Equal("Max", defaultUsage.PlanName);
        Assert.Equal(60, defaultUsage.SessionWindow!.Remaining);
        Assert.Equal(Now, defaultUsage.LastUpdated);
        Assert.True(defaultUsage.TokenActivityLoaded);
        Assert.Equal(LoginStatus.TokenExpired, service.UsageFor(store.Accounts[1]).LoginStatus);
        Assert.DoesNotContain("work-token", api.RequestedAccessTokens);
    }

    [Fact]
    public async Task ChangingWhichAccountsAreShownStartsARefresh()
    {
        var (home, store, api, _, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("token"), ".claude", ".credentials.json");
        var defaultPath = store.Accounts[0].ConfigFolderPath;

        var startedRefreshes = new List<Task>();
        service.ShownAccountsRefreshStarted += startedRefreshes.Add;

        store.SetLabel("renamed", defaultPath);
        Assert.Same(Task.CompletedTask, service.ShownAccountsRefresh);
        Assert.Empty(startedRefreshes);

        store.SetShownInTray(false, defaultPath);
        store.SetShownInTray(true, defaultPath);
        await Task.WhenAll(startedRefreshes);

        Assert.Equal(2, startedRefreshes.Count);
        Assert.Same(startedRefreshes[^1], service.ShownAccountsRefresh);

        Assert.Contains("token", api.RequestedAccessTokens);
        Assert.Equal(LoginStatus.Found, service.UsageFor(store.Accounts[0]).LoginStatus);
    }

    [Fact]
    public async Task ExpiredTokenIsShownAsALoginProblemWithAFailedLoad()
    {
        var (home, store, _, _, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("token", Now.AddMinutes(-5).ToUnixTimeMilliseconds()), ".claude", ".credentials.json");

        await service.RefreshAsync();

        var usage = service.UsageFor(store.Accounts[0]);
        Assert.Equal(LoginStatus.TokenExpired, usage.LoginStatus);
        Assert.IsType<UsageLoadState.Failed>(usage.LoadState);
        Assert.False(usage.HasUsageData);
        Assert.Equal(UsageService.RefreshIntervalWhileWaitingForData, service.NextRefreshInterval);
    }

    [Fact]
    public async Task NetworkErrorKeepsTheLoginStatus()
    {
        var (home, store, api, _, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("token"), ".claude", ".credentials.json");
        api.Respond = _ => throw UsageException.NetworkError("HTTP 500: oops");

        await service.RefreshAsync();

        var usage = service.UsageFor(store.Accounts[0]);
        Assert.Equal(LoginStatus.Found, usage.LoginStatus);
        Assert.Equal(new UsageLoadState.Failed("Network error: HTTP 500: oops"), usage.LoadState);
    }

    [Fact]
    public async Task FetchesAgainOnlyAfterSixtySecondsUnlessForced()
    {
        var (home, _, api, clock, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("token"), ".claude", ".credentials.json");

        await service.RefreshAsync();
        clock.UtcNow = Now.AddSeconds(30);
        await service.RefreshAsync();
        Assert.Single(api.RequestedAccessTokens);

        await service.RefreshAsync(force: true);
        Assert.Equal(2, api.RequestedAccessTokens.Count);

        clock.UtcNow = Now.AddSeconds(95);
        await service.RefreshAsync();
        Assert.Equal(3, api.RequestedAccessTokens.Count);
        Assert.Equal(UsageService.RefreshIntervalWithData, service.NextRefreshInterval);
    }

    [Fact]
    public async Task UsageChangesArePublishedOnTheCallersSynchronizationContext()
    {
        var (home, _, _, _, service) = CreateService();
        using var _home = home;
        home.WriteFile(Credentials.Json("token"), ".claude", ".credentials.json");
        var contextThread = new SingleThreadSynchronizationContext();
        var threadsThatPublished = new List<int>();
        service.UsageChanged += () => threadsThatPublished.Add(Environment.CurrentManagedThreadId);

        await contextThread.RunAsync(() => service.RefreshAsync());

        Assert.NotEmpty(threadsThatPublished);
        Assert.All(threadsThatPublished, threadId => Assert.Equal(contextThread.ThreadId, threadId));
    }
}

public sealed class SingleThreadSynchronizationContext : SynchronizationContext
{
    private readonly System.Collections.Concurrent.BlockingCollection<(SendOrPostCallback Callback, object? State)> queue = new();

    public int ThreadId { get; private set; }

    public override void Post(SendOrPostCallback callback, object? state) => queue.Add((callback, state));

    public Task RunAsync(Func<Task> work)
    {
        var completion = new TaskCompletionSource();
        var thread = new Thread(() =>
        {
            ThreadId = Environment.CurrentManagedThreadId;
            SetSynchronizationContext(this);
            var task = work();
            task.ContinueWith(_ => queue.CompleteAdding(), TaskScheduler.Default);
            foreach (var (callback, state) in queue.GetConsumingEnumerable())
            {
                callback(state);
            }
            if (task.Exception is { } exception)
            {
                completion.SetException(exception.InnerExceptions);
            }
            else
            {
                completion.SetResult();
            }
        });
        thread.Start();
        return completion.Task;
    }
}
