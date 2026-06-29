# Repository-wide Copilot instructions

- 変更前に`AGENTS.md`、関連設計書、対象の`tasks/*.md`を読む。
- 実装前に変更計画、対象ファイル、互換性リスク、テスト、ロールバック方法を提示する。
- 変更計画と実装には毎回`rubber-duck`エージェントを併用し、設計・ロジックの妥当性を検証する。
- 対象タスク外の変更を行わない。
- 既存PowerShellスクリプトの番号、既存CLI引数、生成物名を壊さない。
- SDK依存をドメインモデルへ混ぜず、`agent/src/**/integrations/`へ隔離する。
- モデル出力を確認済み事実として扱わず、事実へsourceを付ける。
- 正式担当者の選択をLLMへ委ねない。
- ツール失敗時は`warnings`と`open_questions`を返し、値を補完しない。
- テストからMicrosoft Foundry、Fabric、Azure AI Search、Microsoft Graphへ接続しない。
- commit候補を作る前に`git diff`と秘密情報混入を確認する。
- 実装後に`uv run pytest`と`uv run python scripts/export_schemas.py --check`を実行する。
- Git/GitHub 操作は Copilot が自律代行する。詳細は「Git/GitHub 運用（チーム fork モデル）」節に従う。

## Git/GitHub 運用（チーム fork モデル）

利用者はチーム開発の Git/GitHub 運用に不慣れなため、下記を Copilot が自律的に代行する。チームに見える操作・不可逆な操作のみ事前に承認を得る。

### リポジトリ構成
- `origin` = 自分の fork。`upstream` = チームの基準リポジトリ。
- Pull Request の base は常に `upstream/main`。`upstream` へは直接 push せず、貢献は必ず PR 経由。
- push 先は常に `origin`。`main` へ直接 commit/push しない（AGENTS.md 条件17）。
- `origin/main` は fast-forward のみで `upstream/main` へ追従させる（`git fetch upstream` → `git checkout main` → `git merge --ff-only upstream/main` → `git push origin main`）。`origin/main` を force-push しない。

### ブランチ運用
- 変更は必ず feature branch（`feature/<topic>`、可能なら対象 tasks 番号に対応）で行う。原則 1つの `tasks/*.md` = 1 branch = 1 PR。
- ワークフローや instruction などのメタ変更は、タスク実装ブランチと分け、`chore/<topic>` 等の別ブランチにする。
- 新規作業前に `git fetch upstream` し、`upstream/main` を起点にする。
- feature branch の最新化:
  - 未 push のローカルブランチ: `upstream/main` への rebase 可。
  - push 済み／PR 化済みブランチ: `upstream/main` を merge で取り込み、履歴を書き換えない。
  - rebase が必須の場合のみ承認のうえ `--force-with-lease`。素の force-push は禁止。

### commit / push
- 意味のある区切り（タスク完了・レビュー可能単位）で自律的に commit→push する。
- staging はスコープを限定: `git status --short` を確認し、`git add .` を避けて対象ファイルだけ stage、`git diff --staged` で確認。秘密情報（トークン・接続文字列・実メール）混入を毎回チェック。
- commit メッセージ末尾に `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` を付ける。
- WIP バックアップを push する場合でテスト未実施/未通過なら、その旨を commit/PR に明記する。

### Pull Request
- WIP は早めに Draft PR を作成してチームへ可視化する（自律実行可、作成後に利用者へ報告）。
  - 例: `gh pr create --repo akikawa1123/fabric-dynamics-erp-integration --base main --head naoki1213mj:feature/<topic> --draft`（`--head` は `<owner>:<branch>` 形式）。
- PR 説明は進捗に応じて随時更新する（自律実行可）。
- Ready / マージ前チェック: `git fetch upstream` → `git log --oneline upstream/main..HEAD` と `git diff --stat upstream/main...HEAD` で対象タスクのファイルだけが含まれることを確認し、`uv run pytest` と `uv run python scripts/export_schemas.py --check` を通す。
- レビュー指摘は同じ feature branch に通常 commit して対応する。レビュー開始後の amend/squash/rebase は reviewer の合意がない限り行わない。

### 自律実行と承認の境界
- 事前確認なしで自律実行してよい: 自 fork の feature/chore branch への commit/push、Draft PR の作成（事後報告）と説明更新、`origin/main` の ff-only 追従。
- 事前に利用者の承認を得る: PR の Ready 化・マージ・close、ブランチ/タグ削除、共有ブランチの force-push（`--force-with-lease` 含む）、`upstream` への直接操作、リリースタグ作成、履歴書き換え。
