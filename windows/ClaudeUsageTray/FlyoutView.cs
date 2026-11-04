using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public enum PendingTransition
{
    None,
    SlideFromRight,
    SlideFromLeft,
    Dissolve,
}

public sealed class FlyoutViewState
{
    public AccountListViewState AccountList { get; } = new();
    public SimpleModeWindow SimpleModeWindow { get; set; } = SimpleModeWindow.Weekly;
    public Dictionary<string, int> RecentSessionsTopIndexByConfigFolderPath { get; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, double> LastDrawnRemainingByRingKey { get; } = new(StringComparer.OrdinalIgnoreCase);
    public PendingTransition AccountContentTransition { get; set; }
    public PendingTransition ModeTransition { get; set; }
}

public sealed class FlyoutView
{
    public const double FlyoutWidth = 320;
    public static readonly string AppVersion = "v" + (typeof(FlyoutView).Assembly.GetName().Version is { } version ? $"{version.Major}.{version.Minor}.{version.Build}" : "");

    private readonly AccountStore accountStore;
    private readonly UsageService usageService;
    private readonly AppSettings settings;
    private readonly FlyoutViewState viewState;
    private readonly TimeProvider timeProvider;
    private readonly string homeFolderPath;
    private readonly Action rerender;
    private readonly Action quit;
    private readonly Action<Task> reportFailure;
    private readonly bool reduceMotion;
    private Theme theme = Theme.Dark;

    public TextBlock? LastUpdatedText { get; private set; }

    public FlyoutView(AccountStore accountStore, UsageService usageService, AppSettings settings, FlyoutViewState viewState,
        TimeProvider timeProvider, string homeFolderPath, Action rerender, Action quit, Action<Task> reportFailure)
    {
        this.accountStore = accountStore;
        this.usageService = usageService;
        this.settings = settings;
        this.viewState = viewState;
        this.timeProvider = timeProvider;
        this.homeFolderPath = homeFolderPath;
        this.rerender = rerender;
        this.quit = quit;
        this.reportFailure = reportFailure;
        reduceMotion = !SystemParameters.ClientAreaAnimation;
    }

    private IReadOnlyList<ClaudeAccount> ShownAccounts => accountStore.ShownAccounts;

    private bool IsAccountColorShown => ShownAccounts.Count > 1;

    private ClaudeAccount? SelectedAccount => accountStore.SelectedAccount(settings.SelectedConfigFolderPath);

    private FlyoutAccountContent AccountContent => FlyoutAccountContentChooser.Choose(settings.MultiAccountSimpleMode, ShownAccounts.Count);

    private Brush AccountColorBrush(ClaudeAccount account) => Theme.BrushFrom(AccountColor.HexFor(accountStore.PositionOf(account)));

    public FrameworkElement Build()
    {
        theme = Theme.For(settings.DarkMode);
        var root = new StackPanel { Margin = new Thickness(16, 10, 16, 16) };
        root.Children.Add(HeaderSection());

        var accountContent = AccountContent == FlyoutAccountContent.SimpleList ? SimpleAccountList() : StandardAccountContent();
        accountContent.Margin = new Thickness(0, 8, 0, 0);
        ApplyTransition(accountContent, viewState.ModeTransition);
        viewState.ModeTransition = PendingTransition.None;
        root.Children.Add(accountContent);

        var settingsSection = SettingsSection();
        settingsSection.Margin = new Thickness(0, 8, 0, 0);
        root.Children.Add(settingsSection);
        var footer = FooterSection();
        footer.Margin = new Thickness(0, 8, 0, 0);
        root.Children.Add(footer);
        return root;
    }

