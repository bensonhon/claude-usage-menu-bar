using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using ClaudeUsageTray.Core;
using Microsoft.Win32;

namespace ClaudeUsageTray;

public static class TaskbarTheme
{
    private const string PersonalizeKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    public static bool IsTaskbarLight()
    {
        using var personalizeKey = Registry.CurrentUser.OpenSubKey(PersonalizeKeyPath);
        return personalizeKey?.GetValue("SystemUsesLightTheme") is int systemUsesLightTheme && systemUsesLightTheme == 1;
    }
}

public sealed class TrayIconImage : IDisposable
{
    private readonly IntPtr iconHandle;

    public TrayIconImage(Bitmap bitmap)
    {
        iconHandle = bitmap.GetHicon();
        Icon = Icon.FromHandle(iconHandle);
    }

    public Icon Icon { get; }

    public void Dispose()
    {
        Icon.Dispose();
        DestroyIcon(iconHandle);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr iconHandle);
}

public static class TrayIconRenderer
{
    private static readonly Lazy<Bitmap> ClaudeLogo = new(LoadClaudeLogo);

    public static TrayIconImage RenderRing(double? remaining, string? accountColorHex, int size, bool isTaskbarLight)
    {
        using var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            graphics.Clear(Color.Transparent);

            var lineWidth = Math.Max(1.4f, size * 0.1f);
            var inset = lineWidth / 2;
            var ringBounds = new RectangleF(inset, inset, size - lineWidth, size - lineWidth);
            using (var trackPen = new Pen(Color.FromArgb(77, 128, 128, 128), lineWidth))
            {
                graphics.DrawEllipse(trackPen, ringBounds);
            }

            var textColor = isTaskbarLight ? Color.FromArgb(255, 26, 26, 26) : Color.White;
            if (remaining is { } value)
            {
                if (value > 0)
                {
                    using var arcPen = new Pen(ColorFromHex(UsageColors.ForRemaining(value)!), lineWidth) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                    graphics.DrawArc(arcPen, ringBounds, -90, (float)(value / 100 * 360));
                }
                var label = ((int)value).ToString(System.Globalization.CultureInfo.InvariantCulture);
                DrawCenteredText(graphics, label, size * (label.Length >= 3 ? 0.36f : 0.47f), textColor, size);
            }
            else
            {
                DrawCenteredText(graphics, "?", size * 0.55f, Color.FromArgb(153, textColor), size);
            }

            if (accountColorHex is not null)
            {
                var dotRadius = size * 0.17f;
                var dotCenter = new PointF(size - dotRadius - 0.5f, size - dotRadius - 0.5f);
                var dotBounds = new RectangleF(dotCenter.X - dotRadius, dotCenter.Y - dotRadius, dotRadius * 2, dotRadius * 2);
                using var dotBrush = new SolidBrush(ColorFromHex(accountColorHex));
                graphics.FillEllipse(dotBrush, dotBounds);
                using var dotOutline = new Pen(isTaskbarLight ? Color.FromArgb(230, 243, 243, 243) : Color.FromArgb(230, 28, 28, 28), Math.Max(1f, size * 0.06f));
                graphics.DrawEllipse(dotOutline, dotBounds);
            }
        }
        return new TrayIconImage(bitmap);
    }

    public static TrayIconImage RenderLogo(int size)
    {
        using var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.Clear(Color.Transparent);
            var logoSize = size * 0.9f;
            var offset = (size - logoSize) / 2;
            graphics.DrawImage(ClaudeLogo.Value, offset, offset, logoSize, logoSize);
        }
        return new TrayIconImage(bitmap);
    }

    private static void DrawCenteredText(Graphics graphics, string text, float fontPixelSize, Color color, int size)
    {
        using var font = new Font("Segoe UI", fontPixelSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(color);
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.NoClip };
        graphics.DrawString(text, font, brush, new RectangleF(0, 0.5f, size, size), format);
    }

    private static Color ColorFromHex(string hex) => ColorTranslator.FromHtml(hex);

    private static Bitmap LoadClaudeLogo()
    {
        var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/ClaudeLogo.png"))
            ?? throw new InvalidOperationException("ClaudeLogo.png is missing from the app resources.");
        using var stream = resource.Stream;
        return new Bitmap(stream);
    }
}
