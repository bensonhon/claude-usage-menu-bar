using System.Text.Json;

namespace ClaudeUsageTray.Core;

public sealed class JsonFile<T> where T : class
{
    private static readonly JsonSerializerOptions SerializerOptions = new() { WriteIndented = true };

    private readonly string filePath;

    public JsonFile(string filePath)
    {
        this.filePath = filePath;
    }

    public T? Load()
    {
        try
        {
            return JsonSerializer.Deserialize<T>(File.ReadAllText(filePath), SerializerOptions);
        }
        catch (FileNotFoundException)
        {
            return null;
        }
        catch (DirectoryNotFoundException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public void Save(T value)
    {
        var folderPath = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrEmpty(folderPath))
        {
            Directory.CreateDirectory(folderPath);
        }
        var temporaryFilePath = filePath + ".tmp";
        File.WriteAllText(temporaryFilePath, JsonSerializer.Serialize(value, SerializerOptions));
        File.Move(temporaryFilePath, filePath, overwrite: true);
    }
}
