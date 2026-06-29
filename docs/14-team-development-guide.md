# チーム開発の進め方

## remote

```text
origin   = 自分のfork
upstream = チームの元リポジトリ
```

## 毎日の開始

```powershell
git status
git fetch upstream
git merge upstream/main
git push
```

## 1タスクのサイクル

1. taskを1つ選ぶ
2. Copilot CLIに計画だけ出させる
3. 変更対象を確認
4. 実装
5. `git diff`
6. テスト
7. 小さくcommit
8. push
9. Draft PRでレビュー依頼

## conflict

判断できない競合を勝手に解決しない。

```powershell
git status
git merge --abort
```

`git push --force`と`git reset --hard`は使わない。
