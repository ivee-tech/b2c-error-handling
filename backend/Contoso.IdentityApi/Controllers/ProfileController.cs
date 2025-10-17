using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Linq;

namespace Contoso.IdentityApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProfileController : ControllerBase
{
    [HttpGet]
    [Authorize]
    public IActionResult Get()
    {
        var claims = User.Claims.ToDictionary(c => c.Type, c => c.Value);
        var result = new
        {
            message = "Secure profile data",
            sub = claims.GetValueOrDefault("sub"),
            name = claims.GetValueOrDefault("name"),
            oid = claims.GetValueOrDefault("oid"),
            tid = claims.GetValueOrDefault("tid"),
            aud = claims.GetValueOrDefault("aud"),
            allClaims = claims
        };
        return Ok(result);
    }
}
