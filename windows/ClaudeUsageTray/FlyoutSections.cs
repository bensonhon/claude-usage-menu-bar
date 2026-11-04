using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public static class Buttons
{
    public static Button Make(UIElement content, Brush foreground, Brush background, Brush border, Action onClick, string? tooltip = null, Thickness? padding = null)
    {
        var button = new Button
        {
            Style = (Style)Application.Current.Resources["FlatButton"],
            Content = content,
            Foreground = foreground,
            Background = background,
            BorderBrush = border,
            Padding = padding ?? new Thickness(8, 3, 8, 3),
            ToolTip = tooltip,
        };
        if (tooltip is not null)
        {
            System.Windows.Automation.AutomationProperties.SetName(button, tooltip);
        }
        button.Click += (_, _) => onClick();
        return button;
    }

    public static Button Labeled(string? iconPath, string label, Brush color, Theme theme, Action onClick)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        if (iconPath is not null)
        {
            content.Children.Add(Icons.Make(iconPath, 10, color));
        }
        content.Children.Add(Text.Make(label, 11, FontWeights.Medium, color, margin: new Thickness(iconPath is null ? 0 : 4, 0, 0, 0)));
        var button = Make(content, color, Theme.Tinted(color, 0.1), Theme.Tinted(color, 0.45), onClick);
        System.Windows.Automation.AutomationProperties.SetName(button, label);
        return button;
    }
}

public static class SectionTitle
{
    public static FrameworkElement Make(string iconPath, Brush iconColor, string title, Theme theme, string? trailingText = null)
    {
        var dock = new DockPanel { LastChildFill = false };
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(Icons.Make(iconPath, 12, iconColor));
        left.Children.Add(Text.Make(title, 13, FontWeights.SemiBold, theme.TextPrimary, margin: new Thickness(6, 0, 0, 0)));
        DockPanel.SetDock(left, Dock.Left);
        dock.Children.Add(left);
        if (trailingText is not null)
        {
            var trailing = Text.Make(trailingText, 10, FontWeights.Medium, theme.TextMuted);
            DockPanel.SetDock(trailing, Dock.Right);
            dock.Children.Add(trailing);
        }
        return dock;
    }
}

public static class LoginProblemNote
{
    public static FrameworkElement? Make(LoginStatus loginStatus, Theme theme, string? accountLabel = null, Brush? dotColor = null)
    {
        if (UsageText.LoginProblemText(loginStatus) is not { } problemText)
        {
            return null;
        }
        var row = new DockPanel();
        if (dotColor is not null)
        {
            var dot = Text.Circle(dotColor);
            dot.VerticalAlignment = VerticalAlignment.Top;
            dot.Margin = new Thickness(0, 4, 6, 0);
            DockPanel.SetDock(dot, Dock.Left);
            row.Children.Add(dot);
        }
        var text = Text.Make(accountLabel is null ? problemText : $"{accountLabel}: {problemText}", 11, FontWeights.Normal, theme.TextSecondary);
        text.TextWrapping = TextWrapping.Wrap;
        text.TextTrimming = TextTrimming.None;
        row.Children.Add(text);
        return Cards.Make(row, Theme.Tinted(Theme.Amber, 0.14), new Thickness(10, 8, 10, 8), 8);
    }
}

public static class ModelUsageSection
{
    public static FrameworkElement? Make(AccountUsage usage, Theme theme, TimeProvider timeProvider)
    {
        var items = usage.SecondaryWindows;
        if (items.Count == 0)
        {
            return null;
        }
        var stack = new StackPanel();
        stack.Children.Add(SectionTitle.Make(Icons.Layers, Theme.Tinted(Theme.Accent, 0.8), "Model Usage", theme));
        foreach (var item in items)
        {
            var bar = UsageProgressBar.Make(item, ResetClock.ResetClockString(item.Window, timeProvider), theme);
            bar.Margin = new Thickness(0, 8, 0, 0);
            stack.Children.Add(bar);
        }
        return stack;
    }
}

