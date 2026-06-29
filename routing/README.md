# StakeholderRouting

`stakeholder-routing.sample.csv`をSharePoint Listへインポートする想定。
サンプルUPNは実環境のデモ利用者へ置換し、実値を公開リポジトリへcommitしない。

ローカル検証:

```powershell
cd agent
uv run mq-routing-check ..\routing\stakeholder-routing.sample.csv ..\contracts\samples\routing-context-sales.json sales_owner
```
