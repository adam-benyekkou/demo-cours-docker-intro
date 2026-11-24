using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace DemoApp.Controllers;

public class HomeController(AppInfo info) : Controller
{
    public IActionResult Index()
    {
        ViewData["ClientAddress"] = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        ViewData["ForwardedFor"] = Request.Headers["X-Forwarded-For"].ToString();
        return View(info);
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        ViewData["RequestId"] = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        return View();
    }
}
