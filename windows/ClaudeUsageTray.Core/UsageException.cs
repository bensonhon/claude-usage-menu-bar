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
    LoginNotFound,
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

    public static UsageException LoginNotFound(CodingTool codingTool) => new(UsageErrorKind.LoginNotFound, codingTool switch
    {
        CodingTool.ClaudeCode => "Claude Code credentials not found in .credentials.json. Make sure you're logged in to Claude Code.",
        CodingTool.Codex => "No ChatGPT login found in Codex's auth.json. Sign in to Codex with ChatGPT.",
        _ => throw new ArgumentOutOfRangeException(nameof(codingTool), codingTool, null),
    });

    public static UsageException TokenExpired(CodingTool codingTool) => new(UsageErrorKind.TokenExpired,
        $"{codingTool.Name()} login token expired. Use {codingTool.Name()} with this account once to refresh it.");

    public static UsageException InvalidToken(CodingTool codingTool, Exception? innerException = null) => new(UsageErrorKind.InvalidToken, codingTool switch
    {
        CodingTool.ClaudeCode => "Could not parse OAuth token from .credentials.json.",
        CodingTool.Codex => "Could not read the ChatGPT login token from Codex's auth.json.",
        _ => throw new ArgumentOutOfRangeException(nameof(codingTool), codingTool, null),
    }, innerException);

    public static UsageException NetworkError(string message, Exception? innerException = null) =>
        new(UsageErrorKind.NetworkError, $"Network error: {message}", innerException);

    public LoginStatus? LoginStatus => Kind switch
    {
        UsageErrorKind.LoginNotFound => Core.LoginStatus.NotFound,
        UsageErrorKind.TokenExpired => Core.LoginStatus.TokenExpired,
        UsageErrorKind.InvalidToken => Core.LoginStatus.Unreadable,
        _ => null,
    };
}
