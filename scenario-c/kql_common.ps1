# KQL 実行ヘルパー (管理コマンド/クエリ)
# 使い方: . "$PSScriptRoot\kql_common.ps1"; Invoke-Kql -Csl ".show tables"
. "$PSScriptRoot\fabric_common.ps1"

function Get-RtiInfo {
    $p = "$PSScriptRoot\rti_info.json"
    if (-not (Test-Path $p)) { throw "rti_info.json がありません。先に 01_create_eventhouse.ps1 を実行してください。" }
    Get-Content $p -Raw | ConvertFrom-Json
}

# KQL 管理コマンド or クエリを実行
function Invoke-Kql {
    param(
        [Parameter(Mandatory)][string]$Csl,
        [string]$Database,
        [switch]$Query   # 指定時は v1/rest/query, 既定は mgmt
    )
    $info = Get-RtiInfo
    if (-not $Database) { $Database = $info.databases[0].name }
    $clusterUri = $info.databases[0].queryUri
    $endpoint = if ($Query) { "$clusterUri/v1/rest/query" } else { "$clusterUri/v1/rest/mgmt" }

    # Fabric Eventhouse はクラスタ URI 自体をトークンのリソースに使う
    $kustoTok = az account get-access-token --resource $clusterUri --query accessToken -o tsv
    $headers = @{
        Authorization  = "Bearer $kustoTok"
        'Content-Type' = 'application/json'
        Accept         = 'application/json'
    }
    $body = @{ db = $Database; csl = $Csl } | ConvertTo-Json -Depth 5

    try {
        $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $body
    }
    catch {
        $r = $_.Exception.Response
        if ($r) {
            $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
            throw "KQL error HTTP $([int]$r.StatusCode): $($sr.ReadToEnd())"
        }
        throw
    }
    # 表形式の結果を扱いやすいオブジェクトに整形
    if ($resp.Tables) {
        $t = $resp.Tables[0]
        $cols = $t.Columns.ColumnName
        return $t.Rows | ForEach-Object {
            $row = $_; $o = [ordered]@{}
            for ($i=0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
            [pscustomobject]$o
        }
    }
    return $resp
}
