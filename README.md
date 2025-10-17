# Contoso Transit Identity Demo (Angular 20 + Azure AD B2C + .NET 8 API)

This sample provides a minimal Single Page Application (Angular 20, standalone component) and a backend **.NET 8 Web API** protected by Azure AD B2C using a **custom policy** whose PolicyId is now `B2C_1A_SignUpSignIn` (renamed from the earlier `B2C_1_susi` to avoid colliding with an existing built‑in user flow of the same name). The underlying custom policy files live in `policies/` and introduce REST API orchestration, error handling and localization.

> NOTE: This is a lightweight hand-written scaffold (not full Angular CLI output) to keep the repository concise. You can migrate it into a standard Angular CLI workspace later if needed.

## 1. Prerequisites
- Node.js 18+ (for frontend tooling)
- .NET 8 SDK
- Azure AD B2C tenant
- Two App Registrations in B2C:
  1. SPA (Public client)
  2. API (Protected resource)

## 2. Azure AD B2C Setup
### 2.1 Quick Terminology
| Term | Meaning |
|------|---------|
| Application (client) ID | GUID identifying an app registration |
| Application ID URI | Logical resource identifier used as token audience (e.g. `https://tenant.onmicrosoft.com/api`) |
| Scope | Permission segment appended to Application ID URI (e.g. `/user.read`) |

### 2.2 API App Registration (Protected Resource)
1. Azure AD B2C tenant → App registrations → New registration → Name: `contoso-transit-api`.
2. Leave redirect URI empty (not needed for APIs).
3. After creation → Expose an API → Set Application ID URI (choose one style, be consistent):
  - Recommended domain style: `https://<tenant>.onmicrosoft.com/<API_CLIENT_ID>`
  - OR GUID style: `api://<API_CLIENT_ID>`
4. Add a scope:
  - Name: `user.read`
  - Admin consent display name: `Read user profile`
  - Description: `Allows reading the signed-in user's profile.`
  - State: Enabled
5. (Optional) Add additional scopes or app roles later.

### 2.3 SPA App Registration (Public Client)
1. New registration → Name: `contoso-transit-spa`.
2. Platform: Single-page application → Redirect URI: `http://localhost:4200`.
3. Enable Access tokens & ID tokens (implicit + auth code flow support for SPA via PKCE).
4. API permissions → Add a permission → My APIs → pick `contoso-transit-api` → select `user.read` → Add.
5. Grant admin consent (avoids user consent prompts in many B2C scenarios).

### 2.4 Custom Policy Deployment (replaces built‑in user flow)
The active policy set now lives under `policies/LocalAccounts/` (the previous versioned samples in `policies/NA/` are retained only for comparison). The SignUpSignIn policy XML uses PolicyId `B2C_1A_SignUpSignIn`. If you previously configured apps against a built‑in user flow `B2C_1_susi`, update their authority URLs to reference this custom policy id.

1. In the Azure Portal open your B2C tenant.
2. Create (or verify) the two required application registrations for custom policies (if they do not already exist):
  - `IdentityExperienceFramework` (web, reply URL: `https://jwt.ms`, allow public client = No)
  - `ProxyIdentityExperienceFramework` (native/public client, redirect URI: `myapp://auth` or `https://jwt.ms`)
  - Grant the `IdentityExperienceFramework` application delegated permissions to `ProxyIdentityExperienceFramework` (API permissions → Add → APIs my organization uses).
   
#### 2.4.1 Detailed steps for Proxy & permission exposure
These two special apps let Azure AD B2C run your custom policy orchestration (IEF = server side; Proxy = acts as the public/native client brokering tokens). The most common confusion is exposing an API on the Proxy app so the IEF app can request its delegated permission.

1. Register `IdentityExperienceFramework` (IEF)
  - Azure AD B2C Portal → App registrations → New registration.
  - Name: `IdentityExperienceFramework`.
  - Supported account types: Accounts in this organizational directory only.
  - Redirect URI (web): `https://jwt.ms` (temporary; any HTTPS you control would work, jwt.ms is convenient for token inspection).
  - Leave SPA / mobile unchecked here.
  - After creation: Authentication blade → ensure "Allow public client flows" is Disabled.
  - No need to expose an API for this app.
