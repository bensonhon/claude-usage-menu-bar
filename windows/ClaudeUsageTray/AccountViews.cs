using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using ClaudeUsageTray.Core;

namespace ClaudeUsageTray;

public sealed record AccountTab(string ConfigFolderPath, string Label, System.Windows.Media.Brush Color, double? SessionRemaining, double? WeeklyRemaining);

public static class AccountTabsView
{
    public static FrameworkElement Make(IReadOnlyList<AccountTab> tabs, string? selectedConfigFolderPath, Theme theme, Action<string> onSelect)
    {
        var isStacked = tabs.Count > 2;
        var grid = new UniformGrid { Rows = 1, Columns = tabs.Count };
        foreach (var tab in tabs)
        {
            var isSelected = selectedConfigFolderPath is not null && ClaudeAccount.IsSamePath(tab.ConfigFolderPath, selectedConfigFolderPath);
            var content = new DockPanel { HorizontalAlignment = HorizontalAlignment.Center, LastChildFill = true };
            var dot = Text.Circle(tab.Color);
            dot.Margin = new Thickness(0, 0, 4, 0);
            DockPanel.SetDock(dot, Dock.Left);
            content.Children.Add(dot);
            var remaining = RemainingView(tab, isStacked, theme);
            remaining.Margin = new Thickness(4, 0, 0, 0);
            DockPanel.SetDock(remaining, Dock.Right);
            content.Children.Add(remaining);
            content.Children.Add(Text.Make(tab.Label, 12, FontWeights.SemiBold, isSelected ? theme.TextPrimary : theme.TextMuted));

            var button = Buttons.Make(content, theme.TextPrimary, isSelected ? theme.Background : System.Windows.Media.Brushes.Transparent,
                System.Windows.Media.Brushes.Transparent, () => onSelect(tab.ConfigFolderPath),
                UsageText.AccountTabTooltip(tab.SessionRemaining, tab.WeeklyRemaining), new Thickness(3, 6, 3, 6));
            button.Margin = new Thickness(1, 0, 1, 0);
            if (isSelected)
            {
                button.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 3, ShadowDepth = 1, Opacity = 0.2, Direction = 270 };
            }
            grid.Children.Add(button);
        }
        return Cards.Make(grid, theme.Segment, new Thickness(3), 9);
    }

    private static FrameworkElement RemainingView(AccountTab tab, bool isStacked, Theme theme)
    {
        if (isStacked)
        {
            var stacked = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            stacked.Children.Add(Text.Make(UsageText.PercentText(tab.SessionRemaining), 11, FontWeights.SemiBold, theme.ForRemaining(tab.SessionRemaining)));
            var weekly = Text.Make(UsageText.PercentText(tab.WeeklyRemaining), 9, FontWeights.SemiBold, theme.ForRemaining(tab.WeeklyRemaining));
            weekly.Margin = new Thickness(0, -2, 0, 0);
            stacked.Children.Add(weekly);
            return stacked;
        }
        var inline = new StackPanel { Orientation = Orientation.Horizontal };
        inline.Children.Add(Text.Make(UsageText.PercentText(tab.SessionRemaining), 11, FontWeights.SemiBold, theme.ForRemaining(tab.SessionRemaining)));
        inline.Children.Add(Text.Make(" / ", 11, FontWeights.SemiBold, Theme.Tinted(theme.TextMuted, 0.6)));
        inline.Children.Add(Text.Make(UsageText.PercentText(tab.WeeklyRemaining), 11, FontWeights.SemiBold, theme.ForRemaining(tab.WeeklyRemaining)));
        return inline;
    }
}

public sealed class AccountListViewState
{
    public bool IsExpanded { get; set; }
    public bool IsEditing { get; set; }
    public bool IsAdding { get; set; }
    public string TypedPath { get; set; } = "";
    public string TypedLabel { get; set; } = "";
    public string? AddConfigFolderErrorText { get; set; }
}

public sealed class AccountListView
{
    public const string TypedPathFieldKey = "typed-path";
    public const string TypedLabelFieldKey = "typed-label";
    public static string LabelFieldKey(string configFolderPath) => "label:" + configFolderPath;