public static class ExtraUsageSection
{
    public static FrameworkElement? Make(AccountUsage usage, Theme theme)
    {
        if (usage.ExtraUsage is not { IsEnabled: true } extra)
        {
            return null;
        }
        var stack = new StackPanel();
        stack.Children.Add(SectionTitle.Make(Icons.Dollar, Theme.Amber, "Extra Usage", theme));

        var amounts = new Grid { Margin = new Thickness(0, 6, 0, 0) };
        amounts.ColumnDefinitions.Add(new ColumnDefinition());
        if (extra.MonthlyLimit is not null)
        {
            amounts.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            amounts.ColumnDefinitions.Add(new ColumnDefinition());
        }
        amounts.Children.Add(Amount("Credits Used", (extra.UsedCredits ?? 0) / 100, theme));
        if (extra.MonthlyLimit is { } monthlyLimit)
        {
            var slash = Text.Make("/", 18, FontWeights.Light, theme.TextMuted, margin: new Thickness(4, 0, 4, 0));
            Grid.SetColumn(slash, 1);
            amounts.Children.Add(slash);
            var limit = Amount("Monthly Limit", monthlyLimit / 100, theme);
            Grid.SetColumn(limit, 2);
            amounts.Children.Add(limit);
        }
        stack.Children.Add(amounts);

        if (extra.MonthlyLimit is { } positiveLimit && positiveLimit > 0)
        {
            stack.Children.Add(Bars.Make((extra.UsedCredits ?? 0) / positiveLimit, Theme.Amber, theme.Card, 6, new Thickness(0, 6, 0, 8)));
        }
        return Cards.Make(stack, theme.Card, new Thickness(12, 10, 12, 2), 12);
    }

    private static FrameworkElement Amount(string label, double dollars, Theme theme)
    {
        var amount = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        amount.Children.Add(Text.Make(label, 10, FontWeights.Medium, theme.TextMuted));
        var value = Text.Make("$" + dollars.ToString("0.00", CultureInfo.InvariantCulture), 18, FontWeights.Bold, theme.TextPrimary);
        value.FontFamily = Theme.DisplayFont;
        amount.Children.Add(value);
        return amount;
    }
}

public static class TokenHistoryView
{
    private static readonly (string Label, string Hex, Func<TokenActivity, long> Tokens)[] DetailRows =
    [
        ("Input", "#60A5FA", activity => activity.TodayInputTokens),
        ("Output", "#34D399", activity => activity.TodayOutputTokens),
        ("Cache Write", "#A78BFA", activity => activity.TodayCacheCreationTokens),
        ("Cache Read", "#FBBF24", activity => activity.TodayCacheReadTokens),
    ];

    public static FrameworkElement Make(TokenActivity activity, bool isLoading, Theme theme)
    {
        var stack = new StackPanel();
        var title = new StackPanel { Orientation = Orientation.Horizontal };
        title.Children.Add(Icons.Make(Icons.Chart, 12, Theme.Accent));
        title.Children.Add(Text.Make("Token Activity", 13, FontWeights.SemiBold, theme.TextSecondary, margin: new Thickness(6, 0, 0, 0)));
        stack.Children.Add(title);

        var totals = new UniformGrid3();
        totals.Add(TotalCard("Today", activity.TodayTokens, isLoading, theme));
        totals.Add(TotalCard("Last 3 Days", activity.Last3DaysTokens, isLoading, theme));
        totals.Add(TotalCard("Last 7 Days", activity.Last7DaysTokens, isLoading, theme));
        totals.Grid.Margin = new Thickness(0, 10, 0, 0);
        stack.Children.Add(totals.Grid);

        if (isLoading || activity.TodayTokens > 0)
        {
            var details = new StackPanel { Margin = new Thickness(12, 12, 12, 0) };
            foreach (var (label, hex, tokens) in DetailRows)
            {
                var row = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
                var dot = Text.Circle(Theme.BrushFrom(hex), 6);
                DockPanel.SetDock(dot, Dock.Left);
                row.Children.Add(dot);
                FrameworkElement value = isLoading
                    ? Skeleton.Make(36, 10, theme)
                    : Text.Make(UsageText.FormatTokenCount(tokens(activity)), 10, FontWeights.SemiBold, theme.TextSecondary, mono: true);
                DockPanel.SetDock(value, Dock.Right);
                row.Children.Add(value);
                row.Children.Add(Text.Make(label, 10, FontWeights.Medium, theme.TextSecondary, margin: new Thickness(6, 0, 0, 0)));
                details.Children.Add(row);
            }
            stack.Children.Add(details);
        }
        return Cards.Make(stack, theme.Card, new Thickness(12), 12);
    }

    private static FrameworkElement TotalCard(string title, long value, bool isLoading, Theme theme)
    {
        var card = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        if (isLoading)
        {
            card.Children.Add(Skeleton.Make(38, 14, theme));
        }
        else
        {
            var number = Text.Make(UsageText.FormatTokenCount(value), 15, FontWeights.Bold, theme.TextPrimary, center: true);
            number.FontFamily = Theme.DisplayFont;
            card.Children.Add(number);
        }
        card.Children.Add(Text.Make(title, 10, FontWeights.Medium, theme.TextSecondary, center: true, margin: new Thickness(0, 3, 0, 0)));
        return card;
    }

