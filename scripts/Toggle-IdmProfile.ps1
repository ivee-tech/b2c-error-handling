<#+
 .SYNOPSIS
    Toggles the REST-IDM-UserValidation technical profile between dev (Basic) and prod (ClientCertificate) modes.
 .DESCRIPTION
    Safely edits the XML using DOM operations (namespace aware) instead of brittle regex replacements.
    Only the targeted TechnicalProfile is modified. Other ServiceUrl / AuthenticationType entries remain untouched.
 .PARAMETER Mode
    'dev'  - Basic authentication with username/password keys.
    'prod' - Client certificate authentication.
 .PARAMETER Path
    Relative or absolute path to the extensions policy XML file to modify.
 .PARAMETER DevServiceUrl / ProdServiceUrl
    Service URLs for each mode.
 .PARAMETER Backup
    Creates a timestamped .bak file before modifying.
 .EXAMPLE
    ./Toggle-IdmProfile.ps1 -Mode dev
 .EXAMPLE
    ./Toggle-IdmProfile.ps1 -Mode prod -ProdServiceUrl https://idm.company.com/users/validate
#>
param(
    [ValidateSet('dev','prod')] [string]$Mode = 'dev',
    [string]$Path = 'policies/B2C_1A_TrustFrameworkExtensions_v1_2_0.xml',
    [string]$DevServiceUrl = 'http://localhost:7071/users/validate',
    [string]$ProdServiceUrl = 'https://idm-api.example.com/users/validate',
    [switch]$Backup
)

if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }

if ($Backup) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $Path -Destination "$Path.$stamp.bak" -Force
}

[xml]$doc = Get-Content -LiteralPath $Path -Raw

# Namespace handling (default namespace present on root)
$nsMgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
$nsMgr.AddNamespace('cpim','http://schemas.microsoft.com/online/cpim/schemas/2013/06')

$tp = $doc.SelectSingleNode("//cpim:TechnicalProfile[@Id='REST-IDM-UserValidation']", $nsMgr)
if (-not $tp) { throw "TechnicalProfile 'REST-IDM-UserValidation' not found in $Path" }

function Upsert-MetadataItem($tpNode, $key, $value) {
    $metadata = $tpNode.Metadata
    if (-not $metadata) {
        $metadata = $tpNode.OwnerDocument.CreateElement('Metadata', $tpNode.NamespaceURI)
        $null = $tpNode.AppendChild($metadata)
    }
    $existing = $metadata.Item | Where-Object { $_.Key -eq $key }
    if ($existing) {
        $existing.InnerText = $value
    } else {
        $item = $tpNode.OwnerDocument.CreateElement('Item', $tpNode.NamespaceURI)
        $item.SetAttribute('Key',$key)
        $item.InnerText = $value
        $null = $metadata.AppendChild($item)
    }
}

function Set-AuthBasic($tpNode){
    Upsert-MetadataItem $tpNode 'AuthenticationType' 'Basic'
    Upsert-MetadataItem $tpNode 'ServiceUrl' $DevServiceUrl
    # Replace CryptographicKeys block
    $ck = $tpNode.SelectSingleNode('cpim:CryptographicKeys', $nsMgr)
    if ($ck) { $null = $tpNode.RemoveChild($ck) }
    $newCk = $tpNode.OwnerDocument.CreateElement('CryptographicKeys', $tpNode.NamespaceURI)
    $comment = $tpNode.OwnerDocument.CreateComment(' Create these policy keys in B2C: B2C_1A_IdmApiBasicUsername / B2C_1A_IdmApiBasicPassword ')
    $null = $newCk.AppendChild($comment)
    foreach($pair in @('BasicAuthenticationUsername','BasicAuthenticationPassword')){
        $keyNode = $tpNode.OwnerDocument.CreateElement('Key', $tpNode.NamespaceURI)
        $keyNode.SetAttribute('Id',$pair)
        $keyNode.SetAttribute('StorageReferenceId',("B2C_1A_" + ($pair -replace 'BasicAuthentication','IdmApiBasic')))
        $null = $newCk.AppendChild($keyNode)
    }
    # Insert after Metadata for readability
    $metadata = $tpNode.SelectSingleNode('cpim:Metadata', $nsMgr)
    if ($metadata -and $metadata.NextSibling) { $null = $tpNode.InsertAfter($newCk, $metadata) } else { $null = $tpNode.AppendChild($newCk) }
    # DisplayName
    $display = $tpNode.SelectSingleNode('cpim:DisplayName', $nsMgr)
    if ($display) { $display.InnerText = 'IDM User Validation (Dev - Basic Auth)' }
}

function Set-AuthCert($tpNode){
    Upsert-MetadataItem $tpNode 'AuthenticationType' 'ClientCertificate'
    Upsert-MetadataItem $tpNode 'ServiceUrl' $ProdServiceUrl
    $ck = $tpNode.SelectSingleNode('cpim:CryptographicKeys', $nsMgr)
    if ($ck) { $null = $tpNode.RemoveChild($ck) }
    $newCk = $tpNode.OwnerDocument.CreateElement('CryptographicKeys', $tpNode.NamespaceURI)
    $keyNode = $tpNode.OwnerDocument.CreateElement('Key', $tpNode.NamespaceURI)
    $keyNode.SetAttribute('Id','ClientCertificate')
    $keyNode.SetAttribute('StorageReferenceId','B2C_1A_IDMApiClientCertificate')
    $null = $newCk.AppendChild($keyNode)
    $metadata = $tpNode.SelectSingleNode('cpim:Metadata', $nsMgr)
    if ($metadata -and $metadata.NextSibling) { $null = $tpNode.InsertAfter($newCk, $metadata) } else { $null = $tpNode.AppendChild($newCk) }
    $display = $tpNode.SelectSingleNode('cpim:DisplayName', $nsMgr)
    if ($display) { $display.InnerText = 'IDM User Validation (Prod - mTLS)' }
}

switch($Mode){
    'dev'  { Set-AuthBasic $tp }
    'prod' { Set-AuthCert  $tp }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$writerSettings = New-Object System.Xml.XmlWriterSettings
$writerSettings.Indent = $true
$writerSettings.Encoding = $utf8NoBom
[System.Xml.XmlWriter] $writer = [System.Xml.XmlWriter]::Create($Path,$writerSettings)
$doc.Save($writer)
$writer.Flush();$writer.Close()

Write-Host "Updated REST-IDM-UserValidation to mode '$Mode' (ServiceUrl: " -NoNewline; Write-Host ($Mode -eq 'dev' ? $DevServiceUrl : $ProdServiceUrl) -ForegroundColor Cyan
