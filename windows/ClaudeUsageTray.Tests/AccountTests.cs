using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class ClaudeAccountTests
{
    private static readonly string Home = Path.Combine(Path.GetTempPath(), "home");
    private static readonly char Separator = Path.DirectorySeparatorChar;

    [Theory]
    [InlineData("~")]
    [InlineData("  ~  ")]
    [InlineData("%USERPROFILE%")]
    public void TildeAndUserProfileMeanTheHomeFolder(string typedPath)
    {
        Assert.Equal(Home, ClaudeAccount.NormalizedConfigFolderPath(typedPath, Home));
    }

    [Theory]
    [InlineData("~\\.claude-work")]
    [InlineData("~/.claude-work")]
    [InlineData("%USERPROFILE%\\.claude-work")]
    [InlineData("%userprofile%/.claude-work\\")]
    public void HomeShortcutsExpandIntoTheHomeFolder(string typedPath)
    {
        Assert.Equal(Path.Combine(Home, ".claude-work"), ClaudeAccount.NormalizedConfigFolderPath(typedPath, Home));
    }

    [Fact]
    public void TrailingSeparatorsAreRemovedButADriveRootIsKept()
    {
        Assert.Equal("D:\\claude-team", ClaudeAccount.NormalizedConfigFolderPath("D:\\claude-team\\\\", Home));
        Assert.Equal("D:\\", ClaudeAccount.NormalizedConfigFolderPath("D:\\", Home));
    }

    [Fact]
    public void DefaultLabelDropsTheLeadingDot()
    {
        Assert.Equal("claude-work", ClaudeAccount.DefaultLabel("C:\\Users\\benson\\.claude-work"));
        Assert.Equal("team", ClaudeAccount.DefaultLabel("D:/team/"));
    }

    [Fact]
    public void DisplayPathShortensTheHomeFolderToTilde()
    {
        Assert.Equal("~", ClaudeAccount.DisplayPath(Home, Home));
        Assert.Equal($"~{Separator}.claude-work", ClaudeAccount.DisplayPath(Path.Combine(Home, ".claude-work"), Home));
        Assert.Equal(Home + "2", ClaudeAccount.DisplayPath(Home + "2", Home));
        Assert.Equal("D:\\team", ClaudeAccount.DisplayPath("D:\\team", Home));
    }

    [Fact]
    public void LabelOrFolderNameFallsBackToTheFolderName()
    {
        Assert.Equal("claude-work", new ClaudeAccount("C:\\Users\\b\\.claude-work", "   ", true, false).LabelOrFolderName);
        Assert.Equal("work", new ClaudeAccount("C:\\Users\\b\\.claude-work", " work ", true, false).LabelOrFolderName);
    }

    [Theory]
    [InlineData(".claude", true)]
    [InlineData(".claude-work", true)]
    [InlineData(".CLAUDE-old", true)]
    [InlineData("claude", false)]
    [InlineData(".config", false)]
    public void ConfigFolderNamesStartWithDotClaude(string folderName, bool expected)
    {
        Assert.Equal(expected, ClaudeAccount.IsConfigFolderName(folderName));
    }
}

public class AccountStoreTests
{
    [Fact]
    public void StartsWithTheDefaultAccountAndPersistsChanges()
    {
        using var folder = new TemporaryFolder();
        var accountsFilePath = Path.Combine(folder.Path, "settings", "accounts.json");
        var store = new AccountStore(accountsFilePath, folder.Path);
        var defaultPath = Path.Combine(folder.Path, ".claude");

        Assert.Equal([new ClaudeAccount(defaultPath, "claude", true, false)], store.Accounts);

        store.SetLabel("main", defaultPath);
        store.SetShownInTray(false, defaultPath);

        var reloaded = new AccountStore(accountsFilePath, folder.Path);
        Assert.Equal([new ClaudeAccount(defaultPath, "main", false, false)], reloaded.Accounts);
        Assert.Empty(reloaded.ShownAccounts);
    }

    [Fact]
    public void CorruptAccountsFileStartsFromTheDefaultAccount()
    {
        using var folder = new TemporaryFolder();
        var accountsFilePath = folder.WriteFile("{broken", "accounts.json");

        Assert.Single(new AccountStore(accountsFilePath, folder.Path).Accounts);
    }

    [Fact]
    public void FoundFoldersAreAddedOnceAndMarkedFoundAutomatically()
    {
        using var folder = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(folder.Path, "accounts.json"), folder.Path);
        var workPath = Path.Combine(folder.Path, ".claude-work");
        var changeCount = 0;
        store.AccountsChanged += () => changeCount++;

        store.AddFoundConfigFolders([Path.Combine(folder.Path, ".claude"), workPath]);
        store.AddFoundConfigFolders([workPath.ToUpperInvariant()]);

