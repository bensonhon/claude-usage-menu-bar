using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class ClaudeCredentialsFileTests
{
    private static readonly FixedTimeProvider Now = new(new DateTimeOffset(2026, 11, 3, 20, 0, 0, TimeSpan.Zero));

    [Fact]
    public void ReadsTheAccessTokenAndCapitalizedPlanName()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", Now.UtcNow.AddHours(1).ToUnixTimeMilliseconds(), "max"), ".claude", ".credentials.json");

        Assert.Equal(new ClaudeLoginToken("token-1", "Max"), ClaudeCredentialsFile.ReadLoginToken(configFolderPath, Now));
        Assert.Equal(LoginStatus.Found, ClaudeCredentialsFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void PlanNameDefaultsToProWithoutASubscriptionType()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", subscriptionType: null), ".claude", ".credentials.json");

        Assert.Equal("Pro", ClaudeCredentialsFile.ReadLoginToken(configFolderPath, Now).PlanName);
    }

    [Fact]
    public void MissingOrEmptyFileIsNotFound()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");

        Assert.Equal(LoginStatus.NotFound, ClaudeCredentialsFile.ReadLoginStatus(configFolderPath, Now));
        Assert.Equal(LoginStatus.NotFound, ClaudeCredentialsFile.ReadLoginStatus(Path.Combine(home.Path, "missing"), Now));
        home.WriteFile("  \n", ".claude", ".credentials.json");
        Assert.Equal(LoginStatus.NotFound, ClaudeCredentialsFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void ExpiredTokenIsTokenExpired()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", Now.UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()), ".claude", ".credentials.json");

        var error = Assert.Throws<UsageException>(() => ClaudeCredentialsFile.ReadLoginToken(configFolderPath, Now));
        Assert.Equal(LoginStatus.TokenExpired, error.LoginStatus);
    }

    [Theory]
    [InlineData("{not json")]
    [InlineData("""{"other":{}}""")]
    [InlineData("""{"claudeAiOauth":{"refreshToken":"x"}}""")]
    public void UnparseableCredentialsAreUnreadable(string fileText)
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(fileText, ".claude", ".credentials.json");

        Assert.Equal(LoginStatus.Unreadable, ClaudeCredentialsFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void LoginProblemsAreTheThreeBadStatuses()
    {
        Assert.False(LoginStatus.NotChecked.IsLoginProblem());
        Assert.False(LoginStatus.Found.IsLoginProblem());
        Assert.True(LoginStatus.TokenExpired.IsLoginProblem());
        Assert.True(LoginStatus.NotFound.IsLoginProblem());
        Assert.True(LoginStatus.Unreadable.IsLoginProblem());
    }
}
