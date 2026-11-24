using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace DemoApp.Controllers;

public class HomeController : Controller
{
    private static readonly DateTimeOffset StartedAt = DateTimeOffset.UtcNow;

    public IActionResult Index()
    {
        ViewData["Host"] = Environment.MachineName;
        ViewData["Environment"] = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
        ViewData["Version"] = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev";
        ViewData["Runtime"] = Environment.Version.ToString();
        ViewData["StartedAt"] = StartedAt.ToString("u");
        ViewData["Uptime"] = (DateTimeOffset.UtcNow - StartedAt).ToString(@"d\.hh\:mm\:ss");
        ViewData["Requests"] = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        ViewData["ForwardedFor"] = Request.Headers["X-Forwarded-For"].ToString();
        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        ViewData["RequestId"] = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        return View();
    }
}
