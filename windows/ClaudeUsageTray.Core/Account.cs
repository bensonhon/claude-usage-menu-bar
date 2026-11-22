using System.Text.Json.Serialization;

namespace ClaudeUsageTray.Core;

[JsonConverter(typeof(JsonStringEnumConverter<CodingTool>))]
public enum CodingTool
{
    ClaudeCode,
    Codex,
}

public static class CodingToolExtensions
{
    public static string Name(this CodingTool codingTool) => codingTool switch
    {
        CodingTool.ClaudeCode => "Claude Code",
        CodingTool.Codex => "Codex",
        _ => throw new ArgumentOutOfRangeException(nameof(codingTool), codingTool, null),
    };
}

public sealed record Account(string ConfigFolderPath, string Label, bool IsShownInTray, bool IsFoundAutomatically, CodingTool CodingTool = CodingTool.ClaudeCode)
{
    public const string ClaudeConfigFolderNamePrefix = ".claude";
    public const string CodexConfigFolderNamePrefix = ".codex";

    private static readonly char[] PathSeparators = ['\\', '/'];

    public string LabelOrFolderName
    {
        get
        {
            var trimmedLabel = Label.Trim();
            return trimmedLabel.Length == 0 ? DefaultLabel(ConfigFolderPath) : trimmedLabel;
        }
    }

    public string ProjectsFolderPath => Path.Combine(ConfigFolderPath, "projects");

    public static bool IsSamePath(string firstPath, string secondPath) =>
        string.Equals(firstPath, secondPath, StringComparison.OrdinalIgnoreCase);

    public static string DefaultConfigFolderPath(string homeFolderPath) => Path.Combine(homeFolderPath, ClaudeConfigFolderNamePrefix);

    public static bool IsClaudeConfigFolderName(string folderName) => folderName.StartsWith(ClaudeConfigFolderNamePrefix, StringComparison.OrdinalIgnoreCase);

    public static bool IsCodexConfigFolderName(string folderName) => folderName.StartsWith(CodexConfigFolderNamePrefix, StringComparison.OrdinalIgnoreCase);

    public static string NormalizedConfigFolderPath(string typedPath, string homeFolderPath)
    {
        var path = typedPath.Trim();
        if (path == "~")
        {
            path = homeFolderPath;
        }
        else if (path.StartsWith("~\\", StringComparison.Ordinal) || path.StartsWith("~/", StringComparison.Ordinal))
        {
            path = Path.Combine(homeFolderPath, path[2..]);
        }
        else if (path.StartsWith("%USERPROFILE%", StringComparison.OrdinalIgnoreCase))
        {
            var rest = path["%USERPROFILE%".Length..].TrimStart(PathSeparators);
            path = rest.Length == 0 ? homeFolderPath : Path.Combine(homeFolderPath, rest);
        }
        while (path.Length > 1 && PathSeparators.Contains(path[^1]) && !IsDriveRoot(path))
        {
            path = path[..^1];
        }
        return path;
    }

    public static bool IsFullPath(string path) => Path.IsPathFullyQualified(path);

    public static string DefaultLabel(string configFolderPath)
    {
        var folderName = LastPathComponent(configFolderPath);
        return folderName.StartsWith('.') ? folderName[1..] : folderName;
    }

    public static string DisplayPath(string configFolderPath, string homeFolderPath)
    {
        if (IsSamePath(configFolderPath, homeFolderPath))
        {
            return "~";
        }
        var homePrefix = homeFolderPath.TrimEnd(PathSeparators);
        if (configFolderPath.Length > homePrefix.Length
            && configFolderPath.StartsWith(homePrefix, StringComparison.OrdinalIgnoreCase)
            && PathSeparators.Contains(configFolderPath[homePrefix.Length]))
        {
            return "~" + configFolderPath[homePrefix.Length..];
        }
        return configFolderPath;
    }

    public static string LastPathComponent(string path)
    {
        var trimmedPath = path.TrimEnd(PathSeparators);
        var lastSeparatorIndex = trimmedPath.LastIndexOfAny(PathSeparators);
        return lastSeparatorIndex < 0 ? trimmedPath : trimmedPath[(lastSeparatorIndex + 1)..];
    }

    private static bool IsDriveRoot(string path) => path.Length == 3 && path[1] == ':' && PathSeparators.Contains(path[2]);
}
