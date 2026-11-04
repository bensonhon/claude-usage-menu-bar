namespace ClaudeUsageTray.Core;

public sealed class AppSettings
{
    private readonly JsonFile<SavedSettings> settingsFile;
    private SavedSettings saved;

    public event Action? SettingsChanged;

    public AppSettings(string settingsFilePath)
    {
        settingsFile = new JsonFile<SavedSettings>(settingsFilePath);
        saved = settingsFile.Load() ?? new SavedSettings();
    }

    public bool ShowLogo { get => saved.ShowLogo; set => Update(saved with { ShowLogo = value }); }
    public bool ShowResetTime { get => saved.ShowResetTime; set => Update(saved with { ShowResetTime = value }); }
    public bool DarkMode { get => saved.DarkMode; set => Update(saved with { DarkMode = value }); }
    public string? SelectedConfigFolderPath { get => saved.SelectedConfigFolderPath; set => Update(saved with { SelectedConfigFolderPath = value }); }
    public bool MultiAccountSimpleMode { get => saved.MultiAccountSimpleMode; set => Update(saved with { MultiAccountSimpleMode = value }); }

    private void Update(SavedSettings changed)
    {
        if (changed == saved)
        {
            return;
        }
        saved = changed;
        settingsFile.Save(saved);
        SettingsChanged?.Invoke();
    }

    public sealed record SavedSettings
    {
        public bool ShowLogo { get; init; } = true;
        public bool ShowResetTime { get; init; } = true;
        public bool DarkMode { get; init; } = true;
        public string? SelectedConfigFolderPath { get; init; }
        public bool MultiAccountSimpleMode { get; init; }
    }
}

public enum FlyoutAccountContent
{
    Standard,
    SimpleList,
}

public static class FlyoutAccountContentChooser
{
    public static FlyoutAccountContent Choose(bool multiAccountSimpleMode, int shownAccountCount) =>
        multiAccountSimpleMode && shownAccountCount > 1 ? FlyoutAccountContent.SimpleList : FlyoutAccountContent.Standard;
}

public enum SimpleModeWindow
{
    Session,
    Weekly,
}