    private FrameworkElement HeaderSection()
    {
        var header = new DockPanel();
        var controls = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        controls.Children.Add(AppearanceToggle());
        var simpleModeButton = Buttons.Make(Icons.Make(Icons.SimpleMode, 11, settings.MultiAccountSimpleMode ? Theme.White : theme.TextMuted),
            theme.TextPrimary, settings.MultiAccountSimpleMode ? Theme.Accent : theme.Card, System.Windows.Media.Brushes.Transparent, () =>
            {
                viewState.ModeTransition = PendingTransition.Dissolve;
                settings.MultiAccountSimpleMode = !settings.MultiAccountSimpleMode;
            }, "Simple Mode", new Thickness(7, 5, 7, 5));
        simpleModeButton.Margin = new Thickness(6, 0, 0, 0);
        controls.Children.Add(simpleModeButton);
        DockPanel.SetDock(controls, Dock.Right);
        header.Children.Add(controls);

        var title = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var titleText = Text.Make("Claude Usage", 16, FontWeights.Bold, theme.TextPrimary);
        titleText.FontFamily = Theme.DisplayFont;
        title.Children.Add(titleText);
        var version = Text.Make(AppVersion, 11, FontWeights.Medium, theme.TextMuted, margin: new Thickness(6, 3, 0, 0));
        title.Children.Add(version);
        header.Children.Add(title);
        return header;
    }

    private FrameworkElement AppearanceToggle()
    {
        var segments = new StackPanel { Orientation = Orientation.Horizontal };
        segments.Children.Add(AppearanceSegment(Icons.Moon, "Dark mode", isSelected: settings.DarkMode, () => settings.DarkMode = true));
        segments.Children.Add(AppearanceSegment(Icons.Sun, "Light mode", isSelected: !settings.DarkMode, () => settings.DarkMode = false));
        return Cards.Make(segments, theme.Segment, new Thickness(2), 8);
    }

    private Button AppearanceSegment(string iconPath, string label, bool isSelected, Action select) =>
        Buttons.Make(Icons.Make(iconPath, 10, isSelected ? Theme.White : theme.TextMuted), theme.TextPrimary,
            isSelected ? Theme.Accent : System.Windows.Media.Brushes.Transparent, System.Windows.Media.Brushes.Transparent, select, label, new Thickness(7, 6, 7, 6));

    private FrameworkElement StandardAccountContent()
    {
        var stack = new StackPanel();
        if (IsAccountColorShown)
        {
            var tabs = ShownAccounts.Select(account => new AccountTab(
                account.ConfigFolderPath,
                account.LabelOrFolderName,
                AccountColorBrush(account),
                usageService.UsageFor(account).SessionWindow?.Remaining,
                usageService.UsageFor(account).WeeklyWindow?.Remaining)).ToList();
            stack.Children.Add(AccountTabsView.Make(tabs, SelectedAccount?.ConfigFolderPath, theme, SelectAccount));
        }
        if (SelectedAccount is { } selectedAccount)
        {
            var section = SelectedAccountSection(selectedAccount);
            section.Margin = new Thickness(0, IsAccountColorShown ? 8 : 0, 0, 0);
            ApplyTransition(section, viewState.AccountContentTransition);
            viewState.AccountContentTransition = PendingTransition.None;
            stack.Children.Add(new Border { ClipToBounds = true, Child = section });
        }
        else
        {
            var none = Text.Make("No accounts shown. Turn one on under Accounts.", 12, FontWeights.Normal, theme.TextMuted, center: true);
            none.TextWrapping = TextWrapping.Wrap;
            stack.Children.Add(Cards.Make(none, theme.Card, new Thickness(14), 12));
        }
        return stack;
    }

    private void SelectAccount(string configFolderPath)
    {
        var shownAccounts = ShownAccounts.ToList();
        var selectedIndex = Math.Max(0, shownAccounts.FindIndex(account => SelectedAccount is { } selected && ClaudeAccount.IsSamePath(account.ConfigFolderPath, selected.ConfigFolderPath)));
        var newIndex = Math.Max(0, shownAccounts.FindIndex(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, configFolderPath)));
        if (newIndex == selectedIndex)
        {
            return;
        }
        viewState.AccountContentTransition = newIndex < selectedIndex ? PendingTransition.SlideFromLeft : PendingTransition.SlideFromRight;
        settings.SelectedConfigFolderPath = configFolderPath;
    }

