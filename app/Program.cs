// Program.cs — point d'entrée de l'application MVC et de son endpoint /health.
//
// Câblage de l'application : services, middlewares, routes et métriques.
// Modifier ici pour brancher un nouveau service ou une nouvelle route.
// Il ne contient aucune logique métier, seulement la configuration.
using DemoApp;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();
builder.Services.AddSingleton(sp =>
    AppInfo.FromEnvironment(sp.GetRequiredService<IHostEnvironment>().EnvironmentName));

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
}

app.UseStaticFiles();
app.UseRouting();
app.UseHttpMetrics();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.MapMetrics();

app.MapGet("/health", (AppInfo info) => Results.Json(new
{
    status = "Healthy",
    environment = info.Environment,
    host = info.Host,
    version = info.Version,
    started_at = info.StartedAt,
    utc = DateTimeOffset.UtcNow
}));

app.Run();
