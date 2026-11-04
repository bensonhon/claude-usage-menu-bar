using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsageTray.Core;

public sealed record TokenActivity
{
    public long TodayTokens { get; init; }
    public long Last3DaysTokens { get; init; }
    public long Last7DaysTokens { get; init; }
    public long TodayInputTokens { get; init; }
    public long TodayOutputTokens { get; init; }
    public long TodayCacheCreationTokens { get; init; }
    public long TodayCacheReadTokens { get; init; }
    public string? CurrentModel { get; init; }
    public IReadOnlyList<SessionSummary> RecentSessions { get; init; } = [];
}

public sealed record SessionSummary(string Id, string ProjectName, string Model, DateTimeOffset LastActivity);

public static class TokenHistoryParser
{
    public const long TailBytesPerFile = 128 * 1024;
    private static readonly TimeSpan SessionWindow = TimeSpan.FromDays(10);

    public static async Task<TokenActivity> ParseLocalTokenHistoryAsync(string projectsFolderPath, TimeProvider timeProvider)
    {
        if (!Directory.Exists(projectsFolderPath))
        {
            return new TokenActivity();
        }
        var now = timeProvider.GetUtcNow();
        var localNow = TimeZoneInfo.ConvertTime(now, timeProvider.LocalTimeZone);
        var startOfToday = new DateTimeOffset(localNow.Date, localNow.Offset);
        var start3Days = startOfToday.AddSeconds(-2 * 86_400);
        var start7Days = startOfToday.AddSeconds(-6 * 86_400);
        var sessionCutoff = now - SessionWindow;

        var filePaths = FindTranscriptFiles(projectsFolderPath)
            .Where(filePath => File.GetLastWriteTimeUtc(filePath) >= sessionCutoff.UtcDateTime)
            .ToList();
        var fileResults = await Task.WhenAll(filePaths.Select(filePath =>
            Task.Run(() => ParseFile(filePath, startOfToday, start3Days, start7Days))));

        return Merge(fileResults, sessionCutoff);
    }

    private static IEnumerable<string> FindTranscriptFiles(string folderPath)
    {
        var folders = new Stack<string>();
        folders.Push(folderPath);
        while (folders.Count > 0)
        {
            var currentFolder = folders.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(currentFolder).ToList();
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (DirectoryNotFoundException)
            {
                continue;
            }
            foreach (var entry in entries)
            {
                if (IsHidden(entry))
                {
                    continue;
                }
                if (Directory.Exists(entry))
                {
                    folders.Push(entry);
                }
                else if (string.Equals(Path.GetExtension(entry), ".jsonl", StringComparison.OrdinalIgnoreCase))
                {
                    yield return entry;
                }
            }
        }
    }

    private static bool IsHidden(string entryPath)
    {
        if (Path.GetFileName(entryPath).StartsWith('.'))
        {
            return true;
        }
        try
        {
            return File.GetAttributes(entryPath).HasFlag(FileAttributes.Hidden);
        }
        catch (FileNotFoundException)
        {
            return true;
        }
        catch (DirectoryNotFoundException)
        {
            return true;
        }
    }

    private static TokenActivity Merge(IEnumerable<FileParseResult> fileResults, DateTimeOffset sessionCutoff)
    {
        long todayTokens = 0, last3DaysTokens = 0, last7DaysTokens = 0;
        long todayInput = 0, todayOutput = 0, todayCacheCreation = 0, todayCacheRead = 0;
        string? latestModel = null;
        var latestModelTimestamp = DateTimeOffset.MinValue;
        var mergedSessions = new Dictionary<string, SessionAccumulator>();

        foreach (var result in fileResults)
        {
            todayTokens += result.TodayTokens;
            last3DaysTokens += result.Last3DaysTokens;
            last7DaysTokens += result.Last7DaysTokens;
            todayInput += result.TodayInputTokens;
            todayOutput += result.TodayOutputTokens;
            todayCacheCreation += result.TodayCacheCreationTokens;
            todayCacheRead += result.TodayCacheReadTokens;
            if (result.LatestModel is not null && result.LatestModelTimestamp > latestModelTimestamp)
            {
                latestModel = result.LatestModel;
                latestModelTimestamp = result.LatestModelTimestamp;
            }
            foreach (var (sessionId, session) in result.Sessions)
            {
                if (!mergedSessions.TryGetValue(sessionId, out var existing) || session.LastActivity > existing.LastActivity)
                {
                    mergedSessions[sessionId] = session;
                }
            }
        }

        var latestSessionByProject = new Dictionary<string, SessionSummary>();
        foreach (var (sessionId, session) in mergedSessions)
        {
            if (session.LastActivity < sessionCutoff)
            {
                continue;
            }
            var projectName = session.Cwd is null ? "(unknown)" : ClaudeAccount.LastPathComponent(session.Cwd);
            var summary = new SessionSummary(sessionId, projectName, session.Model, session.LastActivity);
            if (!latestSessionByProject.TryGetValue(projectName, out var existing) || summary.LastActivity > existing.LastActivity)
            {
                latestSessionByProject[projectName] = summary;
            }
        }

        return new TokenActivity
        {
            TodayTokens = todayTokens,
            Last3DaysTokens = last3DaysTokens,
            Last7DaysTokens = last7DaysTokens,
            TodayInputTokens = todayInput,
            TodayOutputTokens = todayOutput,
            TodayCacheCreationTokens = todayCacheCreation,
            TodayCacheReadTokens = todayCacheRead,
            CurrentModel = latestModel,
            RecentSessions = latestSessionByProject.Values.OrderByDescending(summary => summary.LastActivity).ToList(),
        };
    }

