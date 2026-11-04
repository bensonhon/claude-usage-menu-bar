using System.Text;
using System.Text.Json;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray.Tests;

public class TokenHistoryParserTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 3, 20, 0, 0, TimeSpan.Zero);
    private static readonly FixedTimeProvider Clock = new(Now);

    private static string AssistantLine(DateTimeOffset timestamp, string sessionId = "s1", string cwd = "C:\\work\\alpha",
        string model = "claude-opus-5-5", string? messageId = "m1", int input = 10, int output = 20, int cacheWrite = 30, int cacheRead = 40)
    {
        var message = new Dictionary<string, object>
        {
            ["model"] = model,
            ["content"] = new[] { new Dictionary<string, string> { ["type"] = "text", ["text"] = "hi" } },
            ["usage"] = new Dictionary<string, int>
            {
                ["input_tokens"] = input,
                ["output_tokens"] = output,
                ["cache_creation_input_tokens"] = cacheWrite,
                ["cache_read_input_tokens"] = cacheRead,
            },
        };
        if (messageId is not null)
        {
            message["id"] = messageId;
        }
        return JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["type"] = "assistant",
            ["timestamp"] = timestamp.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", System.Globalization.CultureInfo.InvariantCulture),
            ["sessionId"] = sessionId,
            ["cwd"] = cwd,
            ["message"] = message,
        });
    }


    [Fact]
    public async Task MissingProjectsFolderGivesEmptyActivity()
    {
        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()), Clock);
        Assert.Equal(0, activity.TodayTokens);
        Assert.Empty(activity.RecentSessions);
    }

    [Fact]
    public async Task SumsTokensIntoTodayThreeDayAndSevenDayWindows()
    {
        using var projects = new TemporaryFolder();
        projects.WriteFile(string.Join('\n',
            AssistantLine(Now.AddHours(-1), messageId: "today"),
            AssistantLine(Now.AddDays(-2), messageId: "two-days-ago"),
            AssistantLine(Now.AddDays(-5), messageId: "five-days-ago"),
            AssistantLine(Now.AddDays(-8), messageId: "eight-days-ago")), "alpha", "s1.jsonl");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        Assert.Equal(100, activity.TodayTokens);
        Assert.Equal(200, activity.Last3DaysTokens);
        Assert.Equal(300, activity.Last7DaysTokens);
        Assert.Equal((10L, 20L, 30L, 40L), (activity.TodayInputTokens, activity.TodayOutputTokens, activity.TodayCacheCreationTokens, activity.TodayCacheReadTokens));
    }

    [Fact]
    public async Task RepeatedMessageIdsAreCountedOnce()
    {
        using var projects = new TemporaryFolder();
        projects.WriteFile(string.Join("\r\n",
            AssistantLine(Now.AddMinutes(-3), messageId: "same"),
            AssistantLine(Now.AddMinutes(-2), messageId: "same"),
            AssistantLine(Now.AddMinutes(-1), messageId: null)), "alpha", "s1.jsonl");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        Assert.Equal(200, activity.TodayTokens);
    }

    [Fact]
    public async Task SkipsBrokenLinesUserLinesHiddenFilesAndNonJsonlFiles()
    {
        using var projects = new TemporaryFolder();
        projects.WriteFile(string.Join('\n',
            "{broken",
            """{"type":"user","message":{"role":"user","content":"hello"}}""",
            AssistantLine(Now.AddMinutes(-1))), "alpha", "s1.jsonl");
        projects.WriteFile(AssistantLine(Now.AddMinutes(-1), messageId: "hidden"), ".hidden", "s2.jsonl");
        projects.WriteFile(AssistantLine(Now.AddMinutes(-1), messageId: "text"), "alpha", "notes.txt");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        Assert.Equal(100, activity.TodayTokens);
    }

    [Fact]
    public async Task FilesNotWrittenInTheLastTenDaysAreSkipped()
    {
        using var projects = new TemporaryFolder();
        var oldFilePath = projects.WriteFile(AssistantLine(Now.AddMinutes(-1)), "alpha", "old.jsonl");
        File.SetLastWriteTimeUtc(oldFilePath, Now.AddDays(-11).UtcDateTime);

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        Assert.Equal(0, activity.TodayTokens);
    }

    [Fact]
    public async Task OnlyTheTailOfALargeFileIsRead()
    {
        using var projects = new TemporaryFolder();
        var filler = new StringBuilder();
        var fillerLineCount = 0;
        while (filler.Length < TokenHistoryParser.TailBytesPerFile * 2)
        {
            filler.Append(AssistantLine(Now.AddMinutes(-30), messageId: $"filler-{fillerLineCount++:D6}", input: 1, output: 0, cacheWrite: 0, cacheRead: 0)).Append('\n');
        }
        filler.Append(AssistantLine(Now.AddMinutes(-1), messageId: "last"));
        projects.WriteFile(filler.ToString(), "alpha", "big.jsonl");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        var fillerLinesCounted = activity.TodayTokens - 100;
        Assert.InRange(fillerLinesCounted, 1, fillerLineCount / 2 + 1);
    }

    [Fact]
    public async Task RecentSessionsKeepTheLatestSessionPerProjectWithinTenDays()
    {
        using var projects = new TemporaryFolder();
        projects.WriteFile(AssistantLine(Now.AddHours(-5), "s1", "C:\\work\\alpha", "claude-sonnet-5-5", "a1"), "alpha", "s1.jsonl");
        projects.WriteFile(AssistantLine(Now.AddHours(-1), "s2", "C:\\work\\alpha\\", "claude-opus-5-5", "a2"), "alpha", "s2.jsonl");
        projects.WriteFile(AssistantLine(Now.AddHours(-3), "s3", "/Users/x/beta", "claude-haiku-5-5", "b1"), "beta", "s3.jsonl");
        projects.WriteFile(AssistantLine(Now.AddDays(-12), "s4", "C:\\work\\gamma", "claude-opus-5-5", "g1"), "gamma", "s4.jsonl");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, Clock);

        Assert.Equal(
            [new SessionSummary("s2", "alpha", "claude-opus-5-5", Now.AddHours(-1)), new SessionSummary("s3", "beta", "claude-haiku-5-5", Now.AddHours(-3))],
            activity.RecentSessions.Select(session => session with { LastActivity = session.LastActivity.ToUniversalTime() }));
        Assert.Equal("claude-opus-5-5", activity.CurrentModel);
    }

    [Fact]
    public async Task TodayStartsAtLocalMidnight()
    {
        using var projects = new TemporaryFolder();
        var pacific = TimeZoneInfo.CreateCustomTimeZone("Test-8", TimeSpan.FromHours(-8), "Test-8", "Test-8");
        var morningPacific = new FixedTimeProvider(new DateTimeOffset(2026, 11, 3, 17, 0, 0, TimeSpan.Zero), pacific);
        projects.WriteFile(string.Join('\n',
            AssistantLine(new DateTimeOffset(2026, 11, 3, 9, 0, 0, TimeSpan.Zero), messageId: "after-midnight-pacific"),
            AssistantLine(new DateTimeOffset(2026, 11, 3, 7, 0, 0, TimeSpan.Zero), messageId: "before-midnight-pacific")), "alpha", "s1.jsonl");

        var activity = await TokenHistoryParser.ParseLocalTokenHistoryAsync(projects.Path, morningPacific);

        Assert.Equal(100, activity.TodayTokens);
        Assert.Equal(200, activity.Last3DaysTokens);
    }
}
