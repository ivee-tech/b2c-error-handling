using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Contoso.IdentityApi.Services;

namespace Contoso.IdentityApi.Controllers;

/// <summary>
/// Implements the REST endpoint expected by the B2C technical profile <c>REST-IDM-UserValidation</c>.
/// Input (claims in body): <c>{ "email": "user@example.com", "correlationId": "{guid}" }</c>
/// Output (claims): <c>userExists</c>, <c>userId</c>, <c>userMessage</c>, <c>errorCode</c>, <c>journeyHasError</c>.
/// Backed by a JSON file user directory for demo purposes (see <c>Data/users.json</c>).
/// </summary>
[ApiController]
[AllowAnonymous] // Called by Azure AD B2C, must allow anonymous
[Route("users")] // Matches ServiceUrl path segment (/users/validate)
public class UserValidationController : ControllerBase
{
    /// <summary>Request payload received from Azure AD B2C REST call.</summary>
    /// <param name="Email">User email address.</param>
    /// <param name="CorrelationId">Correlation identifier generated earlier in the journey.</param>
    public record UserValidationRequest(string? Email, string? CorrelationId);
    /// <summary>Simulation request for demonstrating REST error handling scenarios.</summary>
    /// <param name="Scenario">Supports: <c>throttle</c>, <c>generic</c>, <c>success</c>.</param>
    /// <param name="CorrelationId">Correlation id to echo.</param>
    public record ErrorSimulationRequest(string? Scenario, string? CorrelationId);
    private readonly IUserDirectory _directory;
    private readonly IConfiguration _config;

    /// <summary>Creates the controller with a user directory dependency.</summary>
    public UserValidationController(IUserDirectory directory, IConfiguration config)
    {
        _directory = directory;
        _config = config;
    }

    /// <summary>
    /// Validates whether a user already exists and returns structured claims for the custom policy.
    /// Always returns HTTP 200 with a payload indicating success or a journey-level error (journeyHasError).
    /// </summary>
    /// <param name="request">Incoming request containing email and correlationId.</param>
    /// <returns>Structured JSON matching expected output claim names for the technical profile.</returns>
    [HttpPost("validate")] // POST /users/validate
    public async Task<IActionResult> ValidateUser([FromBody] UserValidationRequest request)
    {
        if (request is null)
        {
            // Return a non-2xx with B2C error contract so validation TP halts and shows inline message
            return BadRequest(new
            {
                version = "1.0.0",
                status = 400,
                code = "idm.request.null",
                userMessage = "Invalid request payload.",
                message = "Invalid request payload.",
            });
        }
        if (string.IsNullOrWhiteSpace(request.Email))
        {
            return BadRequest(new
            {
                version = "1.0.0",
                status = 400,
                code = "idm.email.required",
                userMessage = "Email is required.",
                message = "Email is required.",
            });
        }

        // Simulated latency (optional) before any directory lookups to emulate upstream dependency delay.
        // Configuration keys:
        //   UserValidation:SimulatedLatencyMaxMs  (max random delay; if <= 0, disabled)  [default 0]
        //   UserValidation:TimeoutThresholdMs     (threshold after which we return 408)  [default 10000]
        // Behavior:
        //   A random delay D in [0, SimulatedLatencyMaxMs] is awaited. If D > TimeoutThresholdMs we short-circuit
        //   with a 408 response and do NOT query the directory. This lets environments simulate sporadic timeouts
        //   without adding flaky latency to test runs (tests disable via SimulatedLatencyMaxMs = 0).
        var maxLatencyMs = _config.GetValue<int?>("UserValidation:SimulatedLatencyMaxMs") ?? 0;
        var timeoutThresholdMs = _config.GetValue<int?>("UserValidation:TimeoutThresholdMs") ?? 10000;
        if (maxLatencyMs > 0)
        {
            var delay = Random.Shared.Next(0, maxLatencyMs + 1);
            if (delay > 0)
            {
                await Task.Delay(delay);
            }
            if (delay > timeoutThresholdMs)
            {
                return StatusCode(StatusCodes.Status408RequestTimeout, new
                {
                    version = "1.0.0",
                    status = 408,
                    code = "idm.timeout",
                    userMessage = "The request timed out. Please retry.",
                    message = "The request timed out.",
                });
            }
        }

        var email = request.Email.Trim();
        var user = await _directory.FindByEmailAsync(email);
        if (user is null)
        {
            // Return 404 to drive global error page (RaiseErrorResponseCodes will include 404) rather than inline form error.
            return NotFound(new
            {
                version = "1.0.0",
                status = 404,
                code = "idm.user.notFound",
                userMessage = "We can't find that account.",
                message = "We can't find that account.",
            });
        }
        if (user.Blocked)
        {
            // Blocked users surface a 409 so B2C stops at REST validation and shows the friendly message
            return StatusCode(StatusCodes.Status409Conflict, new
            {
                version = "1.0.0",
                status = 409,
                code = "idm.user.blocked",
                userMessage = "The specified account is blocked.",
                message = "The specified account is blocked.",
            });
        }
        return Ok(new
        {
            userExists = true,
            userId = user.UserId,
            userMessage = (string?)null,
            errorCode = (string?)null,
            journeyHasError = false
        });
    }

    private static object Error(string code, string message, bool journeyHasError) => new
    {
        userExists = false,
        userId = (string?)null,
        userMessage = message,
        errorCode = code,
        journeyHasError,
        // retryAfter only present in some error shapes; omitted when null
        retryAfter = (int?)null
    };

    /// <summary>
    /// Simulates various REST error responses to demonstrate how Azure AD B2C surfaces structured errors
    /// and drives the custom error page (via claims like journeyErrorMessage, journeyErrorCode, journeyRetryAfter).
    /// This endpoint intentionally always returns HTTP 200 with a payload describing success or error, matching
    /// the pattern recommended for REST technical profiles (transport-level success, journey-level error encoded in claims).
    /// </summary>
    /// <param name="request">Simulation request indicating scenario.</param>
    /// <returns>JSON payload with the same contract as /users/validate plus optional <c>retryAfter</c>.</returns>
    [HttpPost("simulate-error")] // POST /users/simulate-error
    public IActionResult SimulateError([FromBody] ErrorSimulationRequest? request)
    {
        var scenario = request?.Scenario?.Trim().ToLowerInvariant();
        return scenario switch
        {
            "throttle" => Ok(new
            {
                userExists = false,
                userId = (string?)null,
                userMessage = "Too many attempts. Please retry later.",
                errorCode = "idm.throttle",
                journeyHasError = true,
                retryAfter = 15
            }),
            "generic" or null => Ok(new
            {
                userExists = false,
                userId = (string?)null,
                userMessage = "A generic simulated error occurred.",
                errorCode = "idm.generic",
                journeyHasError = true,
                retryAfter = (int?)null
            }),
            "success" or "ok" => Ok(new
            {
                userExists = false,
                userId = (string?)null,
                userMessage = (string?)null,
                errorCode = (string?)null,
                journeyHasError = false,
                retryAfter = (int?)null
            }),
            _ => Ok(new
            {
                userExists = false,
                userId = (string?)null,
                userMessage = "Unknown scenario. Use one of: throttle, generic, success.",
                errorCode = "idm.sim.invalidScenario",
                journeyHasError = true,
                retryAfter = (int?)null
            })
        };
    }
}
