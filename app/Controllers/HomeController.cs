// HomeController.cs — sert la page d'accueil et la page d'erreur.
//
// Prépare les données de vue : adresse du client et en-tête X-Forwarded-For.
// Modifier ici pour changer ce que les vues reçoivent, pas leur rendu.
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
