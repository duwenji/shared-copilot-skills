# spa-quiz-app ドキュメント クイズセット生成タスク

## 目的
docs/ フォルダの以下5つのドキュメント全体をクイズセット化し、src/data/ に JSON形式で保存する。

## 対象ドキュメント
1. **README.md** - GitHub Pages と全体概要
2. **QUICKSTART.md** - セットアップと基本操作
3. **ARCHITECTURE.md** - アーキテクチャと技術スタック
4. **DEPLOYMENT.md** - デプロイ手順と設定
5. **TROUBLESHOOTING.md** - トラブルシューティング

## 出力仕様

### メタデータ（quizSets.json に追加）
```json
{
  "id": "spa-quiz-app-docs",
  "name": "spa-quiz-app ドキュメント",
  "description": "spa-quiz-appのセットアップ、アーキテクチャ、デプロイ、トラブルシューティングに関するクイズ",
  "category": "技術",
  "icon": "📚",
  "questionCount": 30,
  "difficulty": "intermediate",
  "dataPath": "spa-quiz-app/spa-quiz-app-docs.json",
  "parentId": null,
  "group": null,
  "level": 1,
  "order": 1
}
```

#### フィールド説明
- **id**: クイズセットの一意識別子
- **name**: クイズセット の表示名
- **description**: クイズセットの説明
- **category**: カテゴリ分類
- **icon**: 絵文字アイコン
- **questionCount**: 問題数
- **difficulty**: 難度レベル（beginner/intermediate/advanced）
- **dataPath**: クイズデータファイルの相対パス
- **parentId**: シリーズの親セットID（独立したセットの場合は`null`、シリーズの子の場合は親のID）
- **group**: シリーズグループの識別子（シリーズに属さない場合は`null`）
- **level**: 階層レベル（1=独立または親セット、2=シリーズの子セット）
- **order**: 表示順序（同一グループ内での並び順）

### クイズデータファイル構造
`src/data/spa-quiz-app/spa-quiz-app-docs.json`

```json
{
  "questions": [
    {
      "id": "1",
      "question": "質問文",
      "options": [
        {"id": "A", "text": "選択肢A"},
        {"id": "B", "text": "選択肢B"},
        {"id": "C", "text": "選択肢C"},
        {"id": "D", "text": "選択肢D"}
      ],
      "correctAnswer": "A",
      "explanation": "解説文（複数行対応）",
      "difficulty": "beginner|intermediate|advanced"
    }
  ]
}
```

## クイズ抽出ガイドライン

### README.md から（3-4問）
- GitHub Pages の定義と特徴
- デプロイの4段階フロー（ビルド→gh-pages→GitHub Pages→公開）
- 公開URL

### QUICKSTART.md から（4-5問）
- npm install の目的
- 開発サーバー起動コマンド
- ビルド・デプロイの基本フロー
- アクセスURL

### ARCHITECTURE.md から（8-10問）
- Vite とは何か、なぜ使うのか
- base 設定の開発/本番での値
- React + TypeScript ファイル構成
- useQuiz フック の機能
- quizSets.json と各データファイルの役割
- TypeScript設定での重要設定
- ビルド出力の構造
- NODE_ENV による動的パス切り替え

### DEPLOYMENT.md から（6-8問）
- GitHub Pages の前提条件
- リポジトリ名の形式
- Pages 設定で確認すべき項目
- ビルド前に確認すべきファイル配置
- デプロイコマンド実行後のメッセージ
- vite.config.ts の base 設定の意味
- npm run preview の目的

### TROUBLESHOOTING.md から（6-8問）
- TypeScript エラー「Property 'env' does not exist」の解決方法
- Module not found エラーの原因と解決
- GitHub Pages が反映されない場合の対応
- ローカル開発での 404 エラーの原因
- gh-pages デプロイ失敗の確認ステップ
- クイズデータが読み込めない場合の確認項目

## 難度の分け方
- **beginner** (15%)：用語の意味、基本コマンド、URL
- **intermediate** (70%)：ファイル構成、設定の意味、トラブル対応
- **advanced** (15%)：複合的なシステム理解、エラー解析

## 品質チェック
- [ ] 各選択肢が同程度の長さ（極端に長いものがない）
- [ ] 誤答選択肢が正答と紛らわしい
- [ ] 解説がドキュメント内容と一致
- [ ] 難度分布が適切（easy:intermediate:hard = 15:70:15）
- [ ] 全30問で各ドキュメントが均等に網羅されている
- [ ] relatedDocument フィールドが正確に設定されている

## 調査・提案依頼
以下のことを確認してクイズを生成してください：
1. ドキュメント内容を正確に反映したクイズ設問
2. ドキュメントそのものの矛盾や曖昧な点を指摘（あれば）
3. 生成したクイズセットを以下のファイル形式で提示：
   - quizSets.json 追加分
   - spa-quiz-app-docs.json（完全なクイズセット）
