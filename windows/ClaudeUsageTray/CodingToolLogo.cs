using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public static class CodingToolLogo
{
    private static readonly Lazy<BitmapImage> ClaudeLogo = new(() => LoadLogo("ClaudeLogo.png"));
    private static readonly Lazy<BitmapImage> ChatGPTLogo = new(() => LoadLogo("ChatGPTLogo.png"));

    public static FrameworkElement Make(CodingTool codingTool, double size, Brush chatGPTLogoColor)
    {
        FrameworkElement logo = codingTool switch
        {
            CodingTool.ClaudeCode => new Image { Source = ClaudeLogo.Value, Width = size, Height = size },
            CodingTool.Codex => new Rectangle
            {
                Width = size,
                Height = size,
                Fill = chatGPTLogoColor,
                OpacityMask = new ImageBrush(ChatGPTLogo.Value) { Stretch = Stretch.Uniform },
            },
            _ => throw new ArgumentOutOfRangeException(nameof(codingTool), codingTool, null),
        };
        RenderOptions.SetBitmapScalingMode(logo, BitmapScalingMode.HighQuality);
        logo.VerticalAlignment = VerticalAlignment.Center;
        logo.ToolTip = codingTool.Name();
        return logo;
    }

    private static BitmapImage LoadLogo(string fileName)
    {
        var logo = new BitmapImage(new Uri($"pack://application:,,,/{fileName}"));
        logo.Freeze();
        return logo;
    }
}