    private static FileParseResult ParseFile(string filePath, DateTimeOffset startOfToday, DateTimeOffset start3Days, DateTimeOffset start7Days)
    {
        var result = new FileParseResult();
        var lines = ReadTailLines(filePath);
        if (lines is null)
        {
            return result;
        }
        var seenMessageIds = new HashSet<string>();

        foreach (var line in lines)
        {
            JsonlMessage? jsonlMessage;
            try
            {
                jsonlMessage = JsonSerializer.Deserialize<JsonlMessage>(line);
            }
            catch (JsonException)
            {
                continue;
            }
            if (jsonlMessage is not { Type: "assistant", Message: { } message })
            {
                continue;
            }
            var messageDate = ParseTimestamp(jsonlMessage.Timestamp);

            if (message.Model is { } model && messageDate is { } modelDate && modelDate > result.LatestModelTimestamp)
            {
                result.LatestModel = model;
                result.LatestModelTimestamp = modelDate;
            }

            if (jsonlMessage.SessionId is { } sessionId && message.Model is { } sessionModel && messageDate is { } sessionDate)
            {
                if (result.Sessions.TryGetValue(sessionId, out var existing))
                {
                    if (sessionDate > existing.LastActivity)
                    {
                        result.Sessions[sessionId] = new SessionAccumulator(sessionModel, jsonlMessage.Cwd ?? existing.Cwd, sessionDate);
                    }
                }
                else
                {
                    result.Sessions[sessionId] = new SessionAccumulator(sessionModel, jsonlMessage.Cwd, sessionDate);
                }
            }

            if (message.Usage is not { } usage || messageDate is not { } usageDate)
            {
                continue;
            }
            if (message.Id is { } messageId && !seenMessageIds.Add(messageId))
            {
                continue;
            }

            var input = usage.InputTokens ?? 0;
            var output = usage.OutputTokens ?? 0;
            var cacheCreation = usage.CacheCreationInputTokens ?? 0;
            var cacheRead = usage.CacheReadInputTokens ?? 0;
            var total = input + output + cacheCreation + cacheRead;

            if (usageDate >= start7Days)
            {
                result.Last7DaysTokens += total;
            }
            if (usageDate >= start3Days)
            {
                result.Last3DaysTokens += total;
            }
            if (usageDate >= startOfToday)
            {
                result.TodayTokens += total;
                result.TodayInputTokens += input;
                result.TodayOutputTokens += output;
                result.TodayCacheCreationTokens += cacheCreation;
                result.TodayCacheReadTokens += cacheRead;
            }
        }
        return result;
    }

    private static DateTimeOffset? ParseTimestamp(string? timestamp) =>
        timestamp is not null
        && DateTimeOffset.TryParse(timestamp, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)
            ? parsed
            : null;

    private static List<string>? ReadTailLines(string filePath)
    {
        try
        {
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var offset = stream.Length > TailBytesPerFile ? stream.Length - TailBytesPerFile : 0;
            stream.Seek(offset, SeekOrigin.Begin);
            var buffer = new byte[stream.Length - offset];
            stream.ReadExactly(buffer);
            var parts = Encoding.UTF8.GetString(buffer).Split('\n').ToList();
            if (offset > 0 && parts.Count > 0)
            {
                parts.RemoveAt(0);
            }
            return parts.Select(part => part.TrimEnd('\r')).Where(part => part.Length > 0).ToList();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private sealed class FileParseResult
    {
        public long TodayTokens;
        public long Last3DaysTokens;
        public long Last7DaysTokens;
        public long TodayInputTokens;
        public long TodayOutputTokens;
        public long TodayCacheCreationTokens;
        public long TodayCacheReadTokens;
        public Dictionary<string, SessionAccumulator> Sessions { get; } = new();
        public string? LatestModel;
        public DateTimeOffset LatestModelTimestamp = DateTimeOffset.MinValue;
    }

    private sealed record SessionAccumulator(string Model, string? Cwd, DateTimeOffset LastActivity);

    private sealed class JsonlMessage
    {
        [JsonPropertyName("type")] public string? Type { get; init; }
        [JsonPropertyName("timestamp")] public string? Timestamp { get; init; }
        [JsonPropertyName("sessionId")] public string? SessionId { get; init; }
        [JsonPropertyName("cwd")] public string? Cwd { get; init; }
        [JsonPropertyName("message")] public MessageContent? Message { get; init; }
    }

    private sealed class MessageContent
    {
        [JsonPropertyName("id")] public string? Id { get; init; }
        [JsonPropertyName("model")] public string? Model { get; init; }
        [JsonPropertyName("usage")] public TokenUsage? Usage { get; init; }
    }

    private sealed class TokenUsage
    {
        [JsonPropertyName("input_tokens")] public long? InputTokens { get; init; }
        [JsonPropertyName("output_tokens")] public long? OutputTokens { get; init; }
        [JsonPropertyName("cache_creation_input_tokens")] public long? CacheCreationInputTokens { get; init; }
        [JsonPropertyName("cache_read_input_tokens")] public long? CacheReadInputTokens { get; init; }
    }
}
