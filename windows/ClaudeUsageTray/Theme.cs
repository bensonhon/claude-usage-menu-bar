using System.Windows.Media;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public sealed class Theme
{
    public static readonly FontFamily TextFont = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily DisplayFont = new("Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily MonoFont = new("Cascadia Mono, Consolas");

    public static readonly Brush Accent = BrushFrom(UsageColors.Accent);
    public static readonly Brush Green = BrushFrom(UsageColors.Green);
    public static readonly Brush Amber = BrushFrom(UsageColors.Amber);
    public static readonly Brush Red = BrushFrom(UsageColors.Red);
    public static readonly Brush White = Brushes.White;

    public bool IsDark { get; }
    public Brush Background { get; }
    public Brush Card { get; }
    public Brush Row { get; }
    public Brush Segment { get; }
    public Brush TextPrimary { get; }
    public Brush TextSecondary { get; }
    public Brush TextMuted { get; }
    public Brush RingTrack { get; }
    public Brush Hairline { get; }
    public Brush SessionRow { get; }

    private Theme(bool isDark)
    {
        IsDark = isDark;
        Background = BrushFrom(isDark ? "#1A1A2E" : "#F5F5F7");
        Card = BrushFrom(isDark ? "#222244" : "#E8E8EC");
        Row = isDark ? BrushFrom("#1A1A2E", 0.55) : BrushFrom("#F5F5F7", 0.7);
        Segment = BrushFrom(isDark ? "#333355" : "#D0D0D5");
        TextPrimary = BrushFrom(isDark ? "#FFFFFF" : "#1A1A1A");
        TextSecondary = BrushFrom(isDark ? "#CCCCCC" : "#444444");
        TextMuted = BrushFrom(isDark ? "#999999" : "#666666");
        RingTrack = isDark ? BrushFrom("#FFFFFF", 0.1) : BrushFrom("#DDDDDD");
        Hairline = isDark ? BrushFrom("#FFFFFF", 0.08) : BrushFrom("#000000", 0.08);
        SessionRow = BrushFrom(isDark ? "#2E2E5C" : "#F4F6FA");
    }

    public static Theme Dark { get; } = new(isDark: true);
    public static Theme Light { get; } = new(isDark: false);

    public static Theme For(bool darkMode) => darkMode ? Dark : Light;

    public Brush ForRemaining(double? remaining) =>
        UsageColors.ForRemaining(remaining) is { } hex ? BrushFrom(hex) : TextMuted;

    public static SolidColorBrush BrushFrom(string hex, double opacity = 1)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex);
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }

    public static SolidColorBrush Tinted(Brush brush, double opacity)
    {
        var color = brush is SolidColorBrush solid ? solid.Color : Colors.Gray;
        var tinted = new SolidColorBrush(color) { Opacity = opacity };
        tinted.Freeze();
        return tinted;
    }
}
