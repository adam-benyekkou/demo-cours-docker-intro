using System.Net;
using DemoApp;
using Microsoft.AspNetCore.HttpOverrides;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();
builder.Services.Configure<HostOptions>(o => o.ShutdownTimeout = TimeSpan.FromSeconds(10));
builder.Services.AddSingleton(sp =>
    AppInfo.FromEnvironment(sp.GetRequiredService<IHostEnvironment>().EnvironmentName));

var app = builder.Build();

// Behind Traefik, the client IP and scheme arrive in X-Forwarded-* headers.
// Only the compose edge network may set them: the subnet is pinned in
// stack/docker-compose.yml next to providers.docker.network in traefik.yml, so
// a neighbour container on another network cannot spoof a client IP.
var forwarded = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
    ForwardLimit = 1
};
forwarded.KnownIPNetworks.Add(new System.Net.IPNetwork(IPAddress.Parse("10.89.0.0"), 24));
app.UseForwardedHeaders(forwarded);

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
