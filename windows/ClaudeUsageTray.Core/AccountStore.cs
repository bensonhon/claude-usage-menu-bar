namespace ClaudeUsageTray.Core;

public enum AddConfigFolderError
{
    PathNotAbsolute,
    FolderNotFound,
    AlreadyAdded,
}

public sealed class AddConfigFolderException : Exception
{
    public AddConfigFolderError Error { get; }

    public AddConfigFolderException(AddConfigFolderError error) : base(DescriptionFor(error))
    {
        Error = error;
    }

    public static string DescriptionFor(AddConfigFolderError error) => error switch
    {
        AddConfigFolderError.PathNotAbsolute => "Use a full path, like ~\\.claude-work.",
        AddConfigFolderError.FolderNotFound => "That folder does not exist.",
        AddConfigFolderError.AlreadyAdded => "That folder is already in the list.",
        _ => throw new ArgumentOutOfRangeException(nameof(error), error, null),
    };
}

public sealed class AccountStore
{
    private readonly JsonFile<List<ClaudeAccount>> accountsFile;
    private readonly string homeFolderPath;
    private List<ClaudeAccount> accounts;

    public event Action? AccountsChanged;

    public AccountStore(string accountsFilePath, string homeFolderPath)
    {
        accountsFile = new JsonFile<List<ClaudeAccount>>(accountsFilePath);
        this.homeFolderPath = homeFolderPath;
        accounts = AccountsIncludingDefault(accountsFile.Load() ?? [], homeFolderPath);
    }

    public IReadOnlyList<ClaudeAccount> Accounts => accounts;

    public IReadOnlyList<ClaudeAccount> ShownAccounts => accounts.Where(account => account.IsShownInTray).ToList();

    public ClaudeAccount? SelectedAccount(string? selectedConfigFolderPath)
    {
        var shownAccounts = ShownAccounts;
        return shownAccounts.FirstOrDefault(account => selectedConfigFolderPath is not null && ClaudeAccount.IsSamePath(account.ConfigFolderPath, selectedConfigFolderPath))
            ?? shownAccounts.FirstOrDefault();
    }

    public int PositionOf(ClaudeAccount account) =>
        Math.Max(0, accounts.FindIndex(candidate => ClaudeAccount.IsSamePath(candidate.ConfigFolderPath, account.ConfigFolderPath)));

    public void AddFoundConfigFolders(IEnumerable<string> foundConfigFolderPaths)
    {
        var newAccounts = foundConfigFolderPaths
            .Where(path => !accounts.Any(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, path)))
            .Select(path => new ClaudeAccount(path, ClaudeAccount.DefaultLabel(path), IsShownInTray: true, IsFoundAutomatically: true))
            .ToList();
        if (newAccounts.Count > 0)
        {
            Update(current => current.Concat(newAccounts).ToList());
        }
    }

    public void AddConfigFolder(string typedPath, string label, Func<string, bool> isExistingFolder)
    {
        var configFolderPath = ClaudeAccount.NormalizedConfigFolderPath(typedPath, homeFolderPath);
        if (!ClaudeAccount.IsFullPath(configFolderPath))
        {
            throw new AddConfigFolderException(AddConfigFolderError.PathNotAbsolute);
        }
        if (accounts.Any(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, configFolderPath)))
        {
            throw new AddConfigFolderException(AddConfigFolderError.AlreadyAdded);
        }
        if (!isExistingFolder(configFolderPath))
        {
            throw new AddConfigFolderException(AddConfigFolderError.FolderNotFound);
        }
        var trimmedLabel = label.Trim();
        var account = new ClaudeAccount(
            configFolderPath,
            trimmedLabel.Length == 0 ? ClaudeAccount.DefaultLabel(configFolderPath) : trimmedLabel,
            IsShownInTray: true,
            IsFoundAutomatically: false);
        Update(current => current.Append(account).ToList());
    }

    public void SetShownInTray(bool isShownInTray, string configFolderPath) =>
        Replace(configFolderPath, account => account with { IsShownInTray = isShownInTray });

    public void SetLabel(string label, string configFolderPath) =>
        Replace(configFolderPath, account => account with { Label = label });

    public void MoveUp(string configFolderPath)
    {
        var index = IndexOf(configFolderPath);
        if (index > 0)
        {
            Update(current => Swapped(current, index, index - 1));
        }
    }

    public void MoveDown(string configFolderPath)
    {
        var index = IndexOf(configFolderPath);
        if (index >= 0 && index < accounts.Count - 1)
        {
            Update(current => Swapped(current, index, index + 1));
        }
    }

    public bool IsRemovable(ClaudeAccount account) =>
        !account.IsFoundAutomatically
        && !ClaudeAccount.IsSamePath(account.ConfigFolderPath, ClaudeAccount.DefaultConfigFolderPath(homeFolderPath));

    public void Remove(string configFolderPath)
    {
        var index = IndexOf(configFolderPath);
        if (index >= 0 && IsRemovable(accounts[index]))
        {
            Update(current => current.Where((_, position) => position != index).ToList());
        }
    }

    public static List<ClaudeAccount> AccountsIncludingDefault(List<ClaudeAccount> savedAccounts, string homeFolderPath)
    {
        var defaultConfigFolderPath = ClaudeAccount.DefaultConfigFolderPath(homeFolderPath);
        if (savedAccounts.Any(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, defaultConfigFolderPath)))
        {
            return savedAccounts;
        }
        var defaultAccount = new ClaudeAccount(
            defaultConfigFolderPath,
            ClaudeAccount.DefaultLabel(defaultConfigFolderPath),
            IsShownInTray: true,
            IsFoundAutomatically: false);
        return [defaultAccount, .. savedAccounts];
    }

    private int IndexOf(string configFolderPath) =>
        accounts.FindIndex(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, configFolderPath));

    private void Replace(string configFolderPath, Func<ClaudeAccount, ClaudeAccount> change)
    {
        var index = IndexOf(configFolderPath);
        if (index < 0)
        {
            return;
        }
        Update(current =>
        {
            var changed = current.ToList();
            changed[index] = change(changed[index]);
            return changed;
        });
    }

    private static List<ClaudeAccount> Swapped(List<ClaudeAccount> current, int firstIndex, int secondIndex)
    {
        var swapped = current.ToList();
        (swapped[firstIndex], swapped[secondIndex]) = (swapped[secondIndex], swapped[firstIndex]);
        return swapped;
    }

    private void Update(Func<List<ClaudeAccount>, List<ClaudeAccount>> change)
    {
        accounts = change(accounts);
        accountsFile.Save(accounts);
        AccountsChanged?.Invoke();
    }
}
