using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace ClaudeUsageTray;

public static class Icons
{
    public const string Moon = "M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z";
    public const string Sun = "M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0 M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41";
    public const string SimpleMode = "M14 10L21 3M20 10h-6V4M3 21L10 14M4 14h6v6";
    public const string Refresh = "M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16M8 16H3v5";
    public const string Power = "M12 2v10M18.4 6.6a9 9 0 1 1-12.77.04";
    public const string Gear = "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2zM9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0";
    public const string ChevronDown = "M6 9l6 6 6-6";
    public const string ChevronUp = "M18 15l-6-6-6 6";
    public const string Clock = "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0M12 6v6l4 2";
    public const string External = "M7 7h10v10M7 17L17 7";
    public const string Layers = "M12 2l10 5-10 5L2 7l10-5ZM2 17l10 5 10-5M2 12l10 5 10-5";
    public const string Dollar = "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8M12 18V6";
    public const string Sessions = "M4.5 4h15a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 8.5v-3A1.5 1.5 0 0 1 4.5 4ZM4.5 14h15a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5v-3A1.5 1.5 0 0 1 4.5 14Z";
    public const string Chart = "M3 3v18h18M8 17v-5M13 17V8M18 17V9";
    public const string Sleep = "M2 4h6l-6 8h6M12 4h4l-4 5h4M19 4h3l-3 4h3";
    public const string Plus = "M12 5v14M5 12h14";

    public static FrameworkElement Make(string pathData, double size, Brush stroke)
    {
        var path = new Path
        {
            Data = Geometry.Parse(pathData),
            Stroke = stroke,
            StrokeThickness = 2,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            StrokeLineJoin = PenLineJoin.Round,
            Width = 24,
            Height = 24,
            Stretch = Stretch.None,
        };
        return new Viewbox
        {
            Width = size,
            Height = size,
            Child = new Canvas { Width = 24, Height = 24, Children = { path } },
            VerticalAlignment = VerticalAlignment.Center,
            SnapsToDevicePixels = true,
        };
    }
}
