using System.Windows.Forms;
using ClaudeUsageTray.Core;
using Microsoft.Win32;

namespace ClaudeUsageTray;

public sealed class TrayIconController : IDisposable
{
    private const string LogoKey = "logo";

    private readonly AccountStore accountStore;
    private readonly UsageService usageService;
    private readonly AppSettings settings;
    private readonly TimeProvider timeProvider;
    private readonly FlyoutWindow flyoutWindow;
    private readonly Dictionary<string, ShownTrayIcon> shownTrayIcons = new(StringComparer.OrdinalIgnoreCase);

    public TrayIconController(AccountStore accountStore, UsageService usageService, AppSettings settings, TimeProvider timeProvider, FlyoutWindow flyoutWindow)
    {
        this.accountStore = accountStore;
        this.usageService = usageService;
        this.settings = settings;
        this.timeProvider = timeProvider;
        this.flyoutWindow = flyoutWindow;

        usageService.UsageChanged += Update;
        accountStore.AccountsChanged += Update;
        settings.SettingsChanged += Update;
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        Update();
    }

    public void Update()
    {
        var entries = TrayIconPlan.Entries(accountStore, usageService, settings.ShowLogo, settings.ShowResetTime, timeProvider);
        var entryKeys = entries.Select(KeyFor).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var staleKey in shownTrayIcons.Keys.Where(key => !entryKeys.Contains(key)).ToList())
        {
            shownTrayIcons[staleKey].Dispose();
            shownTrayIcons.Remove(staleKey);
        }

        var iconSize = SystemInformation.SmallIconSize.Width;
        var isTaskbarLight = TaskbarTheme.IsTaskbarLight();
        foreach (var entry in entries)
        {
            var key = KeyFor(entry);
            var drawing = new TrayIconDrawing(entry is TrayIconEntry.AccountRing ring ? (ring.Remaining, ring.AccountColorHex) : null, iconSize, isTaskbarLight);
            var tooltipText = entry is TrayIconEntry.AccountRing accountRing ? accountRing.TooltipText : "Claude Usage";
            if (!shownTrayIcons.TryGetValue(key, out var shownTrayIcon))
            {
                shownTrayIcon = new ShownTrayIcon(new NotifyIcon());
                var clickedKey = key;
                shownTrayIcon.NotifyIcon.MouseUp += (_, mouseEvent) =>
                {
                    if (mouseEvent.Button is MouseButtons.Left or MouseButtons.Right)
                    {
                        OnTrayIconClicked(clickedKey);
                    }
                };
                shownTrayIcons[key] = shownTrayIcon;
            }
            shownTrayIcon.Show(drawing, tooltipText);
        }
    }

    private void OnTrayIconClicked(string key)
    {
        var clickedAccount = accountStore.ShownAccounts.FirstOrDefault(account => ClaudeAccount.IsSamePath(account.ConfigFolderPath, key));
        var selectedAccount = accountStore.SelectedAccount(settings.SelectedConfigFolderPath);
        var isOtherAccountClicked = clickedAccount is not null
            && accountStore.ShownAccounts.Count > 1
            && !ClaudeAccount.IsSamePath(clickedAccount.ConfigFolderPath, selectedAccount?.ConfigFolderPath ?? "");

        if (!isOtherAccountClicked)
        {
            flyoutWindow.Toggle();
            return;
        }
        settings.SelectedConfigFolderPath = clickedAccount!.ConfigFolderPath;
        if (flyoutWindow.IsOpen)
        {
            flyoutWindow.Activate();
        }
        else
        {
            flyoutWindow.ShowFlyout();
        }
    }

    private static string KeyFor(TrayIconEntry entry) => entry switch
    {
        TrayIconEntry.AccountRing ring => ring.Account.ConfigFolderPath,
        _ => LogoKey,
    };

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs preferenceEvent)
    {
        if (preferenceEvent.Category is UserPreferenceCategory.General or UserPreferenceCategory.Color or UserPreferenceCategory.VisualStyle)
        {
            System.Windows.Application.Current.Dispatcher.BeginInvoke(RedrawAll);
        }
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs displayEvent) =>
        System.Windows.Application.Current.Dispatcher.BeginInvoke(RedrawAll);

    private void RedrawAll()
    {
        foreach (var shownTrayIcon in shownTrayIcons.Values)
        {
            shownTrayIcon.ForgetDrawing();
        }
        Update();
    }

    public void Dispose()
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        foreach (var shownTrayIcon in shownTrayIcons.Values)
        {
            shownTrayIcon.Dispose();
        }
        shownTrayIcons.Clear();
    }

    private sealed record TrayIconDrawing((double? Remaining, string? AccountColorHex)? Ring, int Size, bool IsTaskbarLight);

    private sealed class ShownTrayIcon : IDisposable
    {
        private TrayIconImage? image;
        private TrayIconDrawing? drawnDrawing;

        public ShownTrayIcon(NotifyIcon notifyIcon)
        {
            NotifyIcon = notifyIcon;
        }

        public NotifyIcon NotifyIcon { get; }

        public void ForgetDrawing() => drawnDrawing = null;

        public void Show(TrayIconDrawing drawing, string tooltipText)
        {
            if (drawing != drawnDrawing)
            {
                var newImage = drawing.Ring is { } ring
                    ? TrayIconRenderer.RenderRing(ring.Remaining, ring.AccountColorHex, drawing.Size, drawing.IsTaskbarLight)
                    : TrayIconRenderer.RenderLogo(drawing.Size);
                NotifyIcon.Icon = newImage.Icon;
                image?.Dispose();
                image = newImage;
                drawnDrawing = drawing;
            }
            if (NotifyIcon.Text != tooltipText)
            {
                NotifyIcon.Text = tooltipText;
            }
            NotifyIcon.Visible = true;
        }

        public void Dispose()
        {
            NotifyIcon.Visible = false;
            NotifyIcon.Dispose();
            image?.Dispose();
        }
    }
}
