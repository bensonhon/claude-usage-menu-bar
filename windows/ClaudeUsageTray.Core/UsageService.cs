using System.Net.Http.Headers;

namespace ClaudeUsageTray.Core;

public abstract record UsageLoadState
{
    public sealed record Idle : UsageLoadState;
    public sealed record Loading : UsageLoadState;
    public sealed record Loaded : UsageLoadState;
    public sealed record Failed(string Message) : UsageLoadState;
}

public sealed record AccountUsage
{
    public UsageLoadState LoadState { get; init; } = new UsageLoadState.Idle();
    public LoginStatus LoginStatus { get; init; } = LoginStatus.NotChecked;
    public IReadOnlyDictionary<string, UsageWindow> Windows { get; init; } = new Dictionary<string, UsageWindow>();
    public ExtraUsage? ExtraUsage { get; init; }
    public TokenActivity TokenActivity { get; init; } = new();
    public bool TokenActivityLoaded { get; init; }
    public DateTimeOffset? LastUpdated { get; init; }
    public string PlanName { get; init; } = "Pro";

    public UsageWindow? SessionWindow => Windows.GetValueOrDefault("five_hour");
    public UsageWindow? WeeklyWindow => Windows.GetValueOrDefault("seven_day");
    public UsageWindow? TrayRingWindow => SessionWindow ?? WeeklyWindow;
    public bool HasUsageData => Windows.Count > 0;

    public IReadOnlyList<WindowDisplayInfo> SecondaryWindows => Windows
        .Where(entry => entry.Key is not ("five_hour" or "seven_day"))
        .Select(entry => WindowDisplayInfo.From(entry.Key, entry.Value))
        .OrderBy(info => info.Label, StringComparer.Ordinal)
        .ToList();
}

public interface IUsageApi
{
    Task<UsageResponse> FetchClaudeUsageAsync(string accessToken);

    Task<CodexUsageResponse> FetchCodexUsageAsync(CodexLoginToken loginToken);
}

public sealed class UsageApiClient : IUsageApi
{
    public static readonly Uri ClaudeUsageApiUri = new("https://platform.claude.com/api/oauth/usage");
    public static readonly Uri CodexUsageApiUri = new("https://chatgpt.com/backend-api/wham/usage");

    private readonly HttpClient httpClient;

    public UsageApiClient(HttpClient httpClient)
    {
        this.httpClient = httpClient;
        this.httpClient.Timeout = TimeSpan.FromSeconds(15);
    }

    public async Task<UsageResponse> FetchClaudeUsageAsync(string accessToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, ClaudeUsageApiUri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.TryAddWithoutValidation("User-Agent", "claude-code/2.x");
        return UsageResponse.Decode(await FetchSuccessBodyAsync(request));
    }

    public async Task<CodexUsageResponse> FetchCodexUsageAsync(CodexLoginToken loginToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, CodexUsageApiUri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", loginToken.AccessToken);
        request.Headers.Add("chatgpt-account-id", loginToken.ChatGPTAccountId);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.TryAddWithoutValidation("User-Agent", "codex-cli");
        return CodexUsageResponse.Decode(await FetchSuccessBodyAsync(request));
    }

    private async Task<string> FetchSuccessBodyAsync(HttpRequestMessage request)
    {
        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(request);
        }
        catch (HttpRequestException error)
        {
            throw UsageException.NetworkError(error.Message, error);
        }
        catch (TaskCanceledException error)
        {
            throw UsageException.NetworkError("The request timed out.", error);
        }
        using (response)
        {
            var body = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw UsageException.NetworkError($"HTTP {(int)response.StatusCode}: {(body.Length == 0 ? "No body" : body)}");
            }
            return body;
        }
    }
}

public sealed class UsageService
{
    public static readonly TimeSpan RefreshIntervalWhileWaitingForData = TimeSpan.FromSeconds(15);
    public static readonly TimeSpan RefreshIntervalWithData = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan MinimumTimeBetweenFetches = TimeSpan.FromSeconds(60);

