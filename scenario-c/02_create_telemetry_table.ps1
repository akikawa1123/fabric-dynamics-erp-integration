# フェーズ1: Telemetry テーブル + ストリーミング取り込みポリシー + 取込マッピング
. "$PSScriptRoot\kql_common.ps1"

# 1) テーブル作成（scenario-c のスキーマ準拠）
$createTable = @"
.create-merge table Telemetry (
    event_time: datetime,
    plant_id: string,
    line_id: string,
    station_id: string,
    product_number: string,
    lot_id: string,
    vibration_mm_s: real,
    temperature_c: real,
    torque_nm: real,
    dimension_dev_um: real,
    status: string,
    defect_flag: int
)
"@
Write-Host "== Telemetry テーブル作成 =="
Invoke-Kql -Csl $createTable | Out-Null

# 2) ストリーミング取り込みを有効化（低遅延でリアルタイム反映）
Write-Host "== ストリーミング取り込みポリシー有効化 =="
Invoke-Kql -Csl ".alter table Telemetry policy streamingingestion enable" | Out-Null

# 3) JSON 取込マッピング（直接 Kusto ingest 用 / Eventstream でも流用可）
$mapJson = '[{"column":"event_time","Properties":{"Path":"$.event_time"}},{"column":"plant_id","Properties":{"Path":"$.plant_id"}},{"column":"line_id","Properties":{"Path":"$.line_id"}},{"column":"station_id","Properties":{"Path":"$.station_id"}},{"column":"product_number","Properties":{"Path":"$.product_number"}},{"column":"lot_id","Properties":{"Path":"$.lot_id"}},{"column":"vibration_mm_s","Properties":{"Path":"$.vibration_mm_s"}},{"column":"temperature_c","Properties":{"Path":"$.temperature_c"}},{"column":"torque_nm","Properties":{"Path":"$.torque_nm"}},{"column":"dimension_dev_um","Properties":{"Path":"$.dimension_dev_um"}},{"column":"status","Properties":{"Path":"$.status"}},{"column":"defect_flag","Properties":{"Path":"$.defect_flag"}}]'
$mapping = ".create-or-alter table Telemetry ingestion json mapping ""telemetry_json_mapping"" '$mapJson'"
Write-Host "== JSON 取込マッピング作成 =="
Invoke-Kql -Csl $mapping | Out-Null

# 4) 確認
Write-Host "== スキーマ確認 =="
Invoke-Kql -Csl "Telemetry | getschema | project ColumnName, ColumnType" -Query | Format-Table -AutoSize
Write-Host "== 行数 =="
Invoke-Kql -Csl "Telemetry | count" -Query | Format-Table -AutoSize