    private FrameworkElement SelectedAccountSection(ClaudeAccount account)
    {
        var usage = usageService.UsageFor(account);
        var stack = new StackPanel();
        AddSpaced(stack, AccountCard(account, usage));
        AddSpaced(stack, LoginProblemNote.Make(usage.LoginStatus, theme));
        AddSpaced(stack, ModelUsageSection.Make(usage, theme, timeProvider));
        AddSpaced(stack, ExtraUsageSection.Make(usage, theme));
        AddSpaced(stack, RecentSessionsView.Make(usage.TokenActivity.RecentSessions, !usage.TokenActivityLoaded, theme, timeProvider,
            () => viewState.RecentSessionsTopIndexByConfigFolderPath.GetValueOrDefault(account.ConfigFolderPath),
            topIndex => viewState.RecentSessionsTopIndexByConfigFolderPath[account.ConfigFolderPath] = topIndex));
        AddSpaced(stack, TokenHistoryView.Make(usage.TokenActivity, !usage.TokenActivityLoaded, theme));
        return stack;
    }

    private FrameworkElement AccountCard(ClaudeAccount account, AccountUsage usage)
    {
        var stack = new StackPanel();
        var header = new DockPanel { Margin = new Thickness(4, 0, 4, 12) };
        if (IsAccountColorShown)
        {
            var dot = Text.Circle(AccountColorBrush(account));
            dot.Margin = new Thickness(0, 0, 6, 0);
            DockPanel.SetDock(dot, Dock.Left);
            header.Children.Add(dot);
        }
        var planColor = usage.HasUsageData ? Theme.Accent : theme.TextMuted;
        var plan = Cards.Make(Text.Make(usage.HasUsageData ? usage.PlanName : "—", 11, FontWeights.SemiBold, planColor), Theme.Tinted(planColor, 0.15), new Thickness(10, 4, 10, 4), 12);
        plan.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(plan, Dock.Right);
        header.Children.Add(plan);
        var names = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        names.Children.Add(Text.Make(account.LabelOrFolderName, 13, FontWeights.Bold, theme.TextPrimary));
        var path = Text.Make(ClaudeAccount.DisplayPath(account.ConfigFolderPath, homeFolderPath), 10, FontWeights.Normal, theme.TextMuted, mono: true, margin: new Thickness(0, 1, 0, 0));
        path.ToolTip = account.ConfigFolderPath;
        names.Children.Add(path);
        header.Children.Add(names);
        stack.Children.Add(header);

        var rings = new Grid { Margin = new Thickness(0, 0, 0, 16) };
        rings.ColumnDefinitions.Add(new ColumnDefinition());
        rings.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        rings.ColumnDefinitions.Add(new ColumnDefinition());
        var sessionRing = Ring($"{account.ConfigFolderPath}|session", usage.SessionWindow, 70, 7, "Session (5h)", compactReset: false);
        var weeklyRing = Ring($"{account.ConfigFolderPath}|weekly", usage.WeeklyWindow, 70, 7, "Weekly (7d)", compactReset: false);
        Grid.SetColumn(weeklyRing, 2);
        rings.Children.Add(sessionRing);
        rings.Children.Add(weeklyRing);
        stack.Children.Add(rings);
        return Cards.Make(stack, theme.Card, new Thickness(8, 12, 8, 0), 14);
    }

    private FrameworkElement Ring(string ringKey, UsageWindow? window, double size, double lineWidth, string? label, bool compactReset)
    {
        var remaining = window?.Remaining;
        var startingRemaining = viewState.LastDrawnRemainingByRingKey.GetValueOrDefault(ringKey);
        viewState.LastDrawnRemainingByRingKey[ringKey] = remaining ?? 0;
        return UsageRingView.Make(remaining, size, lineWidth, label,
            window is null ? null : ResetClock.ResetClockString(window, timeProvider), theme, compactReset, startingRemaining, reduceMotion);
    }

