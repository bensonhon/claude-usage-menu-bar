using System.Diagnostics;
using System.Net.Http;
using System.Windows;
using System.Windows.Threading;
using ClaudeUsageTray.Core;
using Microsoft.Win32;

namespace ClaudeUsageTray;

public partial class App : Application
{
    private const string AppFolderName = "ClaudeUsageTray";
    public const string ProcessName = "ClaudeUsageTray";

    private TrayIconController? trayIconController;
    private DispatcherTimer? refreshTimer;

    protected override void OnStartup(StartupEventArgs startupEvent)
    {
        base.OnStartup(startupEvent);
        DispatcherUnhandledException += OnDispatcherUnhandledException;
        TerminateOtherInstances();
        StartAtSignIn.Register();

        var homeFolderPath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appDataFolderPath = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppFolderName);
        var timeProvider = TimeProvider.System;

        var accountStore = new AccountStore(System.IO.Path.Combine(appDataFolderPath, "accounts.json"), homeFolderPath);
        var settings = new AppSettings(System.IO.Path.Combine(appDataFolderPath, "settings.json"));
        var usageService = new UsageService(accountStore, new UsageApiClient(new HttpClient()), timeProvider, homeFolderPath);
        usageService.ShownAccountsRefreshStarted += ReportFailure;
        var flyoutWindow = new FlyoutWindow(accountStore, usageService, settings, timeProvider, homeFolderPath, Quit, ReportFailure);
        trayIconController = new TrayIconController(accountStore, usageService, settings, timeProvider, flyoutWindow);

        refreshTimer = new DispatcherTimer();
        refreshTimer.Tick += async (_, _) =>
        {
            refreshTimer.Stop();
            await usageService.RefreshAsync();
            refreshTimer.Interval = usageService.NextRefreshInterval;
            refreshTimer.Start();
        };
        refreshTimer.Interval = TimeSpan.Zero;
        refreshTimer.Start();
    }

    public static void ReportFailure(Task backgroundTask)
    {
        backgroundTask.ContinueWith(
            failedTask => Current.Dispatcher.BeginInvoke(() => System.Runtime.ExceptionServices.ExceptionDispatchInfo.Throw(failedTask.Exception!.InnerException!)),
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted,
            TaskScheduler.Default);
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs unhandledEvent)
    {
        trayIconController?.Dispose();
        MessageBox.Show($"Claude Usage stopped because of an unexpected error:\n\n{unhandledEvent.Exception}", "Claude Usage", MessageBoxButton.OK, MessageBoxImage.Error);
    }

    private void Quit()
    {
        refreshTimer?.Stop();
        trayIconController?.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs exitEvent)
    {
        trayIconController?.Dispose();
        base.OnExit(exitEvent);
    }

    private static void TerminateOtherInstances()
    {
        using var currentProcess = Process.GetCurrentProcess();
        foreach (var otherProcess in Process.GetProcessesByName(ProcessName))
        {
            using (otherProcess)
            {
                if (otherProcess.Id == currentProcess.Id)
                {
                    continue;
                }
                try
                {
                    otherProcess.Kill();
                    otherProcess.WaitForExit(TimeSpan.FromSeconds(2));
                }
                catch (InvalidOperationException)
                {
                }
            }
        }
    }
}

public static class StartAtSignIn
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "ClaudeUsageTray";

    public static void Register()
    {
        if (Environment.ProcessPath is not { } executablePath)
        {
            return;
        }
        using var runKey = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        var command = $"\"{executablePath}\"";
        if (runKey.GetValue(RunValueName) as string != command)
        {
            runKey.SetValue(RunValueName, command);
        }
    }
}
