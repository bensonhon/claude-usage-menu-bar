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
    private readonly JsonFile<List<Account>> accountsFile;
    private readonly string homeFolderPath;
    private List<Account> accounts;

    public event Action? AccountsChanged;

    public AccountStore(string accountsFilePath, string homeFolderPath)
    {
        accountsFile = new JsonFile<List<Account>>(accountsFilePath);
        this.homeFolderPath = homeFolderPath;
        accounts = AccountsIncludingDefault(accountsFile.Load() ?? [], homeFolderPath);
    }

    public IReadOnlyList<Account> Accounts => accounts;

    public IReadOnlyList<Account> ShownAccounts => accounts.Where(account => account.IsShownInTray).ToList();

    public Account? SelectedAccount(string? selectedConfigFolderPath)
    {
        var shownAccounts = ShownAccounts;
        return shownAccounts.FirstOrDefault(account => selectedConfigFolderPath is not null && Account.IsSamePath(account.ConfigFolderPath, selectedConfigFolderPath))
            ?? shownAccounts.FirstOrDefault();
    }

    public int PositionOf(Account account) =>
        Math.Max(0, accounts.FindIndex(candidate => Account.IsSamePath(candidate.ConfigFolderPath, account.ConfigFolderPath)));

    public void AddFoundConfigFolders(IEnumerable<string> foundConfigFolderPaths, CodingTool codingTool)
    {
        var newAccounts = foundConfigFolderPaths
            .Where(path => !accounts.Any(account => Account.IsSamePath(account.ConfigFolderPath, path)))
            .Select(path => new Account(path, Account.DefaultLabel(path), IsShownInTray: true, IsFoundAutomatically: true, codingTool))
            .ToList();
        if (newAccounts.Count > 0)
        {
            Update(current => current.Concat(newAccounts).ToList());
        }
    }

    public void AddConfigFolder(string typedPath, string label, Func<string, bool> isExistingFolder)
    {
        var configFolderPath = Account.NormalizedConfigFolderPath(typedPath, homeFolderPath);
        if (!Account.IsFullPath(configFolderPath))
        {
            throw new AddConfigFolderException(AddConfigFolderError.PathNotAbsolute);
        }
        if (accounts.Any(account => Account.IsSamePath(account.ConfigFolderPath, configFolderPath)))
        {
            throw new AddConfigFolderException(AddConfigFolderError.AlreadyAdded);
        }
        if (!isExistingFolder(configFolderPath))
        {
            throw new AddConfigFolderException(AddConfigFolderError.FolderNotFound);
        }
        var trimmedLabel = label.Trim();
        var account = new Account(
            configFolderPath,
            trimmedLabel.Length == 0 ? Account.DefaultLabel(configFolderPath) : trimmedLabel,
            IsShownInTray: true,
            IsFoundAutomatically: false,
            CodingTool.ClaudeCode);
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

    public bool IsRemovable(Account account) =>
        !account.IsFoundAutomatically
        && !Account.IsSamePath(account.ConfigFolderPath, Account.DefaultConfigFolderPath(homeFolderPath));

    public void Remove(string configFolderPath)
    {
        var index = IndexOf(configFolderPath);
        if (index >= 0 && IsRemovable(accounts[index]))
        {
            Update(current => current.Where((_, position) => position != index).ToList());
        }
    }

    public static List<Account> AccountsIncludingDefault(List<Account> savedAccounts, string homeFolderPath)
    {
        var defaultConfigFolderPath = Account.DefaultConfigFolderPath(homeFolderPath);
        if (savedAccounts.Any(account => Account.IsSamePath(account.ConfigFolderPath, defaultConfigFolderPath)))
        {
            return savedAccounts;
        }
        var defaultAccount = new Account(
            defaultConfigFolderPath,
            Account.DefaultLabel(defaultConfigFolderPath),
            IsShownInTray: true,
            IsFoundAutomatically: false,
            CodingTool.ClaudeCode);
        return [defaultAccount, .. savedAccounts];
    }

    private int IndexOf(string configFolderPath) =>
        accounts.FindIndex(account => Account.IsSamePath(account.ConfigFolderPath, configFolderPath));

    private void Replace(string configFolderPath, Func<Account, Account> change)
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

    private static List<Account> Swapped(List<Account> current, int firstIndex, int secondIndex)
    {
        var swapped = current.ToList();
        (swapped[firstIndex], swapped[secondIndex]) = (swapped[secondIndex], swapped[firstIndex]);
        return swapped;
    }

    private void Update(Func<List<Account>, List<Account>> change)
    {
        accounts = change(accounts);
        accountsFile.Save(accounts);
        AccountsChanged?.Invoke();
    }
}