    private FrameworkElement SimpleAccountList()
    {
        var stack = new StackPanel();
        stack.Children.Add(SimpleModeWindowSwitch());

        var shownAccounts = ShownAccounts;
        var ringSize = shownAccounts.Count > 3 ? 48 : shownAccounts.Count > 2 ? 58 : 70;
        var isCompact = shownAccounts.Count > 2;
        var columns = new System.Windows.Controls.Primitives.UniformGrid { Rows = 1, Columns = shownAccounts.Count };
        foreach (var account in shownAccounts)
        {
            var usage = usageService.UsageFor(account);
            var window = viewState.SimpleModeWindow == SimpleModeWindow.Session ? usage.SessionWindow : usage.WeeklyWindow;
            var column = new StackPanel { Margin = new Thickness(3, 0, 3, 0) };
            var name = new DockPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(2, 0, 2, 8) };
            var dot = Text.Circle(AccountColorBrush(account));
            dot.Margin = new Thickness(0, 0, 4, 0);
            DockPanel.SetDock(dot, Dock.Left);
            name.Children.Add(dot);
            name.Children.Add(Text.Make(account.LabelOrFolderName, isCompact ? 11 : 12, FontWeights.SemiBold, theme.TextPrimary));
            column.Children.Add(name);
            column.Children.Add(Ring($"{account.ConfigFolderPath}|{viewState.SimpleModeWindow}", window, ringSize, ringSize > 60 ? 7 : 6, null, isCompact));
            columns.Children.Add(column);
        }
        var ringsCard = Cards.Make(columns, theme.Card, new Thickness(4, 12, 4, 12), 14);
        ApplyTransition(columns, viewState.AccountContentTransition);
        viewState.AccountContentTransition = PendingTransition.None;
        ringsCard.ClipToBounds = true;
        ringsCard.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(ringsCard);