2. Register `ProxyIdentityExperienceFramework` (Proxy IEF)
  - New registration.
  - Name: `ProxyIdentityExperienceFramework`.
  - Supported account types: Accounts in this directory only.
  - Redirect URI: (Public client / mobile & desktop) add `myapp://auth` (placeholder) AND optionally add `https://jwt.ms` for convenience.
  - After creation: Authentication blade → ensure "Allow public client flows" is Enabled (since it's a public/native client).
3. Expose the Proxy API (critical step)
  - Open the `ProxyIdentityExperienceFramework` app → Expose an API.
  - Click "Set" for Application ID URI if not already set; use the default suggested value (e.g. `api://<proxy-client-id>`). You may also choose domain style: `https://<tenant>.onmicrosoft.com/proxyidentityexperienceframework`, either works—just be consistent.
  - Under Scopes defined by this API → Add a scope:
    - Scope name: `user_impersonation` (conventionally used; name is arbitrary but must match what you later select).
    - Admin consent display name: `Access ProxyIdentityExperienceFramework`.
    - Admin consent description: `Allows the IdentityExperienceFramework app to call the proxy to execute custom policies.`
    - State: Enabled → Add scope.
4. (Optional) Pre-authorize IEF for the Proxy scope
  - The Azure AD B2C portal UI periodically changes. Some tenants show an "Authorized client applications" section under Expose an API; others do not.
  - If you DO see it: Add a client application → paste the `IdentityExperienceFramework` app (client) ID → tick `user_impersonation` → Add.
  - If you DO NOT see that section: Pre-authorization is optional. You can rely solely on admin consent in the next step. If you still want to pre-authorize, open the `ProxyIdentityExperienceFramework` app → Manifest, and add the IEF app client ID to the `knownClientApplications` array, e.g.:
    ```json
    "knownClientApplications": [
      "<IDENTITY_EXPERIENCE_FRAMEWORK_CLIENT_ID>"
    ]
    ```
    Save the manifest. (If the property already exists, append the ID instead of replacing existing entries.)
5. Grant delegated permission in IEF app
  - Open the `IdentityExperienceFramework` app → API permissions → Add a permission → My APIs → select `ProxyIdentityExperienceFramework` → check the `user_impersonation` scope → Add permissions.
  - Click "Grant admin consent" for the tenant to avoid runtime consent prompts.
6. Verify
  - In `IdentityExperienceFramework` → API permissions you should now see `ProxyIdentityExperienceFramework` / `user_impersonation` with a green granted check.
  - In `ProxyIdentityExperienceFramework` → Expose an API you should see the scope and the IEF app listed under Authorized client applications.

Common pitfalls:
* Forgetting to create the scope on the Proxy app (results in "The provided application '<guid>' is not configured to allow the '.../user_impersonation' scope").
* Not granting admin consent (interactive consent prompts appear during policy execution, sometimes leading to cryptic errors).
* Mis-typing the Application ID URI; if you change it later, re-run admin consent.
* Mixing up client IDs in policy XML (if your policy XML includes references—this simplified sample omits those explicit IDs, but full starter packs usually require you to replace placeholders). 

You typically do NOT need to add any of these scope strings into your SPA or API configuration; they are strictly for the internal custom policy execution pipeline.
3. Enable Custom Policy feature (Identity Experience Framework blade) if not already visible.
4. Upload the policies in this exact order (use the Upload button each time):
  1. `TrustFrameworkBase.xml`
  2. `TrustFrameworkLocalization.xml`
  3. `TrustFrameworkExtensions.xml`
  4. `SignUpOrSignin.xml` (PolicyId `B2C_1A_signup_signin` inside – RP referencing journey `SignUpOrSignIn`)
  5. (Optional) `ProfileEdit.xml`
  6. (Optional) `PasswordReset.xml`
5. After upload of the first four, run the sign-up/sign-in policy (Run now) to sanity check – a sign‑up form should appear.
6. Any future changes: update locally, then re‑upload just the changed file(s). Base rarely changes; most edits land in `TrustFrameworkExtensions.xml`.

Key customizations in the LocalAccounts policies:
* Added REST technical profile `REST-UserValidation` executed during sign‑up before directory write (validates existence / blocked state via `/users/validate`).
* (Legacy plan items like CRM contact creation & error simulation are not wired into the LocalAccounts journey – see `docs/b2c-custom-policy-plan.md` for future integration notes.)
* Structured error codes mapped in `TrustFrameworkLocalization.xml` (`idm.user.blocked`, `idm.throttle`, etc.).
* Custom error page override (`api.error`) pointing to placeholder URL – update before production.
* Localization file supplies user‑friendly error and field text.

### 2.5 Environment Variable Mapping
| Location | Value |
|----------|-------|
| `backend/appsettings.json:AzureAdB2C:Audience` | The Application ID URI you set (e.g. `https://<tenant>.onmicrosoft.com/api`) |
| `backend/appsettings.json:AzureAdB2C:ClientId` | API app registration Client ID |
| `frontend environment.b2c.clientId` | SPA app registration Client ID |
| `frontend environment.b2c.apiScopes` | Full scope string (e.g. `https://<tenant>.onmicrosoft.com/api/user.read`) |

### 2.6 Token Debugging
Swagger UI now includes a Bearer auth scheme. Acquire a token in the SPA (F12 → Application/Local Storage or network), then:
1. Open `/swagger`.
2. Click Authorize → enter: `Bearer <access_token>`.
3. Try `GET /api/debug/token` to view claim set.

## 3. Configure Environment
Update `backend/appsettings.json` (values already committed in this sample):
```
"AzureAdB2C": {
  "Instance": "https://zipzappmetadatadev.b2clogin.com",
  "Domain": "zipzappmetadatadev.onmicrosoft.com",
  "TenantId": "zipzappmetadatadev.onmicrosoft.com",
  "ClientId": "f6bbbb2d-02dd-4ca4-83bd-bf0709107617",               // API application (protected resource) client ID
  "SignUpSignInPolicyId": "B2C_1A_SignUpSignIn",                       // Custom policy Id (renamed to avoid built-in flow collision)
  "Audience": "https://zipzappmetadatadev.onmicrosoft.com/contoso-transit-api" // Application ID URI of API
}
```
Update `frontend/src/environments/environment.ts` (values already present):
```
tenant: 'zipzappmetadatadev.onmicrosoft.com'
clientId: 'd35ebbe9-3406-4c0b-bad1-8d92c47341b1'              // SPA app registration client ID
signInSignUpPolicy: 'B2C_1A_SignUpSignIn'
apiScopes: ['https://zipzappmetadatadev.onmicrosoft.com/contoso-transit-api/user.read']
authorityDomain: 'zipzappmetadatadev.b2clogin.com'
```
If you fork this repository, consider moving these identifiers to environment‑specific configuration or secrets management (never store certificates or secrets directly in source).

## 4. Install Dependencies
```
cd frontend
npm install
cd ../backend
dotnet restore
```

## 5. Run
In two terminals:
```
cd backend
dotnet run

cd frontend
npm start
```
Visit http://localhost:4200 and sign in.

## 6. How Auth Works
- MSAL Angular acquires tokens from authority: `https://<tenant>.b2clogin.com/<tenant>.onmicrosoft.com/B2C_1A_SignUpSignIn`.
- Interceptor attaches access token to calls matching `environment.api.baseUrl`.
- .NET API validates token via `Microsoft.AspNetCore.Authentication.JwtBearer` against the B2C policy authority.
- Audience & issuer enforced; on success returns filtered claims via `/api/profile`.

## 7. Extending
| Goal | Change |
|------|--------|
| Add another policy (e.g. password reset) | Add a new route initiating `loginRedirect` with different authority. |
| Acquire token for downstream API | Use `acquireTokenSilent` with additional scopes. |
| Add refresh semantics | MSAL handles per token expiry; intercept 401 to force silent/interactive reauth. |
| Add reactive auth state | Use `MsalBroadcastService` to subscribe to in-progress and handle events |
| Switch fully to standalone bootstrap | Replace `AppModule` with `bootstrapApplication(AppComponent)` |
| Add ESLint | `ng add @angular-eslint/schematics` |

## 8. Security Notes
- Do NOT trust client claims; always validate on backend.
- Restrict CORS origins in production.
- Consider caching JWKS keys beyond built-in caching if high volume.
- Log correlation IDs from B2C (add to accepted claims list if included).

## 9. Production Hardening Checklist
- HTTPS and reverse proxy (e.g. Azure Front Door / App Gateway)
- App Insights telemetry (frontend + backend)
- Retry & circuit breaker for downstream APIs
- Centralized error handling middleware
- Configuration via environment / Azure App Config

## 10. Mapping to Policy Plan
| Plan Section | Implementation Hook |
|--------------|--------------------|
| Error Handling Strategy | Interceptor + backend middleware (extend). |
| Correlation ID Propagation | Add custom claim / header when available. |
| Secure Profile Endpoint | `/api/profile` protected route. |
| Observability | Add ASP.NET logging + integrate App Insights SDK later. |

---
Generated scaffold – customize as needed.

## 11. Azure AD B2C Registration (Checklist Recap)
1. API App: `contoso-transit-api` → Expose an API → Application ID URI = `https://zipzappmetadatadev.onmicrosoft.com/contoso-transit-api` → scope `user.read`.
2. SPA App: `contoso-transit-spa` → SPA redirect `http://localhost:4200` → add delegated permission `user.read` → grant admin consent.
3. Custom Policies: Upload base, extensions, localization, sign-up-sign-in (PolicyId `B2C_1A_SignUpSignIn`).
4. Backend: `Audience` matches Application ID URI; `SignUpSignInPolicyId` = `B2C_1A_SignUpSignIn`.
5. Frontend: `apiScopes` contains full scope string ending in `/user.read`.
6. Test flow: Sign up → CRM & IDM orchestration executes → token issued → call `/api/profile`.

## 12. Operational Tips
| Scenario | Action |
|----------|--------|
| Update REST endpoint URL | Edit `REST-UserValidation` in `TrustFrameworkExtensions.xml` and re-upload that file only. |
| Add new output claim to token | Add claim to base schema (if new), then include in `RelyingParty` OutputClaims of `SignUpOrSignin.xml`; re-upload RP file. |
| Localize additional strings | Extend `TrustFrameworkLocalization.xml` with new `LocalizedString` entries. |
| Troubleshoot token issues | Use https://jwt.ms and check `aud`, `iss`, and presence of custom claims. |
| Capture runtime errors | Ensure backend logs correlation ID; optionally add App Insights REST logger technical profile. |
| Integrate CRM contact creation | Add new REST technical profile + orchestration step (before AAD write) in `TrustFrameworkExtensions.xml`; re-upload that file and test. |
| Point validation to local API | Change `ServiceUrl` in `REST-UserValidation` to your local URL (e.g. `https://localhost:5001/users/validate`). |

### 12.1 REST-IDM-UserValidation Local Contract
The controller `UserValidationController` implements a demo endpoint consumed by the custom policy REST call.

POST `/users/validate`
Request body example:
```json
{
  "email": "alice.legacy@example.com",
  "correlationId": "3f6d9a28-1b63-4f13-9ed0-0f6e9acd1111"
}
```
Successful (existing user) response:
```json
{
  "userExists": true,
  "userId": "idm-a1b2c3d4e5",
  "userMessage": null,
  "errorCode": null,
  "journeyHasError": false
}
```
New user (not found) response:
```json
{
  "userExists": false,
  "userId": null,
  "userMessage": "User not found – proceed to create account.",
  "errorCode": null,
  "journeyHasError": false
}
```
Error (blocked) response:
```json
{
  "userExists": false,
  "userId": null,
  "userMessage": "The specified account is blocked.",
  "errorCode": "idm.user.blocked",
  "journeyHasError": true
}
```
Logic summary:
* Emails containing `legacy` or `exists` => treated as existing.
* Emails containing `blocked` => returns error with `journeyHasError=true`.
* All others => new user path.

Adjust this stub to integrate with a real IDM: replace the simulated rules with a repository / API client and map your real service response fields to the expected claim names in the JSON payload.

### 12.1.1 REST Error Simulation (Custom Error Page & Retry Demo)
To quickly validate custom error UI behavior (including retry countdown) without manipulating real downstream systems, the backend includes a simulation endpoint and the policy adds an `REST-IDM-ErrorSimulation` technical profile.

POST `/users/simulate-error`

Request:
```json
{ "scenario": "throttle", "correlationId": "<guid>" }
```

Supported scenarios:
| Scenario | Behavior | Error Code | retryAfter | Notes |
|----------|----------|-----------|-----------:|-------|
| `throttle` | Returns journey error with wait period | `idm.throttle` | 15 | Shows countdown on custom error page |
| `generic`  | Returns generic journey error | `idm.generic` | – | Default if omitted |
| `success`  | Returns non-error payload | – | – | `journeyHasError=false` |

Throttle example:
```json
{
  "userExists": false,
  "userId": null,
  "userMessage": "Too many attempts. Please retry later.",
  "errorCode": "idm.throttle",
  "journeyHasError": true,
  "retryAfter": 15
}
```

Technical profile snippet (example only – for current implementation see `TrustFrameworkExtensions.xml` `REST-UserValidation` rather than the older simulation profile):
```xml
<TechnicalProfile Id="REST-IDM-ErrorSimulation">
  <DisplayName>IDM Error Simulation</DisplayName>
  <Protocol Name="Proprietary" Handler="Web.TPEngine.Providers.RestfulProvider,Web.TPEngine" />
  <Metadata>
    <Item Key="ServiceUrl">https://idm-api.example.com/users/simulate-error</Item>
    <Item Key="AuthenticationType">ClientCertificate</Item>
    <Item Key="SendClaimsIn">Body</Item>
    <Item Key="ResolveJsonPathsInJsonTokens">true</Item>
  </Metadata>
  <CryptographicKeys>
    <Key Id="ClientCertificate" StorageReferenceId="B2C_1A_IDMApiClientCertificate" />
  </CryptographicKeys>
  <InputClaims>
    <InputClaim ClaimTypeReferenceId="correlationId" PartnerClaimType="correlationId" />
  </InputClaims>
  <OutputClaims>
    <OutputClaim ClaimTypeReferenceId="journeyErrorMessage" PartnerClaimType="userMessage" />
    <OutputClaim ClaimTypeReferenceId="journeyErrorCode" PartnerClaimType="errorCode" />
    <OutputClaim ClaimTypeReferenceId="journeyHasError" PartnerClaimType="journeyHasError" />
    <OutputClaim ClaimTypeReferenceId="journeyRetryAfter" PartnerClaimType="retryAfter" />
  </OutputClaims>
</TechnicalProfile>
```

Temporary orchestration step example (insert before SendClaims and renumber following steps):
```xml
<OrchestrationStep Order="X" Type="ClaimsExchange">
  <ClaimsExchanges>
    <ClaimsExchange Id="IDM-Error-Sim" TechnicalProfileReferenceId="REST-IDM-ErrorSimulation" />
  </ClaimsExchanges>
</OrchestrationStep>
```

If the simulation returns `journeyHasError=true`, the existing error handler (SelfAsserted-ErrorHandler) triggers and the custom `error.html` displays correlation ID, code, message, support link, and retry countdown.

Remove the step when finished testing to restore normal journey flow.

### 12.2 Securing the REST Endpoint
The custom policy technical profile currently specifies `AuthenticationType="ClientCertificate"`. To fully secure the call you have two main options:

| Option | Policy Setting | Backend Changes | When to Use |
|--------|----------------|-----------------|-------------|
| Mutual TLS (Client Certificate) | `AuthenticationType=ClientCertificate` + `<CryptographicKeys><Key Id="ClientCertificate" StorageReferenceId="B2C_1A_IDMApiClientCertificate"/></CryptographicKeys>` | Enable client cert capture (Kestrel) and validate thumbprint(s) | Production / strong auth needed |
| Basic Auth (simpler) | `AuthenticationType=Basic` + keys for `BasicAuthenticationUsername` & `BasicAuthenticationPassword` | Add Basic auth middleware verifying header | Quick dev / lower security |

Current repo implements an **optional client certificate validation** gate (see `RestApiAuth` section in `appsettings.json`). To activate:
1. Upload your client cert to B2C policy keys with name `B2C_1A_IDMApiClientCertificate`.
2. Get the thumbprint (uppercase, no spaces) and place it in `RestApiAuth:AllowedThumbprints`.
3. Set `RestApiAuth:RequireClientCertificate` to `true` (environment variable override recommended instead of committing value).
4. Ensure the REST technical profile still has `AuthenticationType` = `ClientCertificate`.

If you prefer Basic auth instead (simpler locally):
1. Create two policy keys (Manual): `B2C_1A_IdmApiBasicUsername`, `B2C_1A_IdmApiBasicPassword`.
2. Change the technical profile metadata: `<Item Key="AuthenticationType">Basic</Item>` and corresponding `<CryptographicKeys>` to use those keys (remove the certificate key for that profile).
3. Add Basic header validation middleware (not included yet) or switch the existing certificate middleware logic accordingly.

Important: Azure AD B2C cannot add arbitrary custom headers to REST calls—use only supported auth types. For production, prefer client certificate or a dedicated intermediary service protected by network controls.

### 12.3 JSON Directory Backing
The endpoint now looks up users from `Data/users.json`. To modify behavior:
1. Edit the JSON file and save—it's auto reloaded when timestamp changes.
2. Add fields or extend `DirectoryUser` if you need additional claim outputs (also update technical profile output mapping and controller response).
3. For large datasets, replace `JsonUserDirectory` with a DB or caching layer.


---
Custom policy configuration complete with tenant: `zipzappmetadatadev.onmicrosoft.com`.

## 13. Backend Deployment (Azure App Service – Simple ZIP Deploy)

For the simplest possible deployment of the **Contoso.IdentityApi** to an existing Azure App Service Web App we provide `scripts/Deploy-BackendApi.ps1`. It wraps a `dotnet publish` followed by:

```
az webapp deploy --resource-group <rg> --name <webAppName> --src-path <zip> --type zip --restart true
```

### 13.1 Prerequisites
* Azure CLI installed (`az version`)
* Logged in: `az login` (and if you have multiple subscriptions: `az account set --subscription <subIdOrName>`)
* Existing Web App (Linux or Windows) created for .NET 8 (runtime stack isn't strictly required when using self-contained publish, but this sample uses framework-dependent publish).

### 13.2 Script Parameters (minimal set)
| Parameter | Required | Description |
|-----------|----------|-------------|
| `-WebAppName` | Yes | Web App name OR full host (e.g. `contoso-transit-api-dev-...azurewebsites.net`) |
| `-ResourceGroup` | Yes | Resource group containing the Web App |
| `-ProjectPath` | No | Defaults to `backend/Contoso.IdentityApi/Contoso.IdentityApi.csproj` |
| `-Configuration` | No | Build configuration (default `Release`) |
| `-Framework` | No | Force a specific TFM (e.g. `net8.0`) |
| `-SkipBuild` | No | Skip `dotnet publish` (use existing folder) |
| `-ZipOnly` | No | Produce the ZIP without deploying |
| `-Force` | No | Overwrite existing ZIP if path collision |

### 13.3 Typical Usage
```powershell
# From repo root (Windows PowerShell / pwsh)
./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0 -ResourceGroup <your-resource-group>
```

If you copy the full host name, the script will automatically strip the domain, e.g.:
```powershell
./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0.australiaeast-01.azurewebsites.net -ResourceGroup <your-resource-group>
```

Verbose build & force overwrite of an existing zip:
```powershell
./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0 -ResourceGroup <rg> -Verbose -Force
```

Produce the ZIP artifact only (no deployment):
```powershell
./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0 -ResourceGroup <rg> -ZipOnly
```

### 13.4 Output Layout
* Publish output: `backend/Contoso.IdentityApi/bin/DeployPublish/<Configuration>-<timestamp>/`
* ZIP artifact: `artifacts/Contoso.IdentityApi-<timestamp>.zip`

### 13.5 Notes / Next Steps
* This is intentionally minimal. For blue/green or slot swaps, extend with `az webapp deployment slot` commands.
* Add health warm-up by invoking the site root after deploy if desired.
* For CI, integrate this script in a pipeline and provide `WebAppName` / `ResourceGroup` as variables or use native `azure/webapps-deploy` GitHub Action.
* To speed up repeat builds, add a `-SkipBuild` mode paired with caching published output in CI (dotnet publish incremental builds are already incremental if obj/bin are preserved).

### 13.6 Run From Package (Optional)
Enable a read‑only mounted ZIP (atomic style deploy) instead of file extraction:
```powershell
./scripts/Deploy-BackendApi.ps1 -WebAppName <app> -ResourceGroup <rg> -RunFromPackage [-LegacyConfigZip]
```
Behavior when `-RunFromPackage` is used:
1. Ensures `WEBSITE_RUN_FROM_PACKAGE=1` (skips if already a URL value).
2. By default uses `az webapp deploy --type zip` (current recommended command – the platform mounts the package automatically when the setting is present).
3. Sentinel DLL (`Contoso.IdentityApi.dll`) check before upload.
4. Optional `-LegacyConfigZip` forces the deprecated `webapp deployment source config-zip` path (only for troubleshooting older behavior; expect a deprecation warning).
If mounting fails, inspect Kudu event logs or redeploy without `-RunFromPackage`.

---

## 14. Frontend Deployment (Angular → Azure App Service ZIP Deploy)

The Angular SPA can be deployed to a standard Azure App Service (Linux or Windows) with the companion script `scripts/Deploy-Frontend.ps1`. This mirrors the backend deployment approach: build → zip → `az webapp deploy`.

### 14.1 Prerequisites
* Azure CLI logged in (`az login`)
* Node.js / npm
* (Optional) If a runtime-specific App Service plan is used (e.g. Node), ensure it's compatible with serving static assets. Otherwise any App Service can serve static files from `wwwroot`.

### 14.2 Script Parameters
| Parameter | Required | Description |
|----------|----------|-------------|
| `-WebAppName` | Yes | Web App name or full host (script strips domain) |
| `-ResourceGroup` | Yes | Resource group containing the Web App |
| `-FrontendDir` | No | Path to frontend root (default `frontend`) |
| `-ProjectName` | No | Angular project (defaults from `angular.json`) |
| `-Configuration` | No | Angular build config (`production` default) |
| `-DistPath` | No | Override dist output path |
| `-ZipPath` | No | Override artifact zip path |
| `-SkipInstall` | No | Skip `npm install` |
| `-SkipBuild` | No | Skip Angular build |
| `-ZipOnly` | No | Produce ZIP without deploy |
| `-Force` | No | Overwrite existing ZIP |

### 14.3 Typical Usage
```powershell
./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev -ResourceGroup <rg>
```

If you copy the full host name:
```powershell
./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev.azurewebsites.net -ResourceGroup <rg>
```

Skip reinstalling dependencies (useful in CI with caching) & force overwrite:
```powershell
./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev -ResourceGroup <rg> -SkipInstall -Force
```

Artifact only:
```powershell
./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev -ResourceGroup <rg> -ZipOnly
```

### 14.4 Output Layout
* Build output (Angular): `frontend/dist/b2c-frontend/`
* ZIP artifact: `artifacts/frontend-b2c-frontend-<timestamp>.zip`

### 14.5 Notes
* For SPA routing (client-side routes) configure a fallback rewrite rule in App Service (via `web.config` for Windows/IIS or add a simple Node server). Alternatively, add a `web.config` at the dist root mapping all unmatched paths to `index.html`.
* Consider using Azure Static Web Apps for global edge distribution and built‑in auth if requirements evolve.
* To add a fallback now, create `frontend/src/web.config` before build with a rewrite rule and list it under `assets`.

### 14.6 Run From Package (Optional)
```powershell
./scripts/Deploy-Frontend.ps1 -WebAppName <app> -ResourceGroup <rg> -RunFromPackage [-LegacyConfigZip]
```
When specified:
1. Ensures `WEBSITE_RUN_FROM_PACKAGE=1`.
2. Uses `az webapp deploy` by default (mounts when setting is present).
3. `index.html` sentinel validation.
4. `-LegacyConfigZip` available only if you need to compare legacy behavior (emits deprecation warning).
For SPA routing add a `web.config` rewrite so deep links resolve under run-from-package.

---
