using System.Text.Json;

namespace ClaudeUsageTray.Core;

public sealed class CodexUsageResponse
{
    private CodexUsageResponse(string planName)
    {
        PlanName = planName;
    }

    public Dictionary<string, UsageWindow> Windows { get; } = new();
    public string PlanName { get; }

    public static CodexUsageResponse Decode(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException error)
        {
            throw new UsageException(UsageErrorKind.NetworkError, "Network error: Invalid JSON response", error);
        }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                throw new UsageException(UsageErrorKind.NetworkError, "Network error: Invalid JSON response");
            }
            if (!root.TryGetProperty("plan_type", out var planType) || planType.ValueKind != JsonValueKind.String)
            {
                throw new UsageException(UsageErrorKind.NetworkError, "Network error: Codex usage reply has no plan_type");
            }
            if (!root.TryGetProperty("rate_limit", out var rateLimit) || rateLimit.ValueKind != JsonValueKind.Object)
            {
                throw new UsageException(UsageErrorKind.NetworkError, "Network error: Codex usage reply has no rate_limit");
            }
            var response = new CodexUsageResponse(PlanNameFor(planType.GetString()!));
            foreach (var rateLimitWindowName in new[] { "primary_window", "secondary_window" })
            {
                if (!rateLimit.TryGetProperty(rateLimitWindowName, out var rateLimitWindow) || rateLimitWindow.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }
                if (GetNumber(rateLimitWindow, "used_percent") is not { } usedPercent
                    || GetNumber(rateLimitWindow, "limit_window_seconds") is not { } limitWindowSeconds)
                {
                    throw new UsageException(UsageErrorKind.NetworkError,
                        $"Network error: Codex usage reply has a {rateLimitWindowName} without used_percent or limit_window_seconds");
                }
                var resetDate = GetNumber(rateLimitWindow, "reset_at") is { } resetAtSeconds
                    ? DateTimeOffset.FromUnixTimeSeconds((long)resetAtSeconds)
                    : (DateTimeOffset?)null;
                response.Windows[WindowKey((long)limitWindowSeconds)] = new UsageWindow(usedPercent, resetDate);
            }
            return response;
        }
    }

    public static string WindowKey(long limitWindowSeconds) => limitWindowSeconds switch
    {
        5 * 60 * 60 => "five_hour",
        7 * 24 * 60 * 60 => "seven_day",
        _ => $"{limitWindowSeconds / 3600}_hour",
    };

    public const string SelfServePlanTypePrefix = "self_serve_";

    public static string PlanNameFor(string planType)
    {
        var planTypeWithoutSelfServe = planType.StartsWith(SelfServePlanTypePrefix, StringComparison.Ordinal)
            ? planType[SelfServePlanTypePrefix.Length..]
            : planType;
        return string.Join(' ', planTypeWithoutSelfServe.Split('_', StringSplitOptions.RemoveEmptyEntries)
            .Select(word => char.ToUpperInvariant(word[0]) + word[1..].ToLowerInvariant()));
    }

    private static double? GetNumber(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;
}
