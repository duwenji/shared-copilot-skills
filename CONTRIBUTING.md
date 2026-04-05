# Contributing

改善提案や shared skill の追加・更新は歓迎します。

## 基本方針
- consumer repo で再利用しやすい構成を維持してください。
- 変更時は wrapper / templates / docs の整合性も確認してください。
- 新規教材のランディングページは `templates/tutorial-content/` を基点にし、`spa-quiz-app` 案内文を共通化してください。
- 大きな変更は `Issue` で背景共有してから進めてください。

## 推奨フロー
1. `Issue` を作成する
2. branch を切る
3. 対象 skill と `templates/` / `docs/` を更新する
4. consumer repo 側で動作確認する
5. `CHANGELOG.md` に反映する
6. `Pull Request` を作成する
