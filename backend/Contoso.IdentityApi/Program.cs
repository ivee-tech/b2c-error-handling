using Microsoft.AspNetCore.Authentication.JwtBearer;
using Contoso.IdentityApi.Services;
using System.Security.Cryptography.X509Certificates;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using System.Diagnostics;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// Bind config
var b2c = builder.Configuration.GetSection("AzureAdB2C");
var instance = b2c["Instance"]?.TrimEnd('/') ?? "https://yourtenant.b2clogin.com";
var domain = b2c["Domain"] ?? "yourtenant.onmicrosoft.com";
var policy = b2c["SignUpSignInPolicyId"] ?? "B2C_1A_SignUpSignIn";
var audience = b2c["Audience"] ?? b2c["ClientId"] ?? "https://yourtenant.onmicrosoft.com/api";
var issuer = $"{instance}/{domain}/{policy}/v2.0/"; // trailing slash required

builder.Services.AddCors(o => o.AddPolicy("Frontend", p =>
    p.WithOrigins("http://localhost:4200")
     .AllowAnyHeader()
     .AllowAnyMethod()
));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = issuer;
        options.Audience = audience; // Primary audience
        // Accept both the configured Audience and (optionally) the raw client ID for resiliency
        var clientId = b2c["ClientId"];        
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidIssuer = issuer,
            ValidateIssuer = true,
            NameClaimType = "name",
            ValidAudiences = new[] { audience, clientId }.Where(a => !string.IsNullOrWhiteSpace(a))
        };
        options.Events = new JwtBearerEvents
        {
            OnAuthenticationFailed = ctx =>
            {
                ctx.Response.Headers["X-Auth-Failure"] = ctx.Exception.GetType().Name;
                return Task.CompletedTask;
            },
            OnChallenge = ctx =>
            {
                if (!string.IsNullOrEmpty(ctx.ErrorDescription))
                {
                    ctx.Response.Headers["X-Auth-Challenge"] = ctx.ErrorDescription;
                }
                return Task.CompletedTask;
            },
            OnTokenValidated = ctx =>
            {
                // Expose selected debug headers (remove in production)
                var upn = ctx.Principal?.FindFirst("emails")?.Value ?? ctx.Principal?.Identity?.Name ?? "(no-name)";
                ctx.Response.Headers["X-Auth-User"] = upn;
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();
// Register JSON user directory (Data/users.json)
builder.Services.AddSingleton<IUserDirectory>(sp =>
    new JsonUserDirectory(Path.Combine(builder.Environment.ContentRootPath, "Data", "users.json")));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Contoso Identity API", Version = "v1" });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Enter 'Bearer {token}'"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            }, new string[] { }
        }
    });
});

var app = builder.Build();

app.UseCors("Frontend");
app.UseSwagger();
app.UseSwaggerUI();

app.UseAuthentication();
app.UseAuthorization();

// Optional client certificate validation for REST IDM endpoint if enabled in config
var restAuthSection = app.Configuration.GetSection("RestApiAuth");
bool requireClientCert = restAuthSection.GetValue<bool>("RequireClientCertificate");
var allowedThumbprints = restAuthSection.GetSection("AllowedThumbprints").Get<string[]>() ?? Array.Empty<string>();

if (requireClientCert && allowedThumbprints.Length > 0)
{
    app.Use(async (ctx, next) =>
    {
        if (ctx.Request.Path.Equals("/users/validate", StringComparison.OrdinalIgnoreCase))
        {
            var cert = await ctx.Connection.GetClientCertificateAsync();
            if (cert == null || !allowedThumbprints.Contains(cert.Thumbprint?.ToUpperInvariant()))
            {
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await ctx.Response.WriteAsJsonAsync(new
                {
                    userExists = false,
                    userId = (string?)null,
                    userMessage = "Unauthorized REST call",
                    errorCode = "idm.auth.failed",
                    journeyHasError = true
                });
                return;
            }
        }
        await next();
    });
}

// Optional Basic auth enforcement for local development (used when policy profile is set to Basic)
var basicSection = app.Configuration.GetSection("RestApiBasicAuth");
if (basicSection.GetValue<bool>("Enabled"))
{
    var basicUser = basicSection.GetValue<string>("Username") ?? string.Empty;
    var basicPass = basicSection.GetValue<string>("Password") ?? string.Empty;
    var expected = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{basicUser}:{basicPass}"));
    app.Use(async (ctx, next) =>
    {
        if (ctx.Request.Path.StartsWithSegments("/users", StringComparison.OrdinalIgnoreCase))
        {
            if (!ctx.Request.Headers.TryGetValue("Authorization", out var auth) || !auth.ToString().StartsWith("Basic "))
            {
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                ctx.Response.Headers["WWW-Authenticate"] = "Basic realm=Users";
                await ctx.Response.WriteAsJsonAsync(new { error = "basic.auth.missing" });
                return;
            }
            var provided = auth.ToString().Substring("Basic ".Length).Trim();
            // Simple constant-time-ish comparison
            try
            {
                var providedBytes = Convert.FromBase64String(provided);
                var expectedBytes = Convert.FromBase64String(expected);
                if (providedBytes.Length != expectedBytes.Length)
                {
                    ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    ctx.Response.Headers["WWW-Authenticate"] = "Basic realm=Users";
                    await ctx.Response.WriteAsJsonAsync(new { error = "basic.auth.invalid" });
                    return;
                }
                // Constant time comparison
                if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(providedBytes, expectedBytes))
                {
                    ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    ctx.Response.Headers["WWW-Authenticate"] = "Basic realm=Users";
                    await ctx.Response.WriteAsJsonAsync(new { error = "basic.auth.invalid" });
                    return;
                }
            }
            catch
            {
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                ctx.Response.Headers["WWW-Authenticate"] = "Basic realm=Users";
                await ctx.Response.WriteAsJsonAsync(new { error = "basic.auth.invalid" });
                return;
            }
            // Auth success: continue to next middleware/controller
        }
        await next();
    });
}

app.MapGet("/api/health", () => Results.Json(new { status = "ok", policy }))
    .AllowAnonymous();

app.MapControllers();

// Token debug endpoint: returns all claims (for troubleshooting only; remove in production)
app.MapGet("/api/debug/token", (ClaimsPrincipal user) =>
{
    if (user?.Identity == null || !user.Identity.IsAuthenticated)
    {
        return Results.Unauthorized();
    }
    var claims = user.Claims.Select(c => new { c.Type, c.Value });
    return Results.Json(claims);
}).RequireAuthorization();

app.Run();

/// <summary>
/// Dummy Program partial class exposed for integration testing via WebApplicationFactory.
/// </summary>
public partial class Program { }
