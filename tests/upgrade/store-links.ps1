# Prints "<package full name> <download url>" per package of a Store app (default: the Codex App), asking the Store's own endpoints:
# displaycatalog for the WU category, then fe3.delivery.mp.microsoft.com (Windows Update) for the files.
# Request templates in fe3\ come from StoreDev/StoreLib (MPL-2.0).
param([string]$ProductId = '9PLM9XGG6VKS', [string]$Token = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$endpoint = 'https://fe3.delivery.mp.microsoft.com/ClientWebService/client.asmx'
function Template($name, [string[]]$values) {
  $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "fe3\$name"), [Text.Encoding]::UTF8)
  for ($i = 0; $i -lt $values.Count; $i++) { $text = $text.Replace("{$i}", $values[$i]) }
  $text
}
function Soap($url, $body) {
  $r = Invoke-WebRequest -UseBasicParsing -Uri $url -Method Post -ContentType 'application/soap+xml; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
}
$catalog = Invoke-RestMethod "https://displaycatalog.mp.microsoft.com/v7.0/products/$ProductId`?market=US&languages=en-US"
$fulfillment = $catalog.Product.DisplaySkuAvailabilities[0].Sku.Properties.FulfillmentData
if ($fulfillment -is [string]) { $fulfillment = $fulfillment | ConvertFrom-Json }
$cookie = [regex]::Match((Soap $endpoint (Template 'GetCookie.xml' @())), '<EncryptedData>(.*?)</EncryptedData>').Groups[1].Value
$sync = [Net.WebUtility]::HtmlDecode((Soap $endpoint (Template 'WUIDRequest.xml' @($cookie, $fulfillment.WuCategoryId, $Token))))
foreach ($m in [regex]::Matches($sync, '<UpdateInfo>.*?</UpdateInfo>', 'Singleline')) {
  if ($m.Value -notmatch 'SecuredFragment') { continue }
  $package = [regex]::Match($m.Value, 'PackageMoniker="([^"]+)"').Groups[1].Value
  $identity = [regex]::Match($m.Value, '<UpdateIdentity UpdateID="([^"]+)" RevisionNumber="(\d+)"')
  $reply = Soap "$endpoint/secured" (Template 'FE3FileUrl.xml' @($identity.Groups[1].Value, $identity.Groups[2].Value, $Token))
  foreach ($u in [regex]::Matches($reply, '<Url>(.*?)</Url>')) {
    $url = [Net.WebUtility]::HtmlDecode($u.Groups[1].Value)
    if ($url.Length -ne 99) { "$package $url" }   # the 99-character one is the block map
  }
}
