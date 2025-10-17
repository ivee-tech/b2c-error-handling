export const environment = {
  production: false,
  b2c: {
    tenant: 'zipzappmetadatadev.onmicrosoft.com',
    clientId: 'd35ebbe9-3406-4c0b-bad1-8d92c47341b1',
  // NOTE: The custom policy file in policies/LocalAccounts is named with PolicyId="B2C_1A_signup_signin" (lowercase 'signup_signin').
  // The previous value here ('B2C_1A_SIGNUP_SIGNIN') pointed to a different (likely built-in) user flow, causing key mismatch (kid cpimcore_09252015) errors.
  // Aligning this value to the custom policy id to ensure the app calls the custom policy that references the correct signing/encryption keys.
  signInSignUpPolicy: 'B2C_1A_signup_signin', // 'B2C_1A_signup_signin', // was 'B2C_1A_SIGNUP_SIGNIN'
    authorityDomain: 'zipzappmetadatadev.b2clogin.com',
    // IMPORTANT: The scope must match what you created under Expose an API in the API app registration.
    // If you used Application ID URI = https://zipzappmetadatadev.onmicrosoft.com/api then the full scope is that plus /user.read
    // Example alternative (if using the api://<API_CLIENT_ID> style): 'api://f6bbbb2d-02dd-4ca4-83bd-bf0709107617/user.read'
    apiScopes: ['https://zipzappmetadatadev.onmicrosoft.com/contoso-transit-api/user.read'],
    // redirectUri: 'http://localhost:4200',
    // postLogoutRedirectUri: 'http://localhost:4200'
    redirectUri: 'https://contoso-transit-dev-app-gjafhqgaa8bnfme8.australiaeast-01.azurewebsites.net',
    postLogoutRedirectUri: 'https://contoso-transit-dev-app-gjafhqgaa8bnfme8.australiaeast-01.azurewebsites.net'
  },
  api: {
    // baseUrl: 'http://localhost:7071/api'
    baseUrl: 'https://contoso-transit-api-dev-eba5fcfughcfg0c0.australiaeast-01.azurewebsites.net/api'
  }
};
