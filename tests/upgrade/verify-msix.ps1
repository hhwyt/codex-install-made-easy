# Keeps a downloaded Codex App package only when its signature is the Store's: valid, signed for OpenAI's Store
# publisher (the publisher in the package manifest) by a Microsoft CA. Renames <name>.part.msix to <name>.msix, or
# deletes it and fails.
param([Parameter(Mandatory)][string]$Path, [string]$Publisher = 'CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B')
$ErrorActionPreference = 'Stop'
# The partial file still ends in .msix: the signature check picks how to read a file by its extension
if ($Path -notmatch '\.part\.msix$') { throw "expected a .part.msix file: $Path" }
$signature = Get-AuthenticodeSignature -LiteralPath $Path
$certificate = $signature.SignerCertificate
if ($signature.Status -ne 'Valid' -or $certificate.Subject -ne $Publisher -or $certificate.Issuer -notmatch 'O=Microsoft Corporation') {
  Remove-Item -LiteralPath $Path
  throw "bad signature, deleted: $($signature.Status) / $($certificate.Subject) / $($certificate.Issuer)"
}
$final = $Path -replace '\.part\.msix$', '.msix'
Move-Item -LiteralPath $Path $final -Force
"$final  signed by $($certificate.Issuer)"
