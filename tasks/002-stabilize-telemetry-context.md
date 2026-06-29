# Task 002: 異常ロットとActivator文脈を安定化する

- telemetry_sender.pyへ`--anomaly-lot-id`を追加する。
- 未指定時は異常フェーズ開始時にlotを1回生成する。
- 異常対象product / stationへ同じlotを設定する。
- 既存CLIオプションを維持する。
- Activator用KQLをstation + product + lot単位へ変更する。
- README / DEMOを更新する。
- 既存Fabric担当者と変更ファイルを共有する。
