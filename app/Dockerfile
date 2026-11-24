# syntax=docker/dockerfile:1

# Dockerfile — construit l'image de l'application en deux étapes.
#
# Étape build : SDK .NET 10 et publication Release. Étape final : image aspnet.
# Modifier ici pour changer la version de .NET ou la commande de démarrage.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY DemoApp.csproj ./
RUN dotnet restore DemoApp.csproj

COPY . ./
RUN dotnet publish DemoApp.csproj -c Release -o /out --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

COPY --from=build /out ./

# L'image aspnet définit déjà APP_UID=1654, ASPNETCORE_HTTP_PORTS=8080
# et DOTNET_RUNNING_IN_CONTAINER=true.
USER $APP_UID
EXPOSE 8080

ENTRYPOINT ["dotnet", "DemoApp.dll"]
