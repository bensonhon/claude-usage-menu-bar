using System.Globalization;

namespace ClaudeUsageTray.Core;

public static class UsageColors
{
    public const string Green = "#22C55E";
    public const string Amber = "#F59E0B";
    public const string Red = "#EF4444";
    public const string Accent = "#E8732A";

    public static string? ForRemaining(double? remaining) => remaining switch
    {
        null => null,
        > 30 => Green,
        > 10 => Amber,
        _ => Red,
    };
}

public static class AccountColor
{
    public static readonly IReadOnlyList<string> Hexes = ["#60A5FA", "#C084FC", "#F9A8D4", "#67E8F9", "#FDBA74", "#BEF264"];

    public static string HexFor(int position) => Hexes[position % Hexes.Count];
}

public static class UsageText
{
    public static string PercentText(double? remaining) =>
        remaining is { } value ? $"{(int)value}%" : "?";

    public static string AccountTabTooltip(double? sessionRemaining, double? weeklyRemaining) =>
        $"Session {PercentText(sessionRemaining)} left · Weekly {PercentText(weeklyRemaining)} left";

    public static string FormatTokenCount(long count)
    {
        if (count >= 1_000_000)
        {
            return (count / 1_000_000.0).ToString("0.0", CultureInfo.InvariantCulture) + "M";
        }
        if (count >= 1_000)
        {
            return (count / 1_000.0).ToString("0.0", CultureInfo.InvariantCulture) + "K";
        }
        return count.ToString(CultureInfo.InvariantCulture);
    }

    public static string ShortModel(string model)
    {
        if (model.Contains("opus", StringComparison.Ordinal)) return "Opus";
        if (model.Contains("sonnet", StringComparison.Ordinal)) return "Sonnet";
        if (model.Contains("haiku", StringComparison.Ordinal)) return "Haiku";
        return model;
    }

    public static string ModelColorHex(string model)
    {
        if (model.Contains("opus", StringComparison.Ordinal)) return "#C084FC";
        if (model.Contains("sonnet", StringComparison.Ordinal)) return "#60A5FA";
        if (model.Contains("haiku", StringComparison.Ordinal)) return "#34D399";
        return UsageColors.Accent;
    }

    public static string RelativeTime(DateTimeOffset date, DateTimeOffset now)
    {
        var elapsedSeconds = (now - date).TotalSeconds;
        if (elapsedSeconds < 60) return "now";
        var minutes = (int)(elapsedSeconds / 60);
        if (minutes < 60) return $"{minutes}m";
        var hours = minutes / 60;
        if (hours < 24) return $"{hours}h";
        var days = hours / 24;
        if (days < 30) return $"{days}d";
        return $"{days / 30}mo";
    }

    public static string LastUpdatedText(DateTimeOffset lastUpdated, DateTimeOffset now)
    {
        var elapsedSeconds = Math.Max(0, (int)(now - lastUpdated).TotalSeconds);
        if (elapsedSeconds < 60) return $"Updated {elapsedSeconds} sec ago";
        var minutes = elapsedSeconds / 60;
        if (minutes < 60) return $"Updated {minutes} min ago";
        return $"Updated {minutes / 60} hr ago";
    }

    public static string FriendlyErrorMessage(string rawMessage)
    {
        var lowerMessage = rawMessage.ToLowerInvariant();
        if (lowerMessage.Contains("credentials") || lowerMessage.Contains("token") || lowerMessage.Contains("401"))
        {
            return "Requires Claude Code CLI. Sign in via claude to load usage data.";
        }
        return rawMessage;
    }

    public static string? LoginProblemText(LoginStatus loginStatus) => loginStatus switch
    {
        LoginStatus.TokenExpired => "Login token expired. Use Claude Code with this account once, and it comes back on the next refresh.",
        LoginStatus.NotFound => "No Claude Code login found for this folder. Sign in to Claude Code with this config folder.",
        LoginStatus.Unreadable => "Could not read this account's login from .credentials.json.",
        _ => null,
    };

    public static (string Text, string? ColorHex) LoginStatusChip(LoginStatus loginStatus) => loginStatus switch
    {
        LoginStatus.NotChecked => ("Checking…", null),
        LoginStatus.Found => ("Login found", UsageColors.Green),
        LoginStatus.TokenExpired => ("Token expired", UsageColors.Amber),
        LoginStatus.NotFound => ("No login found", null),
        LoginStatus.Unreadable => ("Login unreadable", UsageColors.Red),
        _ => throw new ArgumentOutOfRangeException(nameof(loginStatus), loginStatus, null),
    };

    public static string LoginFilePreview(string typedPath, string homeFolderPath)
    {
        var configFolderPath = ClaudeAccount.NormalizedConfigFolderPath(typedPath, homeFolderPath);
        return ClaudeAccount.IsFullPath(configFolderPath)
            ? $"Login file: {CredentialsFile.PathFor(configFolderPath)}"
            : "Type the folder you set as CLAUDE_CONFIG_DIR";
    }
}

public abstract record TrayIconEntry
{
    public sealed record Logo : TrayIconEntry;
    public sealed record AccountRing(ClaudeAccount Account, double? Remaining, string? AccountColorHex, string TooltipText) : TrayIconEntry;
}

public static class TrayIconPlan
{
    public const int MaximumTooltipLength = 127;

    public static IReadOnlyList<TrayIconEntry> Entries(AccountStore accountStore, UsageService usageService, bool showLogo, bool showResetTime, TimeProvider timeProvider)
    {
        var shownAccounts = accountStore.ShownAccounts;
        var isAccountColorShown = shownAccounts.Count > 1;
        var entries = new List<TrayIconEntry>();
        if (showLogo || shownAccounts.Count == 0)
        {
            entries.Add(new TrayIconEntry.Logo());
        }
        foreach (var account in shownAccounts)
        {
            var usage = usageService.UsageFor(account);
            entries.Add(new TrayIconEntry.AccountRing(
                account,
                usage.SessionWindow?.Remaining,
                isAccountColorShown ? AccountColor.HexFor(accountStore.PositionOf(account)) : null,
                TooltipText(account, usage, showResetTime, timeProvider)));
        }
        return entries;
    }

    public static string TooltipText(ClaudeAccount account, AccountUsage usage, bool showResetTime, TimeProvider timeProvider)
    {
        var lines = new List<string> { account.LabelOrFolderName };
        if (!usage.HasUsageData)
        {
            lines.Add(UsageText.LoginProblemText(usage.LoginStatus) is null ? "No usage data yet" : "Login problem: open for details");
        }
        else
        {
            lines.Add(WindowLine("Session", usage.SessionWindow, showResetTime ? ResetClock.ResetClockShort(usage.SessionWindow, timeProvider) : null));
            lines.Add(WindowLine("Weekly", usage.WeeklyWindow, showResetTime ? ResetClock.ResetClockString(usage.WeeklyWindow, timeProvider) : null));
        }
        var text = string.Join('\n', lines);
        return text.Length <= MaximumTooltipLength ? text : text[..(MaximumTooltipLength - 1)] + "…";
    }

    private static string WindowLine(string name, UsageWindow? window, string? resetTime)
    {
        var line = $"{name} {UsageText.PercentText(window?.Remaining)} left";
        return resetTime is null || resetTime == ResetClock.NoResetTime ? line : $"{line}, resets {resetTime}";
    }
}
