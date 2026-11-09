<#
  WifiZone-Proxy.ps1
  Connecte le PC a internet a travers le telephone Android (Wi-Fi Zone partage
  via l'application Every Proxy ou NetShare).

  Utilisation :
    -Action Activer     : trouve le proxy du telephone, le teste et l'active
    -Action Desactiver  : remet le PC en connexion normale (sans proxy)
    -Action Diagnostic  : affiche l'etat du reseau sans rien modifier
#>
param(
    [ValidateSet('Activer', 'Desactiver', 'Diagnostic')]
    [string]$Action = 'Activer'
)

$ErrorActionPreference = 'SilentlyContinue'
$RegPath  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$Ports    = @(8080, 8282, 8000, 3128, 8888)          # Every Proxy = 8080, NetShare = 8282
$TestUrls = @('http://www.msftconnecttest.com/connecttest.txt', 'http://example.com/')

function Write-Titre($t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Write-Ok($t)    { Write-Host "  [OK]  $t" -ForegroundColor Green }
function Write-Err($t)   { Write-Host "  [X]   $t" -ForegroundColor Red }
function Write-Info($t)  { Write-Host "  ...   $t" -ForegroundColor Gray }

# Previent Windows / les navigateurs que les reglages proxy ont change
function Update-ProxySettings {
    $sig = @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(System.IntPtr h, int opt, System.IntPtr buf, int len);
'@
    try {
        $wi = Add-Type -MemberDefinition $sig -Name WinInetRefresh -Namespace WifiZone -PassThru
        [void]$wi::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)  # SETTINGS_CHANGED
        [void]$wi::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)  # REFRESH
    } catch { }
}

function Set-ProxyOff {
    Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0 -Type DWord
    Update-ProxySettings
}

function Set-ProxyOn([string]$server) {
    Set-ItemProperty -Path $RegPath -Name ProxyServer   -Value $server
    Set-ItemProperty -Path $RegPath -Name ProxyOverride -Value '<local>;localhost;127.*;10.*;192.168.*'
    Set-ItemProperty -Path $RegPath -Name ProxyEnable   -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name AutoDetect    -Value 0 -Type DWord
    Update-ProxySettings
}

function Test-Port([string]$ip, [int]$port, [int]$timeoutMs = 700) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $t = $c.ConnectAsync($ip, $port)
        return ($t.Wait($timeoutMs) -and $c.Connected)
    } catch { return $false } finally { $c.Close() }
}

function Test-Internet([string]$proxy) {
    foreach ($u in $TestUrls) {
        try {
            $p = @{ Uri = $u; UseBasicParsing = $true; TimeoutSec = 10 }
            if ($proxy) { $p.Proxy = "http://$proxy" }
            $r = Invoke-WebRequest @p
            # Un portail captif renvoie une page de connexion au lieu du vrai contenu
            if ($u -like '*connecttest*') { if ($r.Content -match 'Microsoft Connect Test') { return $true } }
            elseif ($r.Content -match 'Example Domain') { return $true }
        } catch { }
    }
    return $false
}

# Liste des adresses ou le telephone peut se trouver
function Get-Candidates {
    $list = New-Object System.Collections.Generic.List[string]
    $cfgs = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address }
    foreach ($c in $cfgs) {
        foreach ($g in $c.IPv4DefaultGateway) { if ($g.NextHop -and $g.NextHop -ne '0.0.0.0') { $list.Add($g.NextHop) } }
        foreach ($a in $c.IPv4Address) {
            $o = $a.IPAddress.Split('.')
            if ($o[0] -ne '169') { $list.Add("$($o[0]).$($o[1]).$($o[2]).1") }
        }
    }
    # Adresses habituelles des points d'acces Android / NetShare
    foreach ($x in @('192.168.43.1', '192.168.49.1', '192.168.42.129', '172.20.10.1')) { $list.Add($x) }
    return $list | Select-Object -Unique
}