        Assert.Equal(2, store.Accounts.Count);
        Assert.Equal(new ClaudeAccount(workPath, "claude-work", true, true), store.Accounts[1]);
        Assert.Equal(1, changeCount);
        Assert.False(store.IsRemovable(store.Accounts[0]));
        Assert.False(store.IsRemovable(store.Accounts[1]));
    }

    [Fact]
    public void AddConfigFolderValidatesThePath()
    {
        using var folder = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(folder.Path, "accounts.json"), folder.Path);
        var teamPath = folder.CreateFolder("team");

        Assert.Equal(AddConfigFolderError.PathNotAbsolute,
            Assert.Throws<AddConfigFolderException>(() => store.AddConfigFolder("claude-x", "", Directory.Exists)).Error);
        Assert.Equal(AddConfigFolderError.AlreadyAdded,
            Assert.Throws<AddConfigFolderException>(() => store.AddConfigFolder("~/.claude", "", Directory.Exists)).Error);
        Assert.Equal(AddConfigFolderError.FolderNotFound,
            Assert.Throws<AddConfigFolderException>(() => store.AddConfigFolder("~/missing", "", Directory.Exists)).Error);

        store.AddConfigFolder(teamPath + Path.DirectorySeparatorChar, "  ", Directory.Exists);

        var added = store.Accounts[^1];
        Assert.Equal(new ClaudeAccount(teamPath, "team", true, false), added);
        Assert.True(store.IsRemovable(added));
        store.Remove(teamPath);
        Assert.Single(store.Accounts);
    }

    [Fact]
    public void MovesAccountsUpAndDownWithinBounds()
    {
        using var folder = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(folder.Path, "accounts.json"), folder.Path);
        var defaultPath = Path.Combine(folder.Path, ".claude");
        var workPath = Path.Combine(folder.Path, ".claude-work");
        store.AddFoundConfigFolders([workPath]);

        store.MoveUp(defaultPath);
        Assert.Equal([defaultPath, workPath], store.Accounts.Select(a => a.ConfigFolderPath));
        store.MoveDown(defaultPath);
        Assert.Equal([workPath, defaultPath], store.Accounts.Select(a => a.ConfigFolderPath));
        store.MoveDown(defaultPath);
        Assert.Equal([workPath, defaultPath], store.Accounts.Select(a => a.ConfigFolderPath));
        store.MoveUp(defaultPath);
        Assert.Equal([defaultPath, workPath], store.Accounts.Select(a => a.ConfigFolderPath));
        Assert.Equal(1, store.PositionOf(store.Accounts[1]));
    }

    [Fact]
    public void SelectedAccountIsTheSavedShownAccountOrElseTheFirstShownOne()
    {
        using var folder = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(folder.Path, "accounts.json"), folder.Path);
        var defaultPath = Path.Combine(folder.Path, ".claude");
        var workPath = Path.Combine(folder.Path, ".claude-work");
        store.AddFoundConfigFolders([workPath]);

        Assert.Equal(defaultPath, store.SelectedAccount(null)!.ConfigFolderPath);
        Assert.Equal(workPath, store.SelectedAccount(workPath.ToUpperInvariant())!.ConfigFolderPath);
        store.SetShownInTray(false, workPath);
        Assert.Equal(defaultPath, store.SelectedAccount(workPath)!.ConfigFolderPath);
        store.SetShownInTray(false, defaultPath);
        Assert.Null(store.SelectedAccount(workPath));
    }

    [Fact]
    public void RemoveIgnoresAccountsThatAreNotRemovable()
    {
        using var folder = new TemporaryFolder();
        var store = new AccountStore(Path.Combine(folder.Path, "accounts.json"), folder.Path);
        var workPath = Path.Combine(folder.Path, ".claude-work");
        store.AddFoundConfigFolders([workPath]);

        store.Remove(workPath);
        store.Remove(Path.Combine(folder.Path, ".claude"));

        Assert.Equal(2, store.Accounts.Count);
    }
}

public class AppSettingsTests
{
    [Fact]
    public void DefaultsMatchTheMacApp()
    {
        using var folder = new TemporaryFolder();
        var settings = new AppSettings(Path.Combine(folder.Path, "settings.json"));

        Assert.True(settings.ShowLogo);
        Assert.True(settings.ShowResetTime);
        Assert.True(settings.DarkMode);
        Assert.False(settings.MultiAccountSimpleMode);
        Assert.Null(settings.SelectedConfigFolderPath);
    }

    [Fact]
    public void ChangesArePersistedAndRaiseOneEventEach()
    {
        using var folder = new TemporaryFolder();
        var settingsFilePath = Path.Combine(folder.Path, "settings.json");
        var settings = new AppSettings(settingsFilePath);
        var changeCount = 0;
        settings.SettingsChanged += () => changeCount++;

        settings.DarkMode = false;
        settings.DarkMode = false;
        settings.ShowLogo = false;
        settings.SelectedConfigFolderPath = "C:\\x";
        settings.MultiAccountSimpleMode = true;

        var reloaded = new AppSettings(settingsFilePath);
        Assert.False(reloaded.DarkMode);
        Assert.False(reloaded.ShowLogo);
        Assert.True(reloaded.ShowResetTime);
        Assert.Equal("C:\\x", reloaded.SelectedConfigFolderPath);
        Assert.True(reloaded.MultiAccountSimpleMode);
        Assert.Equal(4, changeCount);
    }

    [Theory]
    [InlineData(true, 2, FlyoutAccountContent.SimpleList)]
    [InlineData(true, 1, FlyoutAccountContent.Standard)]
    [InlineData(false, 3, FlyoutAccountContent.Standard)]
    public void SimpleListNeedsSimpleModeAndMoreThanOneShownAccount(bool simpleMode, int shownCount, FlyoutAccountContent expected)
    {
        Assert.Equal(expected, FlyoutAccountContentChooser.Choose(simpleMode, shownCount));
    }
}
