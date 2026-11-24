namespace DemoApp;

/// <summary>Host facts shared by the home page and the /health probe.</summary>
public sealed record AppInfo(
    string Host,
    string Environment,
    string Version,
    string Runtime,
    DateTimeOffset StartedAt)
{
    /// <summary>Time since the container started, in d.hh:mm:ss.</summary>
    public string Uptime => (DateTimeOffset.UtcNow - StartedAt).ToString(@"d\.hh\:mm\:ss");

    public static AppInfo FromEnvironment(string environmentName) => new(
        Host: System.Environment.MachineName,
        Environment: environmentName,
        Version: System.Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
        Runtime: System.Environment.Version.ToString(),
        StartedAt: DateTimeOffset.UtcNow);
}
