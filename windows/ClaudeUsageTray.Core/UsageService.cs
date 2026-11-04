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
    public bool HasUsageData => Windows.Count > 0;

    public IReadOnlyList<WindowDisplayInfo> SecondaryWindows => Windows
        .Where(entry => entry.Key is not ("five_hour" or "seven_day"))
        .Select(entry => WindowDisplayInfo.From(entry.Key, entry.Value))
        .OrderBy(info => info.Label, StringComparer.Ordinal)
        .ToList();
}

public interface IUsageApi
{
    Task<UsageResponse> FetchUsageAsync(string accessToken);
}

public sealed class UsageApiClient : IUsageApi
{
    public static readonly Uri UsageApiUri = new("https://platform.claude.com/api/oauth/usage");

    private readonly HttpClient httpClient;

    public UsageApiClient(HttpClient httpClient)
    {
        this.httpClient = httpClient;
        this.httpClient.Timeout = TimeSpan.FromSeconds(15);
    }

    public async Task<UsageResponse> FetchUsageAsync(string accessToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, UsageApiUri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.TryAddWithoutValidation("User-Agent", "claude-code/2.x");

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
            return UsageResponse.Decode(body);
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

    public AccountUsage UsageFor(ClaudeAccount account) =>
        usageByConfigFolderPath.GetValueOrDefault(account.ConfigFolderPath) ?? new AccountUsage();

    public bool IsEveryShownAccountLoaded => accountStore.ShownAccounts.All(account => UsageFor(account).HasUsageData);

    public TimeSpan NextRefreshInterval => IsEveryShownAccountLoaded ? RefreshIntervalWithData : RefreshIntervalWhileWaitingForData;

    public async Task RefreshAsync(bool force = false)
    {
        var foundConfigFolderPaths = await Task.Run(() => FindConfigFoldersWithCredentialsFile(homeFolderPath));
        accountStore.AddFoundConfigFolders(foundConfigFolderPaths);
        await Task.WhenAll(accountStore.Accounts.ToList().Select(account => RefreshAsync(account, force)));
    }

    public static IReadOnlyList<string> FindConfigFoldersWithCredentialsFile(string homeFolderPath)
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
            .Where(folderPath => ClaudeAccount.IsConfigFolderName(Path.GetFileName(folderPath)))
            .Where(CredentialsFile.Exists)
            .OrderBy(folderPath => folderPath, StringComparer.Ordinal)
            .ToList();
    }

    private async Task RefreshAsync(ClaudeAccount account, bool force)
    {
        var configFolderPath = account.ConfigFolderPath;

        if (!account.IsShownInTray)
        {
            var loginStatus = await Task.Run(() => CredentialsFile.ReadLoginStatus(configFolderPath, timeProvider));
            SetUsage(configFolderPath, usage => usage with { LoginStatus = loginStatus });
            return;
        }

        var activityTask = Task.Run(() => TokenHistoryParser.ParseLocalTokenHistoryAsync(account.ProjectsFolderPath, timeProvider));

        var lastUpdated = usageByConfigFolderPath.GetValueOrDefault(configFolderPath)?.LastUpdated;
        var skipNetwork = !force && lastUpdated is { } updatedAt && timeProvider.GetUtcNow() - updatedAt < MinimumTimeBetweenFetches;

        if (!skipNetwork)
        {
            SetUsage(configFolderPath, usage => usage with { LoadState = new UsageLoadState.Loading() });
            try
            {
                var loginToken = await Task.Run(() => CredentialsFile.ReadLoginToken(configFolderPath, timeProvider));
                SetUsage(configFolderPath, usage => usage with { LoginStatus = LoginStatus.Found });
                var response = await usageApi.FetchUsageAsync(loginToken.AccessToken);
                SetUsage(configFolderPath, usage => usage with
                {
                    Windows = response.Windows,
                    ExtraUsage = response.ExtraUsage,
                    PlanName = loginToken.PlanName,
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
