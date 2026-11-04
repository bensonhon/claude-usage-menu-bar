using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class CredentialsFileTests
{
    private static readonly FixedTimeProvider Now = new(new DateTimeOffset(2026, 11, 3, 20, 0, 0, TimeSpan.Zero));

    [Fact]
    public void ReadsTheAccessTokenAndCapitalizedPlanName()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", Now.UtcNow.AddHours(1).ToUnixTimeMilliseconds(), "max"), ".claude", ".credentials.json");

        Assert.Equal(new LoginToken("token-1", "Max"), CredentialsFile.ReadLoginToken(configFolderPath, Now));
        Assert.Equal(LoginStatus.Found, CredentialsFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void PlanNameDefaultsToProWithoutASubscriptionType()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", subscriptionType: null), ".claude", ".credentials.json");

        Assert.Equal("Pro", CredentialsFile.ReadLoginToken(configFolderPath, Now).PlanName);
    }

    [Fact]
    public void MissingOrEmptyFileIsNotFound()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");

        Assert.Equal(LoginStatus.NotFound, CredentialsFile.ReadLoginStatus(configFolderPath, Now));
        Assert.Equal(LoginStatus.NotFound, CredentialsFile.ReadLoginStatus(Path.Combine(home.Path, "missing"), Now));
        home.WriteFile("  \n", ".claude", ".credentials.json");
        Assert.Equal(LoginStatus.NotFound, CredentialsFile.ReadLoginStatus(configFolderPath, Now));
    }

    [Fact]
    public void ExpiredTokenIsTokenExpired()
    {
        using var home = new TemporaryFolder();
        var configFolderPath = home.CreateFolder(".claude");
        home.WriteFile(Credentials.Json("token-1", Now.UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()), ".claude", ".credentials.json");

        var error = Assert.Throws<UsageException>(() => CredentialsFile.ReadLoginToken(configFolderPath, Now));
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

        Assert.Equal(LoginStatus.Unreadable, CredentialsFile.ReadLoginStatus(configFolderPath, Now));
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
