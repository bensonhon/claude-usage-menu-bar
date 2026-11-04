using System.Text.Json;

namespace ClaudeUsageTray.Core;

public sealed record ExtraUsage(bool IsEnabled, double? UsedCredits, double? MonthlyLimit);

public sealed class UsageResponse
{
    public Dictionary<string, UsageWindow> Windows { get; } = new();
    public ExtraUsage? ExtraUsage { get; private set; }

    public static UsageResponse Decode(string json)
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
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new UsageException(UsageErrorKind.NetworkError, "Network error: Invalid JSON response");
            }
            var response = new UsageResponse();
            foreach (var property in document.RootElement.EnumerateObject())
            {
                if (property.Value.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }
                if (property.Name == "extra_usage")
                {
                    response.ExtraUsage = new ExtraUsage(
                        GetBool(property.Value, "is_enabled") ?? false,
                        GetDouble(property.Value, "used_credits"),
                        GetDouble(property.Value, "monthly_limit"));
                    continue;
                }
                if (GetDouble(property.Value, "utilization") is not { } utilization)
                {
                    continue;
                }
                response.Windows[property.Name] = new UsageWindow(utilization, GetString(property.Value, "resets_at"));
            }
            return response;
        }
    }

    private static double? GetDouble(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;

    private static bool? GetBool(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False ? value.GetBoolean() : null;

    private static string? GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}

public sealed record WindowDisplayInfo(string Key, string Label, double Utilization, double Remaining, UsageWindow Window)
{
    public static WindowDisplayInfo From(string key, UsageWindow window) =>
        new(key, LabelForKey(key), window.Utilization, window.Remaining, window);

    public static string LabelForKey(string key) => key switch
    {
        "five_hour" => "Session (5h)",
        "seven_day" => "Weekly (7d)",
        "seven_day_sonnet" => "Sonnet (7d)",
        "seven_day_opus" => "Opus (7d)",
        "seven_day_haiku" => "Haiku (7d)",
        "seven_day_cowork" => "Cowork (7d)",
        "seven_day_omelette" => "Omelette (7d)",
        "iguana_necktie" => "Priority Tier",
        "omelette_promotional" => "Omelette Promo",
        "seven_day_oauth_apps" => "OAuth Apps (7d)",
        _ => CapitalizeWords(key.Replace('_', ' ')),
    };

    private static string CapitalizeWords(string text) =>
        string.Join(' ', text.Split(' ').Select(word => word.Length == 0 ? word : char.ToUpperInvariant(word[0]) + word[1..].ToLowerInvariant()));
}
