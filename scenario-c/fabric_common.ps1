# 共通: Fabric REST / Kusto 用のトークン取得と環境設定
# 他スクリプトから dot-source して使う:  . "$PSScriptRoot\fabric_common.ps1"
#
# 環境固有の値（WorkspaceId 等）はリポジトリに含めず、以下のいずれかから読み込む:
#   1) 環境変数  FABRIC_WORKSPACE_ID / FABRIC_ERP_LAKEHOUSE_ID / FABRIC_ALERT_RECIPIENT
#   2) config.local.json （config.example.json をコピーして作成。.gitignore 済）

$global:FabricApiBase = 'https://api.fabric.microsoft.com/v1'

$cfgPath = Join-Path $PSScriptRoot 'config.local.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { $null }

$global:WorkspaceId    = [Environment]::GetEnvironmentVariable('FABRIC_WORKSPACE_ID')
$global:ErpLakehouseId = [Environment]::GetEnvironmentVariable('FABRIC_ERP_LAKEHOUSE_ID')
$global:AlertRecipient = [Environment]::GetEnvironmentVariable('FABRIC_ALERT_RECIPIENT')
if ($cfg) {
    if (-not $global:WorkspaceId)    { $global:WorkspaceId    = $cfg.workspaceId }
    if (-not $global:ErpLakehouseId) { $global:ErpLakehouseId = $cfg.erpLakehouseId }
    if (-not $global:AlertRecipient) { $global:AlertRecipient = $cfg.alertRecipient }
}
if (-not $global:WorkspaceId) {
    throw "WorkspaceId が未設定です。config.example.json をコピーして config.local.json を作成し workspaceId を設定するか、環境変数 FABRIC_WORKSPACE_ID を設定してください。"
}

function Get-FabricToken {
    az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
}

function Get-KustoToken {
    az account get-access-token --resource https://kusto.fabric.microsoft.com --query accessToken -o tsv
}

function Get-FabricHeaders {
    @{ Authorization = "Bearer $(Get-FabricToken)"; 'Content-Type' = 'application/json' }
}

# LRO(長時間処理)に対応した Fabric REST 呼び出し。完了まで待機して結果を返す。
# Windows PowerShell 5.1 互換 (Invoke-WebRequest は非2xxで例外を投げる)
function Invoke-FabricRest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,        # 例: /workspaces/{ws}/eventhouses
        [object]$Body
    )
    $headers = Get-FabricHeaders
    # Content-Type に charset を明示し、ボディは UTF-8 バイト列で送る
    # (PS5.1 は文字列ボディを Latin1 でエンコードするため日本語が ? に化ける)
    $headers['Content-Type'] = 'application/json; charset=utf-8'
    $uri = "$FabricApiBase$Path"
    # if 式の戻り値はパイプラインで byte[] -> object[] に展開されてしまうため
    # 明示的に byte[] として代入する (object[] だと数値配列として送信されて 400 になる)
    $bodyBytes = $null
    if ($null -ne $Body) {
        [byte[]]$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 30))
    }

    try {
        $resp = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyBytes -UseBasicParsing
    }
    catch {
        $r = $_.Exception.Response
        if ($r) {
            $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
            $errBody = $sr.ReadToEnd()
            throw "HTTP $([int]$r.StatusCode) : $errBody"
        }
        throw
    }

    $code = [int]$resp.StatusCode

    if ($code -eq 202) {
        # 非同期。Location/Operation を完了までポーリング
        $opUrl = $resp.Headers['Location']
        if ($opUrl -is [array]) { $opUrl = $opUrl[0] }
        Write-Host "  LRO accepted, polling: $opUrl"
        for ($i = 0; $i -lt 100; $i++) {
            Start-Sleep -Seconds 3
            $op = Invoke-RestMethod -Uri $opUrl -Headers (Get-FabricHeaders)
            if ($op.status -eq 'Succeeded') {
                $resultUrl = "$opUrl/result"
                try { return Invoke-RestMethod -Uri $resultUrl -Headers (Get-FabricHeaders) } catch { return $op }
            }
            elseif ($op.status -eq 'Failed') {
                throw "LRO failed: $($op | ConvertTo-Json -Depth 10)"
            }
        }
        throw "LRO timed out"
    }
    elseif ($code -ge 200 -and $code -lt 300) {
        if ($resp.Content) { return ($resp.Content | ConvertFrom-Json) }
        return $null
    }
    else {
        throw "HTTP $code : $($resp.Content)"
    }
}

function Get-FabricItems {
    param([string]$Type)
    $r = Invoke-FabricRest -Method GET -Path "/workspaces/$WorkspaceId/items"
    if ($Type) { return $r.value | Where-Object { $_.type -eq $Type } }
    return $r.value
}
