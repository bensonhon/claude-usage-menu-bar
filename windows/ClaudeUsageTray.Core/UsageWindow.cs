using System.Globalization;

namespace ClaudeUsageTray.Core;

public sealed record UsageWindow(double Utilization, string? ResetsAt)
{
    public double Remaining => Math.Max(0, Math.Min(100, 100 - Utilization));

    public DateTimeOffset? ResetDate
    {
        get
        {
            if (ResetsAt is null)
            {
                return null;
            }
            return DateTimeOffset.TryParse(ResetsAt, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var resetDate)
                ? resetDate
                : null;
        }
    }
}

public static class ResetClock
{
    public const string NoResetTime = "—";

    public static string ResetClockShort(UsageWindow? window, TimeProvider timeProvider)
    {
        var roundedResetTime = RoundedLocalResetTime(window, timeProvider);
        return roundedResetTime is null ? NoResetTime : FormatHour(roundedResetTime.Value);
    }

    public static string ResetClockString(UsageWindow? window, TimeProvider timeProvider)
    {
        var roundedResetTime = RoundedLocalResetTime(window, timeProvider);
        if (roundedResetTime is null)
        {
            return NoResetTime;
        }
        var resetTime = roundedResetTime.Value;
        var today = timeProvider.GetLocalNow().Date;
        if (resetTime.Date == today)
        {
            return FormatHour(resetTime);
        }
        if (resetTime.Date == today.AddDays(1))
        {
            return $"Tomorrow {FormatHour(resetTime)}";
        }
        return $"{resetTime.ToString("MMM d", CultureInfo.InvariantCulture)}, {resetTime.ToString("%h", CultureInfo.InvariantCulture)}{AmPm(resetTime)}";
    }

    private static DateTime? RoundedLocalResetTime(UsageWindow? window, TimeProvider timeProvider)
    {
        if (window?.ResetDate is not { } resetDate)
        {
            return null;
        }
        var localResetTime = TimeZoneInfo.ConvertTime(resetDate, timeProvider.LocalTimeZone).DateTime;
        var minute = localResetTime.Minute;
        return minute >= 30 ? localResetTime.AddMinutes(60 - minute) : localResetTime.AddMinutes(-minute);
    }

    private static string FormatHour(DateTime time)
    {
        var hour = time.ToString("%h", CultureInfo.InvariantCulture);
        return time.Minute == 0
            ? $"{hour}{AmPm(time)}"
            : $"{hour}:{time.ToString("mm", CultureInfo.InvariantCulture)}{AmPm(time)}";
    }

    private static string AmPm(DateTime time) => time.Hour < 12 ? "AM" : "PM";
}