    private readonly AccountStore accountStore;
    private readonly UsageService usageService;
    private readonly AccountListViewState viewState;
    private readonly Theme theme;
    private readonly string homeFolderPath;
    private readonly Action rerender;

    public AccountListView(AccountStore accountStore, UsageService usageService, AccountListViewState viewState, Theme theme, string homeFolderPath, Action rerender)
    {
        this.accountStore = accountStore;
        this.usageService = usageService;
        this.viewState = viewState;
        this.theme = theme;
        this.homeFolderPath = homeFolderPath;
        this.rerender = rerender;
    }

    public FrameworkElement Make()
    {
        var stack = new StackPanel();
        stack.Children.Add(ExpandButton());
        if (!viewState.IsExpanded)
        {
            return stack;
        }
        var list = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        foreach (var account in accountStore.Accounts)
        {
            var row = viewState.IsEditing ? EditingRow(account) : AccountRow(account);
            row.Margin = new Thickness(0, 0, 0, 6);
            list.Children.Add(row);
        }
        if (viewState.IsAdding)
        {
            list.Children.Add(AddConfigFolderForm());
        }
        else
        {
            var addButton = Buttons.Labeled(Icons.Plus, "Add config folder", Theme.Accent, theme, () =>
            {
                viewState.TypedPath = "";
                viewState.TypedLabel = "";
                viewState.AddConfigFolderErrorText = null;
                viewState.IsEditing = false;
                viewState.IsAdding = true;
                rerender();
            });
            addButton.HorizontalAlignment = HorizontalAlignment.Left;
            list.Children.Add(addButton);
        }
        var editButton = Buttons.Labeled(null, viewState.IsEditing ? "Done" : "Edit labels & order", Theme.Accent, theme, () =>
        {
            viewState.IsEditing = !viewState.IsEditing;
            viewState.IsAdding = false;
            rerender();
        });
        editButton.HorizontalAlignment = HorizontalAlignment.Right;
        editButton.Margin = new Thickness(0, 6, 0, 0);
        list.Children.Add(editButton);
        stack.Children.Add(list);
        return stack;
    }

    private FrameworkElement ExpandButton()
    {
        var content = new DockPanel();
        var chevron = Icons.Make(Icons.ChevronDown, 10, theme.TextMuted);
        chevron.RenderTransformOrigin = new Point(0.5, 0.5);
        chevron.RenderTransform = new System.Windows.Media.RotateTransform(viewState.IsExpanded ? 180 : 0);
        DockPanel.SetDock(chevron, Dock.Right);
        content.Children.Add(chevron);
        var label = new StackPanel { Orientation = Orientation.Horizontal };
        label.Children.Add(Text.Make("Accounts", 12, FontWeights.Normal, theme.TextPrimary));
        label.Children.Add(Text.Make($"{accountStore.ShownAccounts.Count} of {accountStore.Accounts.Count} shown", 12, FontWeights.Normal, theme.TextMuted, margin: new Thickness(4, 0, 0, 0)));
        content.Children.Add(label);
        var button = Buttons.Make(content, theme.TextPrimary, System.Windows.Media.Brushes.Transparent, theme.Hairline, () =>
        {
            viewState.IsExpanded = !viewState.IsExpanded;
            rerender();
        }, padding: new Thickness(8, 5, 8, 5));
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        return button;
    }

