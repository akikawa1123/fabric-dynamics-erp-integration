---
applyTo: "agent/**/*.py,agent/pyproject.toml,routing/**/*.py"
---

- Python 3.13を対象にする。
- 依存関係はuvで管理する。
- Pydantic v2を使用し、`extra="forbid"`を設定する。
- 外部SDKのimportは`integrations/`へ限定するか遅延importする。
- 公開関数に型ヒントを付ける。
- `except Exception: pass`を追加しない。
- ロジックはネットワークなしで単体テスト可能にする。