    private readonly AccountStore accountStore;
    private readonly IUsageApi usageApi;
    private readonly TimeProvider timeProvider;
    private readonly string homeFolderPath;
    private readonly Dictionary<string, AccountUsage> usageByConfigFolderPath = new(StringComparer.OrdinalIgnoreCase);
    private List<string> shownConfigFolderPaths;

    public event Action? UsageChanged;

    public event Action<Task>? ShownAccountsRefreshStarted;

    public Task ShownAccountsRefresh { get; private set; } = Task.CompletedTask;

    public UsageService(AccountStore accountStore, IUsageApi usageApi, TimeProvider timeProvider, string homeFolderPath)
    {
        this.accountStore = accountStore;
        this.usageApi = usageApi;
        this.timeProvider = timeProvider;
        this.homeFolderPath = homeFolderPath;
        shownConfigFolderPaths = ShownConfigFolderPaths();
        accountStore.AccountsChanged += OnAccountsChanged;
    }

    public AccountUsage UsageFor(Account account) =>
        usageByConfigFolderPath.GetValueOrDefault(account.ConfigFolderPath) ?? new AccountUsage();

    public bool IsEveryShownAccountLoaded => accountStore.ShownAccounts.All(account => UsageFor(account).HasUsageData);

    public TimeSpan NextRefreshInterval => IsEveryShownAccountLoaded ? RefreshIntervalWithData : RefreshIntervalWhileWaitingForData;

    public async Task RefreshAsync(bool force = false)
    {
        var claudeConfigFolderPaths = await Task.Run(() => FindClaudeConfigFoldersWithCredentialsFile(homeFolderPath));
        var codexConfigFolderPaths = await Task.Run(() => FindCodexConfigFoldersWithAuthFile(homeFolderPath));
        accountStore.AddFoundConfigFolders(claudeConfigFolderPaths, CodingTool.ClaudeCode);
        accountStore.AddFoundConfigFolders(codexConfigFolderPaths, CodingTool.Codex);
        await Task.WhenAll(accountStore.Accounts.ToList().Select(account => RefreshAsync(account, force)));
    }

    public static IReadOnlyList<string> FindClaudeConfigFoldersWithCredentialsFile(string homeFolderPath) =>
        FindConfigFolders(homeFolderPath, Account.IsClaudeConfigFolderName, ClaudeCredentialsFile.Exists);

    public static IReadOnlyList<string> FindCodexConfigFoldersWithAuthFile(string homeFolderPath) =>
        FindConfigFolders(homeFolderPath, Account.IsCodexConfigFolderName, CodexAuthFile.Exists);