    private sealed class UniformGrid3
    {
        public Grid Grid { get; } = new();
        private int column;

        public UniformGrid3()
        {
            for (var index = 0; index < 3; index++)
            {
                Grid.ColumnDefinitions.Add(new ColumnDefinition());
            }
        }

        public void Add(UIElement element)
        {
            Grid.SetColumn(element, column++);
            Grid.Children.Add(element);
        }
    }
}

public static class Skeleton
{
    public static FrameworkElement Make(double width, double height, Theme theme)
    {
        var block = new Border
        {
            Width = width,
            Height = height,
            CornerRadius = new CornerRadius(3),
            Background = theme.IsDark ? Theme.Tinted(Theme.White, 0.12) : Theme.Tinted(Brushes.Gray, 0.25),
        };
        block.Loaded += (_, _) =>
        {
            if (SystemParameters.ClientAreaAnimation)
            {
                block.BeginAnimation(UIElement.OpacityProperty, new System.Windows.Media.Animation.DoubleAnimation(1, 0.6, TimeSpan.FromSeconds(0.9))
                {
                    AutoReverse = true,
                    RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever,
                });
            }
        };
        return block;
    }
}

public sealed class RecentSessionsView
{
    private const int VisibleRows = 3;
    private const double RowHeight = 22;
    private const double RowSpacing = 1;
    private static readonly TimeSpan AdvanceInterval = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan ActiveWindow = TimeSpan.FromMinutes(5);

    public static FrameworkElement Make(IReadOnlyList<SessionSummary> sessions, bool isLoading, Theme theme, TimeProvider timeProvider, Func<int> readTopIndex, Action<int> saveTopIndex)
    {
        var stack = new StackPanel();
        var header = SectionTitle.Make(Icons.Sessions, Theme.Tinted(Theme.Accent, 0.8), "Recent Sessions", theme, isLoading ? "…" : sessions.Count.ToString(CultureInfo.InvariantCulture));
        header.Margin = new Thickness(12, 12, 12, 8);
        stack.Children.Add(header);

        var rows = isLoading ? VisibleRows : Math.Min(sessions.Count, VisibleRows);
        var viewportHeight = rows * RowHeight + Math.Max(rows - 1, 0) * RowSpacing;

        if (isLoading)
        {
            var skeletons = new StackPanel { Margin = new Thickness(12, 0, 12, 12) };
            for (var index = 0; index < VisibleRows; index++)
            {
                skeletons.Children.Add(SkeletonRow(theme, index));
            }
            stack.Children.Add(skeletons);
        }
        else if (sessions.Count == 0)
        {
            var empty = new StackPanel { Margin = new Thickness(12, 0, 12, 12), HorizontalAlignment = HorizontalAlignment.Center };
            empty.Children.Add(new ContentControl { Content = Icons.Make(Icons.Sleep, 18, theme.TextMuted), HorizontalAlignment = HorizontalAlignment.Center });
            empty.Children.Add(Text.Make("No sessions in the last 10 days", 11, FontWeights.Normal, theme.TextMuted, center: true, margin: new Thickness(0, 6, 0, 0)));
            stack.Children.Add(empty);
        }
        else
        {
            var list = new StackPanel { Margin = new Thickness(12, 0, 4, 0) };
            var now = timeProvider.GetUtcNow();
            for (var index = 0; index < sessions.Count; index++)
            {
                var row = SessionRow(sessions[index], now, theme);
                row.Margin = new Thickness(0, index == 0 ? 0 : RowSpacing, 0, 0);
                list.Children.Add(row);
            }
            var scrollViewer = new ScrollViewer
            {
                Content = list,
                Height = viewportHeight,
                VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                Foreground = theme.TextMuted,
                Margin = new Thickness(0, 0, 4, 12),
            };
            stack.Children.Add(scrollViewer);
            if (sessions.Count > VisibleRows)
            {
                StartAutoAdvance(scrollViewer, sessions.Count, readTopIndex, saveTopIndex);
            }
        }
        return Cards.Make(stack, theme.Card, new Thickness(0), 12);
    }

