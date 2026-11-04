using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public sealed class FixedTimeProvider : TimeProvider
{
    private readonly TimeZoneInfo localTimeZone;

    public FixedTimeProvider(DateTimeOffset utcNow, TimeZoneInfo? localTimeZone = null)
    {
        UtcNow = utcNow;
        this.localTimeZone = localTimeZone ?? TimeZoneInfo.Utc;
    }

    public DateTimeOffset UtcNow { get; set; }

    public override DateTimeOffset GetUtcNow() => UtcNow;

    public override TimeZoneInfo LocalTimeZone => localTimeZone;
}

public sealed class TemporaryFolder : IDisposable
{
    public TemporaryFolder()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "ClaudeUsageTray.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public string CreateFolder(params string[] parts)
    {
        var folderPath = System.IO.Path.Combine([Path, .. parts]);
        Directory.CreateDirectory(folderPath);
        return folderPath;
    }

    public string WriteFile(string text, params string[] parts)
    {
        var filePath = System.IO.Path.Combine([Path, .. parts]);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(filePath)!);
        File.WriteAllText(filePath, text);
        return filePath;
    }

    public void Dispose()
    {
        Directory.Delete(Path, recursive: true);
    }
}

public sealed class FakeUsageApi : IUsageApi
{
    public List<string> RequestedAccessTokens { get; } = [];
    public Func<string, UsageResponse> Respond { get; set; } = _ => UsageResponse.Decode("""{"five_hour":{"utilization":40,"resets_at":"2026-11-03T20:00:00Z"}}""");

    public Task<UsageResponse> FetchUsageAsync(string accessToken)
    {
        RequestedAccessTokens.Add(accessToken);
        return Task.FromResult(Respond(accessToken));
    }
}

public static class Credentials
{
    public static string Json(string accessToken, long? expiresAtMilliseconds = null, string? subscriptionType = "max")
    {
        var oauth = new Dictionary<string, object> { ["accessToken"] = accessToken, ["refreshToken"] = "refresh" };
        if (expiresAtMilliseconds is { } expiresAt)
        {
            oauth["expiresAt"] = expiresAt;
        }
        if (subscriptionType is not null)
        {
            oauth["subscriptionType"] = subscriptionType;
        }
        return System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, object> { ["claudeAiOauth"] = oauth });
    }
}