    private static IReadOnlyList<string> FindConfigFolders(string homeFolderPath, Func<string, bool> isConfigFolderName, Func<string, bool> hasLogin)
    {
        IEnumerable<string> folderPaths;
        try
        {
            folderPaths = Directory.EnumerateDirectories(homeFolderPath).ToList();
        }
        catch (DirectoryNotFoundException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
        return folderPaths
            .Where(folderPath => isConfigFolderName(Path.GetFileName(folderPath)))
            .Where(hasLogin)
            .OrderBy(folderPath => folderPath, StringComparer.Ordinal)
            .ToList();
    }

    private async Task RefreshAsync(Account account, bool force)
    {
        var configFolderPath = account.ConfigFolderPath;

        if (!account.IsShownInTray)
        {
            var loginStatus = await Task.Run(() => ReadLoginStatus(account));
            SetUsage(configFolderPath, usage => usage with { LoginStatus = loginStatus });
            return;
        }

        var activityTask = account.CodingTool switch
        {
            CodingTool.ClaudeCode => Task.Run(() => TokenHistoryParser.ParseLocalTokenHistoryAsync(account.ProjectsFolderPath, timeProvider)),
            CodingTool.Codex => Task.FromResult(new TokenActivity()),
            _ => throw new ArgumentOutOfRangeException(nameof(account), account.CodingTool, null),
        };

        var lastUpdated = usageByConfigFolderPath.GetValueOrDefault(configFolderPath)?.LastUpdated;
        var skipNetwork = !force && lastUpdated is { } updatedAt && timeProvider.GetUtcNow() - updatedAt < MinimumTimeBetweenFetches;

        if (!skipNetwork)
        {
            SetUsage(configFolderPath, usage => usage with { LoadState = new UsageLoadState.Loading() });
            try
            {
                var fetchedUsage = await FetchUsageAsync(account);
                SetUsage(configFolderPath, usage => usage with
                {
                    Windows = fetchedUsage.Windows,
                    ExtraUsage = fetchedUsage.ExtraUsage,
                    PlanName = fetchedUsage.PlanName,
                    LastUpdated = timeProvider.GetUtcNow(),
                    LoadState = new UsageLoadState.Loaded(),
                });
            }
            catch (UsageException error)
            {
                SetUsage(configFolderPath, usage => usage with
                {
                    LoginStatus = error.LoginStatus ?? usage.LoginStatus,
                    LoadState = new UsageLoadState.Failed(error.Message),
                });
            }
        }

        var activity = await activityTask;
        SetUsage(configFolderPath, usage => usage with { TokenActivity = activity, TokenActivityLoaded = true });
    }

    private sealed record FetchedUsage(IReadOnlyDictionary<string, UsageWindow> Windows, ExtraUsage? ExtraUsage, string PlanName);

    private async Task<FetchedUsage> FetchUsageAsync(Account account)
    {
        var configFolderPath = account.ConfigFolderPath;
        switch (account.CodingTool)
        {
            case CodingTool.ClaudeCode:
            {
                var loginToken = await Task.Run(() => ClaudeCredentialsFile.ReadLoginToken(configFolderPath, timeProvider));
                SetUsage(configFolderPath, usage => usage with { LoginStatus = LoginStatus.Found });
                var response = await usageApi.FetchClaudeUsageAsync(loginToken.AccessToken);
                return new FetchedUsage(response.Windows, response.ExtraUsage, loginToken.PlanName);
            }
            case CodingTool.Codex:
            {
                var loginToken = await Task.Run(() => CodexAuthFile.ReadLoginToken(configFolderPath, timeProvider));
                SetUsage(configFolderPath, usage => usage with { LoginStatus = LoginStatus.Found });
                var response = await usageApi.FetchCodexUsageAsync(loginToken);
                return new FetchedUsage(response.Windows, null, response.PlanName);
            }
            default:
                throw new ArgumentOutOfRangeException(nameof(account), account.CodingTool, null);
        }
    }

    private LoginStatus ReadLoginStatus(Account account) => account.CodingTool switch
    {
        CodingTool.ClaudeCode => ClaudeCredentialsFile.ReadLoginStatus(account.ConfigFolderPath, timeProvider),
        CodingTool.Codex => CodexAuthFile.ReadLoginStatus(account.ConfigFolderPath, timeProvider),
        _ => throw new ArgumentOutOfRangeException(nameof(account), account.CodingTool, null),
    };

    private void SetUsage(string configFolderPath, Func<AccountUsage, AccountUsage> change)
    {
        var current = usageByConfigFolderPath.GetValueOrDefault(configFolderPath) ?? new AccountUsage();
        usageByConfigFolderPath[configFolderPath] = change(current);
        UsageChanged?.Invoke();
    }

    private List<string> ShownConfigFolderPaths() =>
        accountStore.ShownAccounts.Select(account => account.ConfigFolderPath).ToList();

    private void OnAccountsChanged()
    {
        var newShownConfigFolderPaths = ShownConfigFolderPaths();
        if (newShownConfigFolderPaths.SequenceEqual(shownConfigFolderPaths, StringComparer.OrdinalIgnoreCase))
        {
            return;
        }
        shownConfigFolderPaths = newShownConfigFolderPaths;
        ShownAccountsRefresh = RefreshAsync();
        ShownAccountsRefreshStarted?.Invoke(ShownAccountsRefresh);
    }
}
