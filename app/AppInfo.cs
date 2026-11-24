// AppInfo.cs — décrit les faits d'hôte exposés à la page d'accueil et à /health.
//
// Enregistré en singleton par Program.cs et rempli une fois au démarrage.
// Les valeurs viennent de l'environnement du conteneur, pas d'un appel réseau.
namespace DemoApp;

/// <summary>Faits d'hôte partagés par la page d'accueil et la sonde /health.</summary>
public sealed record AppInfo(
    string Host,
    string Environment,
    string Version,
    string Runtime,
    DateTimeOffset StartedAt)
{
    /// <summary>Temps écoulé depuis le démarrage du conteneur, au format d.hh:mm:ss.</summary>
    public string Uptime => (DateTimeOffset.UtcNow - StartedAt).ToString(@"d\.hh\:mm\:ss");

    public static AppInfo FromEnvironment(string environmentName) => new(
        Host: System.Environment.MachineName,
        Environment: environmentName,
        Version: System.Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
        Runtime: System.Environment.Version.ToString(),
        StartedAt: DateTimeOffset.UtcNow);
}
