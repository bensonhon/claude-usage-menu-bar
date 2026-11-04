using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public sealed class FlyoutWindow : Window
{
    private const double ShadowMargin = 16;
    private const double ScreenEdgeGap = 12 - ShadowMargin;
    private static readonly TimeSpan ReopenGuard = TimeSpan.FromMilliseconds(350);

    private readonly AccountStore accountStore;
    private readonly AppSettings settings;
    private readonly UsageService usageService;
    private readonly FlyoutView flyoutView;
    private readonly Border chrome;
    private readonly ScrollViewer scrollViewer;
    private readonly TranslateTransform openOffset = new();
    private readonly DispatcherTimer lastUpdatedTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly Action quit;
    private readonly Action<Task> reportFailure;
    private bool isClosing;
    private bool isRebuilding;
    private bool isRebuildQueued;
    private DateTime hiddenAt = DateTime.MinValue;

    public FlyoutWindow(AccountStore accountStore, UsageService usageService, AppSettings settings, TimeProvider timeProvider, string homeFolderPath, Action quit, Action<Task> reportFailure)
    {
        this.accountStore = accountStore;
        this.settings = settings;
        this.usageService = usageService;
        this.quit = quit;
        this.reportFailure = reportFailure;
        flyoutView = new FlyoutView(accountStore, usageService, settings, new FlyoutViewState(), timeProvider, homeFolderPath, Rebuild, quit, reportFailure);

        Title = "Claude Usage";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = true;
        SizeToContent = SizeToContent.Height;
        Width = FlyoutView.FlyoutWidth + ShadowMargin * 2;
        FontFamily = Theme.TextFont;
        UseLayoutRounding = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);

        scrollViewer = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
        };
        chrome = new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(ShadowMargin),
            Child = scrollViewer,
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0.45 },
            RenderTransform = openOffset,
        };
        Content = chrome;

        Deactivated += (_, _) => HideFlyout();
        PreviewKeyDown += OnPreviewKeyDown;
        SizeChanged += (_, _) => PlaceAboveTaskbar();
        lastUpdatedTimer.Tick += (_, _) => flyoutView.UpdateLastUpdatedText();

        usageService.UsageChanged += RebuildIfVisible;
        accountStore.AccountsChanged += RebuildIfVisible;
        settings.SettingsChanged += RebuildIfVisible;
    }

    public bool IsOpen => IsVisible && !isClosing;

    public void Toggle()
    {
        if (IsOpen)
        {
            HideFlyout();
            return;
        }
        if (DateTime.UtcNow - hiddenAt < ReopenGuard)
        {
            return;
        }
        ShowFlyout();
    }

    public void ShowFlyout()
    {
        isClosing = false;
        Rebuild();
        Opacity = 0;
        Show();
        UpdateLayout();
        PlaceAboveTaskbar();
        Activate();
        lastUpdatedTimer.Start();

        var duration = SystemParameters.ClientAreaAnimation ? TimeSpan.FromMilliseconds(240) : TimeSpan.Zero;
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, duration) { EasingFunction = easing });
        openOffset.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(14, 0, duration) { EasingFunction = easing });

        reportFailure(usageService.RefreshAsync());
    }

    public void HideFlyout()
    {
        if (!IsVisible || isClosing)
        {
            return;
        }
        isClosing = true;
        hiddenAt = DateTime.UtcNow;
        lastUpdatedTimer.Stop();
        var fadeOut = new DoubleAnimation(Opacity, 0, SystemParameters.ClientAreaAnimation ? TimeSpan.FromMilliseconds(130) : TimeSpan.Zero);
        fadeOut.Completed += (_, _) =>
        {
            if (isClosing)
            {
                Hide();
                isClosing = false;
            }
        };
        BeginAnimation(OpacityProperty, fadeOut);
    }

    private void RebuildIfVisible()
    {
        if (!IsVisible || isClosing || isRebuildQueued)
        {
            return;
        }
        isRebuildQueued = true;
        Dispatcher.BeginInvoke(DispatcherPriority.Background, () =>
        {
            isRebuildQueued = false;
            if (IsVisible && !isClosing)
            {
                Rebuild();
            }
        });
    }

    private void Rebuild()
    {
        if (isRebuilding)
        {
            RebuildIfVisible();
            return;
        }
        isRebuilding = true;
        try
        {
            RebuildContent();
        }
        finally
        {
            isRebuilding = false;
        }
    }

    private void RebuildContent()
    {
        var theme = Theme.For(settings.DarkMode);
        var scrollOffset = scrollViewer.VerticalOffset;
        var focusedField = Keyboard.FocusedElement as TextBox;
        var focusedFieldKey = focusedField?.Uid;
        var caretIndex = focusedField?.CaretIndex ?? 0;

        chrome.Background = theme.Background;
        chrome.BorderBrush = theme.Hairline;
        scrollViewer.Foreground = theme.TextMuted;
        scrollViewer.MaxHeight = MaximumContentHeight();
        scrollViewer.Content = flyoutView.Build();
        scrollViewer.UpdateLayout();
        scrollViewer.ScrollToVerticalOffset(scrollOffset);

        if (!string.IsNullOrEmpty(focusedFieldKey) && FindField(scrollViewer, focusedFieldKey) is { } restoredField)
        {
            restoredField.Focus();
            restoredField.CaretIndex = Math.Min(caretIndex, restoredField.Text.Length);
        }
    }

    private static TextBox? FindField(DependencyObject parent, string fieldKey)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is TextBox field && field.Uid == fieldKey)
            {
                return field;
            }
            if (FindField(child, fieldKey) is { } found)
            {
                return found;
            }
        }
        return null;
    }

    private double MaximumContentHeight()
    {
        var workArea = CurrentWorkAreaInDips();
        return Math.Max(360, workArea.Height * 0.85);
    }

    private Rect CurrentWorkAreaInDips()
    {
        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var dpiScale = VisualTreeHelper.GetDpi(this);
        var workingArea = screen.WorkingArea;
        return new Rect(workingArea.Left / dpiScale.DpiScaleX, workingArea.Top / dpiScale.DpiScaleY,
            workingArea.Width / dpiScale.DpiScaleX, workingArea.Height / dpiScale.DpiScaleY);
    }

    private void PlaceAboveTaskbar()
    {
        if (!IsVisible)
        {
            return;
        }
        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var workArea = CurrentWorkAreaInDips();
        var bounds = screen.Bounds;
        var workingArea = screen.WorkingArea;
        var taskbarEdge = TaskbarEdgeFor(bounds, workingArea);

        Left = taskbarEdge == TaskbarEdge.Left ? workArea.Left + ScreenEdgeGap : workArea.Right - ActualWidth - ScreenEdgeGap;
        Top = taskbarEdge == TaskbarEdge.Top ? workArea.Top + ScreenEdgeGap : workArea.Bottom - ActualHeight - ScreenEdgeGap;
    }

    private enum TaskbarEdge
    {
        Bottom,
        Top,
        Left,
        Right,
    }

    private static TaskbarEdge TaskbarEdgeFor(System.Drawing.Rectangle bounds, System.Drawing.Rectangle workingArea)
    {
        if (workingArea.Top > bounds.Top) return TaskbarEdge.Top;
        if (workingArea.Left > bounds.Left) return TaskbarEdge.Left;
        if (workingArea.Right < bounds.Right) return TaskbarEdge.Right;
        return TaskbarEdge.Bottom;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs keyEvent)
    {
        if (keyEvent.Key == Key.Escape)
        {
            HideFlyout();
            keyEvent.Handled = true;
        }
        else if (keyEvent.Key == Key.Q && Keyboard.Modifiers == ModifierKeys.Control)
        {
            quit();
            keyEvent.Handled = true;
        }
    }
}
