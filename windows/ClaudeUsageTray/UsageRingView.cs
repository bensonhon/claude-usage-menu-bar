using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public sealed class RingArc : FrameworkElement
{
    public static readonly DependencyProperty AnimatedRemainingProperty = DependencyProperty.Register(
        nameof(AnimatedRemaining), typeof(double), typeof(RingArc),
        new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    private readonly double? remaining;
    private readonly double lineWidth;
    private readonly Theme theme;

    public RingArc(double? remaining, double size, double lineWidth, Theme theme)
    {
        this.remaining = remaining;
        this.lineWidth = lineWidth;
        this.theme = theme;
        Width = size;
        Height = size;
    }

    public double AnimatedRemaining
    {
        get => (double)GetValue(AnimatedRemainingProperty);
        set => SetValue(AnimatedRemainingProperty, value);
    }

    public void AnimateFrom(double startingRemaining, TimeSpan duration, bool reduceMotion)
    {
        var target = remaining ?? 0;
        if (reduceMotion || duration == TimeSpan.Zero)
        {
            AnimatedRemaining = target;
            return;
        }
        BeginAnimation(AnimatedRemainingProperty, new DoubleAnimation(startingRemaining, target, duration)
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
        });
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        var center = new Point(Width / 2, Height / 2);
        var radius = (Width - lineWidth) / 2;
        drawingContext.DrawEllipse(null, new Pen(theme.RingTrack, lineWidth), center, radius, radius);
        if (remaining is null || AnimatedRemaining <= 0)
        {
            return;
        }
        var pen = new Pen(theme.ForRemaining(remaining), lineWidth) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        var fraction = Math.Min(AnimatedRemaining, 99.999) / 100;
        var angle = fraction * 2 * Math.PI;
        var start = new Point(center.X, center.Y - radius);
        var end = new Point(center.X + radius * Math.Sin(angle), center.Y - radius * Math.Cos(angle));
        var figure = new PathFigure { StartPoint = start, IsClosed = false };
        figure.Segments.Add(new ArcSegment(end, new Size(radius, radius), 0, fraction > 0.5, SweepDirection.Clockwise, true));
        var geometry = new PathGeometry([figure]);
        drawingContext.DrawGeometry(null, pen, geometry);
    }
}

public static class UsageRingView
{
    public static FrameworkElement Make(
        double? remaining,
        double size,
        double lineWidth,
        string? label,
        string? resetTime,
        Theme theme,
        bool compactReset,
        double startingRemaining,
        bool reduceMotion)
    {
        var arc = new RingArc(remaining, size, lineWidth, theme);
        arc.Loaded += (_, _) => arc.AnimateFrom(startingRemaining, TimeSpan.FromMilliseconds(startingRemaining == 0 ? 800 : 500), reduceMotion);

        var centerText = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        if (remaining is { } value)
        {
            centerText.Children.Add(Text.Make($"{(int)value}%", size * 0.24, FontWeights.Bold, theme.ForRemaining(remaining), center: true));
            centerText.Children.Add(Text.Make("left", size * 0.11, FontWeights.Medium, theme.TextMuted, center: true));
        }
        else
        {
            centerText.Children.Add(Text.Make("?", size * 0.3, FontWeights.Bold, theme.TextMuted, center: true));
        }
        var ring = new Grid { Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center, Children = { arc, centerText } };

        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        stack.Children.Add(ring);
        var caption = new StackPanel { Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
        if (label is not null)
        {
            caption.Children.Add(Text.Make(label, 12, FontWeights.SemiBold, theme.TextSecondary, center: true));
        }
        if (compactReset)
        {
            var compact = Text.Make(resetTime ?? "---", 10, FontWeights.Normal, theme.TextMuted, center: true);
            compact.TextWrapping = TextWrapping.Wrap;
            compact.MaxWidth = size + 24;
            caption.Children.Add(compact);
        }
        else
        {
            var resetRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0) };
            resetRow.Children.Add(Icons.Make(Icons.Clock, 9, theme.TextMuted));
            resetRow.Children.Add(Text.Make(resetTime is null ? "---" : $"Reset by {resetTime}", 10, FontWeights.Normal, theme.TextMuted, margin: new Thickness(3, 0, 0, 0)));
            caption.Children.Add(resetRow);
        }
        stack.Children.Add(caption);
        return stack;
    }
}

public static class UsageProgressBar
{
    public static FrameworkElement Make(WindowDisplayInfo item, string resetTime, Theme theme)
    {
        var barColor = theme.ForRemaining(item.Remaining);
        var panel = new StackPanel();
        var header = new DockPanel();
        var percent = Text.Make($"{(int)item.Remaining}% left", 11, FontWeights.SemiBold, barColor);
        DockPanel.SetDock(percent, Dock.Right);
        header.Children.Add(percent);
        header.Children.Add(Text.Make(item.Label, 12, FontWeights.Medium, theme.TextSecondary));
        panel.Children.Add(header);
        panel.Children.Add(Bars.Make(item.Remaining / 100, barColor, theme.RingTrack, 6, new Thickness(0, 6, 0, 0)));
        if (resetTime != ResetClock.NoResetTime)
        {
            var resetRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 6, 0, 0) };
            resetRow.Children.Add(Icons.Make(Icons.Clock, 8, theme.TextMuted));
            resetRow.Children.Add(Text.Make($"Reset by {resetTime}", 9, FontWeights.Normal, theme.TextMuted, margin: new Thickness(3, 0, 0, 0)));
            panel.Children.Add(resetRow);
        }
        return Cards.Make(panel, theme.Card, new Thickness(12, 10, 12, 10), 10);
    }
}

public static class Bars
{
    public static FrameworkElement Make(double fraction, Brush fill, Brush track, double height, Thickness margin)
    {
        var clampedFraction = Math.Max(0, Math.Min(1, fraction));
        var grid = new Grid { Height = height, Margin = margin };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(clampedFraction, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - clampedFraction, GridUnitType.Star) });
        var trackBorder = new Border { Background = track, CornerRadius = new CornerRadius(height / 2) };
        Grid.SetColumnSpan(trackBorder, 2);
        grid.Children.Add(trackBorder);
        if (clampedFraction > 0)
        {
            grid.Children.Add(new Border { Background = fill, CornerRadius = new CornerRadius(height / 2) });
        }
        return grid;
    }
}

public static class Cards
{
    public static Border Make(UIElement child, Brush background, Thickness padding, double cornerRadius) => new()
    {
        Background = background,
        CornerRadius = new CornerRadius(cornerRadius),
        Padding = padding,
        Child = child,
    };
}

public static class Text
{
    public static TextBlock Make(string text, double size, FontWeight weight, Brush foreground, bool center = false, Thickness? margin = null, bool mono = false) => new()
    {
        Text = text,
        FontSize = size,
        FontWeight = weight,
        Foreground = foreground,
        FontFamily = mono ? Theme.MonoFont : Theme.TextFont,
        TextAlignment = center ? TextAlignment.Center : TextAlignment.Left,
        HorizontalAlignment = center ? HorizontalAlignment.Center : HorizontalAlignment.Left,
        VerticalAlignment = VerticalAlignment.Center,
        Margin = margin ?? new Thickness(0),
        TextTrimming = TextTrimming.CharacterEllipsis,
        Typography = { NumeralAlignment = FontNumeralAlignment.Tabular },
    };

    public static FrameworkElement Circle(Brush color, double size = 7) => new System.Windows.Shapes.Ellipse
    {
        Width = size,
        Height = size,
        Fill = color,
        VerticalAlignment = VerticalAlignment.Center,
    };

}