        foreach (var account in shownAccounts)
        {
            AddSpaced(stack, LoginProblemNote.Make(usageService.UsageFor(account).LoginStatus, theme, account.LabelOrFolderName, AccountColorBrush(account)));
        }
        return stack;
    }

    private FrameworkElement SimpleModeWindowSwitch()
    {
        var grid = new System.Windows.Controls.Primitives.UniformGrid { Rows = 1, Columns = 2 };
        foreach (var window in new[] { SimpleModeWindow.Session, SimpleModeWindow.Weekly })
        {
            var isSelected = viewState.SimpleModeWindow == window;
            var button = Buttons.Make(Text.Make(window.ToString(), 11, FontWeights.SemiBold, isSelected ? Theme.White : theme.TextMuted, center: true),
                theme.TextPrimary, isSelected ? Theme.Accent : System.Windows.Media.Brushes.Transparent, System.Windows.Media.Brushes.Transparent, () =>
                {
                    if (viewState.SimpleModeWindow == window)
                    {
                        return;
                    }
                    viewState.AccountContentTransition = window == SimpleModeWindow.Weekly ? PendingTransition.SlideFromRight : PendingTransition.SlideFromLeft;
                    viewState.SimpleModeWindow = window;
                    rerender();
                }, padding: new Thickness(0, 4, 0, 4));
            button.Margin = new Thickness(1, 0, 1, 0);
            grid.Children.Add(button);
        }
        return Cards.Make(grid, theme.Segment, new Thickness(3), 8);
    }

    private FrameworkElement SettingsSection()
    {
        var stack = new StackPanel();
        var title = new StackPanel { Orientation = Orientation.Horizontal };
        title.Children.Add(Icons.Make(Icons.Gear, 11, theme.TextMuted));
        title.Children.Add(Text.Make("Tray Options", 13, FontWeights.SemiBold, theme.TextPrimary, margin: new Thickness(6, 0, 0, 0)));
        stack.Children.Add(title);
        stack.Children.Add(SettingCheckBox("Show Claude logo", settings.ShowLogo, isChecked => settings.ShowLogo = isChecked));
        stack.Children.Add(SettingCheckBox("Show reset time", settings.ShowResetTime, isChecked => settings.ShowResetTime = isChecked));
        stack.Children.Add(new Border { Height = 1, Background = theme.Hairline, Margin = new Thickness(0, 8, 0, 8) });
        stack.Children.Add(new AccountListView(accountStore, usageService, viewState.AccountList, theme, homeFolderPath, rerender).Make());
        return Cards.Make(stack, theme.Card, new Thickness(12), 12);
    }

    private CheckBox SettingCheckBox(string label, bool isChecked, Action<bool> setChecked)
    {
        var checkBox = new CheckBox
        {
            Style = (Style)Application.Current.Resources["TrayCheckBox"],
            Content = Text.Make(label, 12, FontWeights.Normal, theme.TextPrimary),
            IsChecked = isChecked,
            BorderBrush = theme.TextMuted,
            Margin = new Thickness(0, 8, 0, 0),
        };
        checkBox.Click += (_, _) => setChecked(checkBox.IsChecked == true);
        return checkBox;
    }

    private DateTimeOffset? FooterLastUpdated => AccountContent switch
    {
        FlyoutAccountContent.SimpleList => ShownAccounts.Select(account => usageService.UsageFor(account).LastUpdated).Max(),
        _ => SelectedAccount is { } account ? usageService.UsageFor(account).LastUpdated : null,
    };

    public void UpdateLastUpdatedText()
    {
        if (LastUpdatedText is not null && FooterLastUpdated is { } lastUpdated)
        {
            LastUpdatedText.Text = UsageText.LastUpdatedText(lastUpdated, timeProvider.GetUtcNow());
        }
    }

    private FrameworkElement FooterSection()
    {
        var stack = new StackPanel();
        stack.Children.Add(new Border { Height = 1, Background = theme.Hairline, Margin = new Thickness(0, 0, 0, 8) });
        var row = new DockPanel();
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        actions.Children.Add(Buttons.Labeled(Icons.Refresh, "Refresh", Theme.Accent, theme, () => reportFailure(usageService.RefreshAsync(force: true))));
        var quitButton = Buttons.Labeled(Icons.Power, "Quit", Theme.Red, theme, quit);
        quitButton.Margin = new Thickness(6, 0, 0, 0);
        quitButton.ToolTip = "Quit (Ctrl+Q)";
        actions.Children.Add(quitButton);
        DockPanel.SetDock(actions, Dock.Right);
        row.Children.Add(actions);
        LastUpdatedText = Text.Make("", 10, FontWeights.Normal, theme.TextMuted);
        UpdateLastUpdatedText();
        row.Children.Add(LastUpdatedText);
        stack.Children.Add(row);

        var linkContent = new StackPanel { Orientation = Orientation.Horizontal };
        linkContent.Children.Add(Text.Make("Open claude.ai", 10, FontWeights.Medium, theme.TextMuted));
        linkContent.Children.Add(Icons.Make(Icons.External, 8, theme.TextMuted));
        var link = Buttons.Make(linkContent, theme.TextMuted, System.Windows.Media.Brushes.Transparent, theme.Hairline,
            () => Process.Start(new ProcessStartInfo("https://claude.ai") { UseShellExecute = true }), padding: new Thickness(6, 2, 6, 2));
        link.HorizontalAlignment = HorizontalAlignment.Right;
        link.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(link);

        if (AccountContent == FlyoutAccountContent.Standard
            && SelectedAccount is { } account
            && usageService.UsageFor(account) is { LoadState: UsageLoadState.Failed failed } usage
            && !usage.LoginStatus.IsLoginProblem())
        {
            var error = Text.Make(UsageText.FriendlyErrorMessage(failed.Message), 10, FontWeights.Normal, theme.TextMuted, center: true, margin: new Thickness(0, 8, 0, 0));
            error.TextWrapping = TextWrapping.Wrap;
            error.TextTrimming = TextTrimming.CharacterEllipsis;
            error.MaxHeight = 42;
            stack.Children.Add(error);
        }
        return stack;
    }

    private static void AddSpaced(StackPanel stack, FrameworkElement? element)
    {
        if (element is null)
        {
            return;
        }
        if (stack.Children.Count > 0)
        {
            element.Margin = new Thickness(element.Margin.Left, element.Margin.Top + 8, element.Margin.Right, element.Margin.Bottom);
        }
        stack.Children.Add(element);
    }

    private void ApplyTransition(FrameworkElement element, PendingTransition transition)
    {
        if (transition == PendingTransition.None || reduceMotion)
        {
            return;
        }
        var duration = TimeSpan.FromMilliseconds(300);
        var easing = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        element.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, duration) { EasingFunction = easing });
        if (transition == PendingTransition.Dissolve)
        {
            return;
        }
        var offset = new TranslateTransform();
        element.RenderTransform = offset;
        var from = transition == PendingTransition.SlideFromRight ? 40 : -40;
        offset.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(from, 0, duration) { EasingFunction = easing });
    }
}
