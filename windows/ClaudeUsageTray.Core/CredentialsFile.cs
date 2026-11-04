using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsageTray.Core;

public enum LoginStatus
{
    NotChecked,
    Found,
    TokenExpired,
    NotFound,
    Unreadable,
}

public static class LoginStatusExtensions
{
    public static bool IsLoginProblem(this LoginStatus loginStatus) =>
        loginStatus is LoginStatus.TokenExpired or LoginStatus.NotFound or LoginStatus.Unreadable;
}

public enum UsageErrorKind
{
    CredentialsFileNotFound,
    TokenExpired,
    InvalidToken,
    NetworkError,
}

public sealed class UsageException : Exception
{
    public UsageErrorKind Kind { get; }

    public UsageException(UsageErrorKind kind, string message, Exception? innerException = null)
        : base(message, innerException)
    {
        Kind = kind;
    }

    public static UsageException CredentialsFileNotFound() => new(UsageErrorKind.CredentialsFileNotFound,
        "Claude Code credentials not found in .credentials.json. Make sure you're logged in to Claude Code.");

    public static UsageException TokenExpired() => new(UsageErrorKind.TokenExpired,
        "Claude Code login token expired. Use Claude Code with this account once to refresh it.");

    public static UsageException InvalidToken(Exception? innerException = null) => new(UsageErrorKind.InvalidToken,
        "Could not parse OAuth token from .credentials.json.", innerException);

    public static UsageException NetworkError(string message, Exception? innerException = null) =>
        new(UsageErrorKind.NetworkError, $"Network error: {message}", innerException);

    public LoginStatus? LoginStatus => Kind switch
    {
        UsageErrorKind.CredentialsFileNotFound => Core.LoginStatus.NotFound,
        UsageErrorKind.TokenExpired => Core.LoginStatus.TokenExpired,
        UsageErrorKind.InvalidToken => Core.LoginStatus.Unreadable,
        _ => null,
    };
}

public sealed record LoginToken(string AccessToken, string PlanName);

public static class CredentialsFile
{
    public const string FileName = ".credentials.json";

    public static string PathFor(string configFolderPath) => Path.Combine(configFolderPath, FileName);

    public static bool Exists(string configFolderPath) => File.Exists(PathFor(configFolderPath));

    public static LoginToken ReadLoginToken(string configFolderPath, TimeProvider timeProvider)
    {
        string rawText;
        try
        {
            rawText = File.ReadAllText(PathFor(configFolderPath)).Trim();
        }
        catch (FileNotFoundException)
        {
            throw UsageException.CredentialsFileNotFound();
        }
        catch (DirectoryNotFoundException)
        {
            throw UsageException.CredentialsFileNotFound();
        }
        catch (IOException error)
        {
            throw UsageException.InvalidToken(error);
        }
        catch (UnauthorizedAccessException error)
        {
            throw UsageException.InvalidToken(error);
        }
        if (rawText.Length == 0)
        {
            throw UsageException.CredentialsFileNotFound();
        }

        OAuthCredentials? credentials;
        try
        {
            credentials = JsonSerializer.Deserialize<OAuthCredentials>(rawText);
        }
        catch (JsonException error)
        {
            throw UsageException.InvalidToken(error);
        }
        if (credentials?.ClaudeAiOauth is not { AccessToken: { Length: > 0 } accessToken } oauth)
        {
            throw UsageException.InvalidToken();
        }
        if (oauth.ExpiresAt is { } expiresAt && expiresAt < timeProvider.GetUtcNow().ToUnixTimeMilliseconds())
        {
            throw UsageException.TokenExpired();
        }
        return new LoginToken(accessToken, PlanNameFor(oauth.SubscriptionType));
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