    private static void StartAutoAdvance(ScrollViewer scrollViewer, int sessionCount, Func<int> readTopIndex, Action<int> saveTopIndex)
    {
        var rowStep = RowHeight + RowSpacing;
        var isHovering = false;
        scrollViewer.MouseEnter += (_, _) => isHovering = true;
        scrollViewer.MouseLeave += (_, _) => isHovering = false;
        scrollViewer.Loaded += (_, _) => scrollViewer.ScrollToVerticalOffset(readTopIndex() * rowStep);

        var advanceTimer = new DispatcherTimer { Interval = AdvanceInterval };
        DispatcherTimer? scrollAnimationTimer = null;
        advanceTimer.Tick += (_, _) =>
        {
            if (isHovering)
            {
                return;
            }
            var maximumTopIndex = Math.Max(sessionCount - VisibleRows, 0);
            var topIndex = readTopIndex() >= maximumTopIndex ? 0 : readTopIndex() + 1;
            saveTopIndex(topIndex);
            var targetOffset = topIndex * rowStep;
            if (!SystemParameters.ClientAreaAnimation)
            {
                scrollViewer.ScrollToVerticalOffset(targetOffset);
                return;
            }
            var startOffset = scrollViewer.VerticalOffset;
            var startedAt = DateTime.UtcNow;
            scrollAnimationTimer?.Stop();
            scrollAnimationTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            scrollAnimationTimer.Tick += (_, _) =>
            {
                var progress = Math.Min(1, (DateTime.UtcNow - startedAt).TotalMilliseconds / 500);
                scrollViewer.ScrollToVerticalOffset(startOffset + (targetOffset - startOffset) * progress);
                if (progress >= 1)
                {
                    scrollAnimationTimer.Stop();
                }
            };
            scrollAnimationTimer.Start();
        };
        scrollViewer.Loaded += (_, _) => advanceTimer.Start();
        scrollViewer.Unloaded += (_, _) =>
        {
            advanceTimer.Stop();
            scrollAnimationTimer?.Stop();
        };
    }

    private static FrameworkElement SessionRow(SessionSummary session, DateTimeOffset now, Theme theme)
    {
        var isActive = now - session.LastActivity < ActiveWindow;
        var row = new DockPanel { Height = RowHeight };
        var dot = Text.Circle(isActive ? Theme.Green : Theme.Tinted(Brushes.Gray, 0.3), 6);
        dot.Margin = new Thickness(0, 0, 8, 0);
        DockPanel.SetDock(dot, Dock.Left);
        row.Children.Add(dot);
        var time = Text.Make(UsageText.RelativeTime(session.LastActivity, now), 10, FontWeights.Normal, theme.TextMuted);
        time.Width = 24;
        time.TextAlignment = TextAlignment.Right;
        DockPanel.SetDock(time, Dock.Right);
        row.Children.Add(time);
        var model = Text.Make(UsageText.ShortModel(session.Model), 10, FontWeights.Bold, Theme.BrushFrom(UsageText.ModelColorHex(session.Model)));
        model.Width = 42;
        model.TextAlignment = TextAlignment.Right;
        DockPanel.SetDock(model, Dock.Right);
        row.Children.Add(model);
        var name = Text.Make(session.ProjectName, 11, FontWeights.Medium, theme.TextPrimary, mono: true);
        name.ToolTip = session.ProjectName;
        row.Children.Add(name);
        return Cards.Make(row, theme.SessionRow, new Thickness(8, 0, 8, 0), 6);
    }

    private static FrameworkElement SkeletonRow(Theme theme, int index)
    {
        var row = new DockPanel { Height = RowHeight };
        var dot = Text.Circle(Theme.Tinted(Brushes.Gray, 0.3), 6);
        dot.Margin = new Thickness(0, 0, 8, 0);
        DockPanel.SetDock(dot, Dock.Left);
        row.Children.Add(dot);
        var time = Skeleton.Make(32, 10, theme);
        DockPanel.SetDock(time, Dock.Right);
        row.Children.Add(time);
        var model = Skeleton.Make(40, 10, theme);
        model.Margin = new Thickness(0, 0, 6, 0);
        DockPanel.SetDock(model, Dock.Right);
        row.Children.Add(model);
        var name = Skeleton.Make(120, 10, theme);
        name.HorizontalAlignment = HorizontalAlignment.Left;
        row.Children.Add(name);
        var card = Cards.Make(row, theme.SessionRow, new Thickness(8, 0, 8, 0), 6);
        card.Margin = new Thickness(0, index == 0 ? 0 : RowSpacing, 0, 0);
        return card;
    }
}
