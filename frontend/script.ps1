$tenant = 'zipzappmetadatadev.onmicrosoft.com'
$policy = 'B2C_1A_signup_signin'
$appId = 'd35ebbe9-3406-4c0b-bad1-8d92c47341b1' # your SPA client
$username = 'radudanielro@yahoo.com'
$password = '***'

$body = @{
  grant_type='password'
  username=$username
  password=$password
  scope='openid'
  client_id=$appId
}
$tokenEndpoint = "https://$tenant.b2clogin.com/$tenant/$policy/oauth2/v2.0/token"
Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body