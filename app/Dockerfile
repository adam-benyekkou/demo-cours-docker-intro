# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY DemoApp.csproj ./
RUN dotnet restore DemoApp.csproj

COPY . ./
RUN dotnet publish DemoApp.csproj -c Release -o /out --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /out ./

# The aspnet image already defines APP_UID=1654, the non-root user "app",
# ASPNETCORE_HTTP_PORTS=8080 and DOTNET_RUNNING_IN_CONTAINER=true.
USER $APP_UID
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080"]

ENTRYPOINT ["dotnet", "DemoApp.dll"]