    private FrameworkElement AccountRow(ClaudeAccount account)
    {
        var row = new DockPanel();
        var toggle = new CheckBox
        {
            Style = (Style)Application.Current.Resources["TraySwitch"],
            IsChecked = account.IsShownInTray,
            BorderBrush = theme.TextMuted,
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Show in tray",
        };
        System.Windows.Automation.AutomationProperties.SetName(toggle, $"Show {account.LabelOrFolderName} in tray");
        toggle.Click += (_, _) => accountStore.SetShownInTray(toggle.IsChecked == true, account.ConfigFolderPath);
        DockPanel.SetDock(toggle, Dock.Left);
        row.Children.Add(toggle);

        var dot = Text.Circle(Theme.BrushFrom(AccountColor.HexFor(accountStore.PositionOf(account))));
        dot.Margin = new Thickness(8, 0, 8, 0);
        DockPanel.SetDock(dot, Dock.Left);
        row.Children.Add(dot);

        var chips = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) };
        var (chipText, chipHex) = UsageText.LoginStatusChip(usageService.UsageFor(account).LoginStatus);
        chips.Children.Add(Chip(chipText, chipHex is null ? theme.TextMuted : Theme.BrushFrom(chipHex)));
        if (account.IsFoundAutomatically)
        {
            var foundChip = Chip("Found automatically", Theme.BrushFrom("#60A5FA"));
            foundChip.Margin = new Thickness(0, 3, 0, 0);
            chips.Children.Add(foundChip);
        }
        DockPanel.SetDock(chips, Dock.Right);
        row.Children.Add(chips);

        row.Children.Add(NameAndPath(account.LabelOrFolderName, account.ConfigFolderPath));
        return Cards.Make(row, theme.Row, new Thickness(8), 9);
    }

    private FrameworkElement EditingRow(ClaudeAccount account)
    {
        var position = accountStore.PositionOf(account);
        var row = new DockPanel();
        var orderButtons = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        var upButton = OrderButton(Icons.ChevronUp, "Move up", position > 0, () => accountStore.MoveUp(account.ConfigFolderPath));
        var downButton = OrderButton(Icons.ChevronDown, "Move down", position < accountStore.Accounts.Count - 1, () => accountStore.MoveDown(account.ConfigFolderPath));
        downButton.Margin = new Thickness(0, 2, 0, 0);
        orderButtons.Children.Add(upButton);
        orderButtons.Children.Add(downButton);
        DockPanel.SetDock(orderButtons, Dock.Left);
        row.Children.Add(orderButtons);

        if (accountStore.IsRemovable(account))
        {
            var removeButton = Buttons.Labeled(null, "Remove", Theme.Red, theme, () => accountStore.Remove(account.ConfigFolderPath));
            removeButton.Margin = new Thickness(8, 0, 0, 0);
            removeButton.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(removeButton, Dock.Right);
            row.Children.Add(removeButton);
        }

        var fields = new StackPanel();
        var labelField = TextField(account.Label, ClaudeAccount.DefaultLabel(account.ConfigFolderPath), LabelFieldKey(account.ConfigFolderPath), mono: false);
        labelField.LostKeyboardFocus += (_, _) => CommitLabel(account, labelField.Text);
        labelField.KeyDown += (_, keyEvent) =>
        {
            if (keyEvent.Key == Key.Enter)
            {
                CommitLabel(account, labelField.Text);
            }
        };
        fields.Children.Add(labelField);
        fields.Children.Add(PathText(account.ConfigFolderPath, new Thickness(0, 3, 0, 0)));
        row.Children.Add(fields);
        return Cards.Make(row, theme.Row, new Thickness(8), 9);
    }

    private void CommitLabel(ClaudeAccount account, string label)
    {
        var current = accountStore.Accounts.FirstOrDefault(candidate => ClaudeAccount.IsSamePath(candidate.ConfigFolderPath, account.ConfigFolderPath));
        if (current is not null && current.Label != label)
        {
            accountStore.SetLabel(label, account.ConfigFolderPath);
        }
    }

    private FrameworkElement AddConfigFolderForm()
    {
        var form = new StackPanel();
        var pathField = TextField(viewState.TypedPath, "~\\.claude-work", TypedPathFieldKey, mono: true);
        var preview = Text.Make(UsageText.LoginFilePreview(viewState.TypedPath, homeFolderPath), 10, FontWeights.Normal, theme.TextMuted, mono: true, margin: new Thickness(0, 6, 0, 0));
        preview.TextWrapping = TextWrapping.Wrap;
        preview.TextTrimming = TextTrimming.None;
        var errorText = Text.Make(viewState.AddConfigFolderErrorText ?? "", 10, FontWeights.Normal, Theme.Red, margin: new Thickness(0, 6, 0, 0));
        errorText.Visibility = viewState.AddConfigFolderErrorText is null ? Visibility.Collapsed : Visibility.Visible;
        pathField.TextChanged += (_, _) =>
        {
            viewState.TypedPath = pathField.Text;
            viewState.AddConfigFolderErrorText = null;
            errorText.Visibility = Visibility.Collapsed;
            preview.Text = UsageText.LoginFilePreview(pathField.Text, homeFolderPath);
        };
        form.Children.Add(pathField);
        var labelField = TextField(viewState.TypedLabel, "Label (e.g. work)", TypedLabelFieldKey, mono: false);
        labelField.Margin = new Thickness(0, 6, 0, 0);
        labelField.TextChanged += (_, _) => viewState.TypedLabel = labelField.Text;
        form.Children.Add(labelField);
        form.Children.Add(preview);
        form.Children.Add(errorText);

        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 6, 0, 0) };
        actions.Children.Add(Buttons.Labeled(null, "Cancel", theme.TextMuted, theme, () =>
        {
            viewState.IsAdding = false;
            rerender();
        }));
        var addButton = Buttons.Labeled(null, "Add", Theme.Accent, theme, AddTypedConfigFolder);
        addButton.Margin = new Thickness(6, 0, 0, 0);
        actions.Children.Add(addButton);
        form.Children.Add(actions);
        pathField.KeyDown += (_, keyEvent) =>
        {
            if (keyEvent.Key == Key.Enter)
            {
                AddTypedConfigFolder();
            }
        };
        return Cards.Make(form, theme.Row, new Thickness(8), 9);
    }

    private void AddTypedConfigFolder()
    {
        try
        {
            accountStore.AddConfigFolder(viewState.TypedPath, viewState.TypedLabel, System.IO.Directory.Exists);
            viewState.IsAdding = false;
            viewState.AddConfigFolderErrorText = null;
        }
        catch (AddConfigFolderException error)
        {
            viewState.AddConfigFolderErrorText = error.Message;
        }
        rerender();
    }

    private TextBox TextField(string text, string placeholder, string fieldKey, bool mono)
    {
        var field = new TextBox
        {
            Style = (Style)Application.Current.Resources["TrayTextBox"],
            Text = text,
            Tag = placeholder,
            Uid = fieldKey,
            Background = theme.Background,
            Foreground = theme.TextPrimary,
            CaretBrush = theme.TextPrimary,
            BorderBrush = theme.TextMuted,
            SelectionBrush = Theme.Accent,
            FontFamily = mono ? Theme.MonoFont : Theme.TextFont,
        };
        System.Windows.Automation.AutomationProperties.SetName(field, placeholder);
        return field;
    }

    private FrameworkElement NameAndPath(string name, string configFolderPath)
    {
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(Text.Make(name, 12, FontWeights.SemiBold, theme.TextPrimary));
        stack.Children.Add(PathText(configFolderPath, new Thickness(0, 1, 0, 0)));
        return stack;
    }

    private TextBlock PathText(string configFolderPath, Thickness margin)
    {
        var displayPath = ClaudeAccount.DisplayPath(configFolderPath, homeFolderPath);
        var path = Text.Make(displayPath, 10, FontWeights.Normal, theme.TextMuted, margin: margin, mono: true);
        path.ToolTip = configFolderPath;
        return path;
    }

    private FrameworkElement Chip(string text, System.Windows.Media.Brush color)
    {
        var chip = Cards.Make(Text.Make(text, 9, FontWeights.Bold, color), Theme.Tinted(color, 0.18), new Thickness(6, 2, 6, 2), 4);
        chip.HorizontalAlignment = HorizontalAlignment.Right;
        return chip;
    }

    private Button OrderButton(string iconPath, string label, bool isEnabled, Action onClick)
    {
        var button = Buttons.Make(Icons.Make(iconPath, 10, theme.TextMuted), theme.TextMuted, theme.Card, theme.Hairline, onClick, label, new Thickness(3, 1, 3, 1));
        button.IsEnabled = isEnabled;
        return button;
    }
}
