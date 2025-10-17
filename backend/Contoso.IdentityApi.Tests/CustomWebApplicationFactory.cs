using System.IO;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Contoso.IdentityApi.Tests;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Derive backend project directory relative to test assembly base path.
        // baseDir = backend/Contoso.IdentityApi.Tests/bin/Debug/net8.0/
        var baseDir = AppContext.BaseDirectory;
        var backendProjectDir = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "Contoso.IdentityApi"));
        if (!File.Exists(Path.Combine(backendProjectDir, "Contoso.IdentityApi.csproj")))
        {
            // Fallback to current directory if expected layout not found.
            backendProjectDir = Directory.GetCurrentDirectory();
        }
        builder.UseContentRoot(backendProjectDir);
    }
}