using System.Text;
using System.Text.Json;

namespace ClaudeUsageTray.Core;

public sealed record CodexLoginToken(string AccessToken, string ChatGPTAccountId);

public static class CodexAuthFile
{
    public const string FileName = "auth.json";

    public static string PathFor(string configFolderPath) => Path.Combine(configFolderPath, FileName);

    public static bool Exists(string configFolderPath) => File.Exists(PathFor(configFolderPath));

    public static CodexLoginToken ReadLoginToken(string configFolderPath, TimeProvider timeProvider)
    {
        string authFileText;
        try
        {
            authFileText = File.ReadAllText(PathFor(configFolderPath));
        }
        catch (FileNotFoundException)
        {
            throw UsageException.LoginNotFound(CodingTool.Codex);
        }
        catch (DirectoryNotFoundException)
        {
            throw UsageException.LoginNotFound(CodingTool.Codex);
        }
        catch (IOException error)
        {
            throw UsageException.InvalidToken(CodingTool.Codex, error);
        }
        catch (UnauthorizedAccessException error)
        {
            throw UsageException.InvalidToken(CodingTool.Codex, error);
        }
        return LoginTokenFrom(authFileText, timeProvider);
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

    public static CodexLoginToken LoginTokenFrom(string authFileText, TimeProvider timeProvider)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(authFileText);
        }
        catch (JsonException error)
        {
            throw UsageException.InvalidToken(CodingTool.Codex, error);
        }
        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("tokens", out var tokens)
                || tokens.ValueKind != JsonValueKind.Object
                || GetString(tokens, "access_token") is not { Length: > 0 } accessToken
                || GetString(tokens, "account_id") is not { Length: > 0 } chatGPTAccountId)
            {
                throw UsageException.LoginNotFound(CodingTool.Codex);
            }
            if (AccessTokenExpiry(accessToken) is not { } accessTokenExpiry)
            {
                throw UsageException.InvalidToken(CodingTool.Codex);
            }
            if (accessTokenExpiry < timeProvider.GetUtcNow())
            {
                throw UsageException.TokenExpired(CodingTool.Codex);
            }
            return new CodexLoginToken(accessToken, chatGPTAccountId);
        }
    }

    public static DateTimeOffset? AccessTokenExpiry(string accessToken)
    {
        var tokenParts = accessToken.Split('.');
        if (tokenParts.Length != 3)
        {
            return null;
        }
        var claimsBase64 = tokenParts[1].Replace('-', '+').Replace('_', '/');
        claimsBase64 += new string('=', (4 - claimsBase64.Length % 4) % 4);
        try
        {
            using var claims = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(claimsBase64)));
            if (claims.RootElement.ValueKind == JsonValueKind.Object
                && claims.RootElement.TryGetProperty("exp", out var expiry)
                && expiry.ValueKind == JsonValueKind.Number)
            {
                return DateTimeOffset.FromUnixTimeSeconds((long)expiry.GetDouble());
            }
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? GetString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