function Show-Reseau {
    Write-Titre 'Etat du reseau du PC'
    $cfgs = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
    if (-not $cfgs) { Write-Err 'Aucune carte reseau connectee. Connecte le PC au point d acces du telephone.'; return }
    foreach ($c in $cfgs) {
        $ip = ($c.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '
        $gw = ($c.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ', '
        $ssid = ''
        if ($c.InterfaceAlias -match 'Wi-?Fi|Sans fil|Wireless|WLAN') {
            $line = (netsh wlan show interfaces) | Select-String '^\s*SSID\s*:' | Select-Object -First 1
            if ($line) { $ssid = ($line.ToString() -split ':', 2)[1].Trim() }
        }
        Write-Host ("  Carte      : {0}" -f $c.InterfaceAlias)
        if ($ssid) { Write-Host ("  Reseau     : {0}" -f $ssid) }
        Write-Host ("  Adresse IP : {0}" -f $ip)
        Write-Host ("  Passerelle : {0}" -f $gw)
        if ($ip -like '169.254.*') { Write-Err 'Adresse 169.254.x.x : le PC n a pas recu d adresse du telephone.' }
        Write-Host ''
    }
    $p = Get-ItemProperty -Path $RegPath
    if ($p.ProxyEnable -eq 1) { Write-Info "Proxy actuellement ACTIVE : $($p.ProxyServer)" }
    else { Write-Info 'Proxy actuellement desactive.' }
}

# ------------------------------------------------------------------------------
switch ($Action) {

    'Desactiver' {
        Set-ProxyOff
        Write-Titre 'Proxy desactive'
        Write-Ok 'Le PC utilise de nouveau la connexion normale.'
    }

    'Diagnostic' {
        Show-Reseau
        Write-Titre 'Recherche du proxy du telephone'
        foreach ($ip in Get-Candidates) {
            foreach ($port in $Ports) {
                if (Test-Port $ip $port) { Write-Ok "Proxy trouve : $ip`:$port" }
            }
        }
        Write-Titre 'Test internet direct (sans proxy)'
        if (Test-Internet $null) { Write-Ok 'Internet fonctionne sans proxy.' } else { Write-Err 'Pas d internet sans proxy.' }
    }

    'Activer' {
        Show-Reseau

        # On coupe d'abord l'ancien proxy pour que les tests soient fiables
        Set-ProxyOff

        Write-Titre 'Etape 1 : internet fonctionne-t-il deja sans proxy ?'
        if (Test-Internet $null) {
            Write-Ok 'Oui ! Le PC a deja internet, aucun proxy n est necessaire.'
            break
        }
        Write-Info 'Non (normal avec un Wi-Fi Zone qui bloque le partage). On cherche le proxy...'

        Write-Titre 'Etape 2 : recherche du proxy sur le telephone'
        $found = @()
        foreach ($ip in Get-Candidates) {
            foreach ($port in $Ports) {
                Write-Host ("  ...   essai {0}:{1}" -f $ip, $port) -ForegroundColor DarkGray
                if (Test-Port $ip $port) { Write-Ok "Proxy repond sur $ip`:$port"; $found += "$ip`:$port" }
            }
        }

        if (-not $found) {
            Write-Titre 'ECHEC : aucun proxy trouve'
            Write-Host @'
  Le PC ne parvient pas a joindre Every Proxy sur le telephone. Verifie :
   1. Le PC est connecte au POINT D ACCES DU TELEPHONE (pas a un autre Wi-Fi).
   2. Every Proxy est OUVERT et "Proxy HTTP" est ACTIVE (bouton bleu).
   3. Dans Every Proxy, appuie sur le crayon a cote de "Proxy HTTP" :
      l hote doit etre 0.0.0.0 et le port 8080.
   4. Telephone : Parametres > Applications > Every Proxy > Batterie
      > "Aucune restriction".
   5. Desactive puis reactive le point d acces, reconnecte le PC,
      et relance ce programme.
'@ -ForegroundColor Yellow
            break
        }

        Write-Titre 'Etape 3 : test d internet a travers le proxy'
        $ok = $null
        foreach ($f in $found) {
            Write-Info "test via $f ..."
            if (Test-Internet $f) { $ok = $f; break } else { Write-Err "pas d internet via $f" }
        }

        if (-not $ok) {
            Write-Titre 'ECHEC : le proxy repond mais n a pas internet'
            Write-Host @'
  Le telephone recoit bien les demandes du PC, mais n arrive pas a aller
  sur internet. Verifie :
   1. Sur le TELEPHONE, ouvre un site dans Chrome : internet doit marcher.
      Sinon, reconnecte-toi au Wi-Fi Zone (code / ticket expire ?).
   2. Telephone : Parametres > Plus de connexions > DNS prive > Desactive.
   3. Ferme completement Every Proxy, rouvre-le, reactive "Proxy HTTP",
      puis relance ce programme.
'@ -ForegroundColor Yellow
            Write-Info ("Le proxy {0} est quand meme active pour que tu puisses tester." -f $found[0])
            Set-ProxyOn $found[0]
            break
        }

        Set-ProxyOn $ok
        Write-Titre 'SUCCES'
        Write-Ok "Internet fonctionne via le telephone (proxy $ok)."
        Write-Host ''
        Write-Host '  - Ouvre Chrome ou Edge : les sites doivent s afficher.' -ForegroundColor White
        Write-Host '  - Windows peut afficher "Pas de connexion Internet" : c est normal, ignore-le.' -ForegroundColor White
        Write-Host '  - Laisse Every Proxy ouvert sur le telephone.' -ForegroundColor White
        Write-Host '  - Sur un autre Wi-Fi, lance 2-DESACTIVER-PROXY.bat.' -ForegroundColor White
    }
}
