using Microsoft.AspNetCore.HttpOverrides;
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();
builder.Services.Configure<HostOptions>(o => o.ShutdownTimeout = TimeSpan.FromSeconds(10));

var app = builder.Build();

// Behind Traefik, the client IP and scheme arrive in X-Forwarded-* headers.
var forwarded = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
};
forwarded.KnownNetworks.Clear();
forwarded.KnownProxies.Clear();
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

app.MapGet("/health", (IHostEnvironment env) => Results.Json(new
{
    status = "Healthy",
    environment = env.EnvironmentName,
    host = Environment.MachineName,
    version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
    utc = DateTimeOffset.UtcNow
}));

app.Run();
