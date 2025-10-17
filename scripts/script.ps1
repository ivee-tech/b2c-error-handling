# if getting error below, try logging in again with az login with the specified scope in the correct tenant
# Account has previously been signed out of this application.. Status: Response_Status.Status_AccountUnusable, Error code: 0, Tag: 540940121
az login --scope https://management.core.windows.net//.default --tenant $env:ZZ_TENANT_ID

$rgName = 'rg-contoso'
$appName = 'contoso-transit-api-dev'
.\scripts\Deploy-BackendApi.ps1 -WebAppName $appName -ResourceGroup $rgName
# $zipPath = '.\artifacts\Contoso.IdentityApi-20251017-002408.zip'
# az webapp deploy --resource-group $rgName --name $appName --src-path $zipPath --type zip --restart true


$rgName = 'rg-contoso'
$appName = 'contoso-transit-dev-app'
.\scripts\Deploy-Frontend.ps1 -WebAppName $appName -ResourceGroup $rgName
# $zipPath = '.\artifacts\frontend-b2c-frontend-20251016-224359.zip'
# az webapp deploy --resource-group $rgName --name $appName --src-path $zipPath --type zip --restart true


$u = "devuser"
$p = "***"
$pair = [System.Text.Encoding]::UTF8.GetBytes("$u`:$p") 
$basic = [Convert]::ToBase64String($pair)
$resp = Invoke-RestMethod -Method Post `
  -Uri "https://contoso-transit-api-dev-eba5fcfughcfg0c0.australiaeast-01.azurewebsites.net/users/validate" `
  -Headers @{ Authorization = "Basic $basic" } `
  -ContentType 'application/json' `
  -Body '{"email":"b@b.com","correlationId":"debug"}'
$resp | ConvertTo-Json -Depth 4