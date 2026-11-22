using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsageTray.Core;

public sealed record ClaudeLoginToken(string AccessToken, string PlanName);

public static class ClaudeCredentialsFile
{
    public const string FileName = ".credentials.json";

    public static string PathFor(string configFolderPath) => Path.Combine(configFolderPath, FileName);

    public static bool Exists(string configFolderPath) => File.Exists(PathFor(configFolderPath));

    public static ClaudeLoginToken ReadLoginToken(string configFolderPath, TimeProvider timeProvider)
    {
        string rawText;
        try
        {
            rawText = File.ReadAllText(PathFor(configFolderPath)).Trim();
        }
        catch (FileNotFoundException)
        {
            throw UsageException.LoginNotFound(CodingTool.ClaudeCode);
        }
        catch (DirectoryNotFoundException)
        {
            throw UsageException.LoginNotFound(CodingTool.ClaudeCode);
        }
        catch (IOException error)
        {
            throw UsageException.InvalidToken(CodingTool.ClaudeCode, error);
        }
        catch (UnauthorizedAccessException error)
        {
            throw UsageException.InvalidToken(CodingTool.ClaudeCode, error);
        }
        if (rawText.Length == 0)
        {
            throw UsageException.LoginNotFound(CodingTool.ClaudeCode);
        }

        OAuthCredentials? credentials;
        try
        {
            credentials = JsonSerializer.Deserialize<OAuthCredentials>(rawText);
        }
        catch (JsonException error)
        {
            throw UsageException.InvalidToken(CodingTool.ClaudeCode, error);
        }
        if (credentials?.ClaudeAiOauth is not { AccessToken: { Length: > 0 } accessToken } oauth)
        {
            throw UsageException.InvalidToken(CodingTool.ClaudeCode);
        }
        if (oauth.ExpiresAt is { } expiresAt && expiresAt < timeProvider.GetUtcNow().ToUnixTimeMilliseconds())
        {
            throw UsageException.TokenExpired(CodingTool.ClaudeCode);
        }
        return new ClaudeLoginToken(accessToken, PlanNameFor(oauth.SubscriptionType));
    }

    public static LoginStatus ReadLoginStatus(string configFolderPath, TimeProvider timeProvider)
    {
        try
        {
            ReadLoginToken(configFolderPath, timeProvider);
            return LoginStatus.Found;
        }
        catch (UsageException error)
        {
            return error.LoginStatus ?? LoginStatus.Unreadable;
        }
    }

    private static string PlanNameFor(string? subscriptionType)
    {
        if (string.IsNullOrEmpty(subscriptionType))
        {
            return "Pro";
        }
        return string.Join(' ', subscriptionType.Split(' ').Select(word =>
            word.Length == 0 ? word : char.ToUpperInvariant(word[0]) + word[1..].ToLowerInvariant()));
    }

    private sealed class OAuthCredentials
    {
        [JsonPropertyName("claudeAiOauth")]
        public OAuthToken? ClaudeAiOauth { get; init; }
    }

    private sealed class OAuthToken
    {
        [JsonPropertyName("accessToken")]
        public string? AccessToken { get; init; }

        [JsonPropertyName("expiresAt")]
        public double? ExpiresAt { get; init; }

        [JsonPropertyName("subscriptionType")]
        public string? SubscriptionType { get; init; }
    }
}
