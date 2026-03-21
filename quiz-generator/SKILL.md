---
name: quiz-generator
description: ドキュメントから段階的学習用クイズセットを自動生成。セクション進行に応じて難度が段階的に上昇する複数学習パスを構成。JSON形式で出力対応。
license: MIT
---

# Quiz Generator（汎用化版）

## 概要

**プロジェクト配下のドキュメント**を対話的なクイズセットに自動変換するスキルです。

> **参考資料**
> - 📋 [データフォーマット仕様書](./DATA_FORMAT_SPECIFICATION.md) - 出力データの詳細仕様
> - ✅ [JSON スキーマ定義](./schemas/) - 自動バリデーション用のスキーマ（question-schema.json, question-set-schema.json, quizset-metadata-schema.json）

| 特徴 | 説明 |
|------|------|
| ✅ **自動生成** | ドキュメント構造を解析し、シリーズとクイズセットを自動生成 |
| ✅ **単一管理** | すべてのクイズを `tutorial/` に一元管理 |
| ✅ **段階的学習** | beginner → intermediate → advanced で難度を段階化 |
| ✅ **JSON出力** | 標準化されたJSON形式で出力対応 |
| ✅ **拡張性** | 新規セクション追加時も自動的に対応 |

---

## クイックスタート

### 🚀 対話型オートメーション（推奨）

分析→自動判断→生成→検証を **ユーザー入力なしで自動実行**：

```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "progressive"
output_format: "json"
```

**特徴：**
- ✅ 4ステップを全自動で実行
- ✅ ドキュメント構造から自動判断してセクション構成を決定
- ✅ 段階的難度を自動適用
- ✅ 生成結果を自動検証
- ✅ ユーザーの判断・入力は不要

**結果：**
```
tutorial/github-copilot-skills-tutorial/
├── quizSets.json                ← SPA Quiz App 用メタデータインデックス
├── metadata.json                ← シリーズ全体のメタデータ
├── fundamentals.json            ← Section 1（15問）
├── basics.json                  ← Section 2（12問）
├── comparison.json              ← Section 3（12問）
├── implementation.json          ← Section 4（12問）
├── advanced.json                ← Section 5（12問）
├── advanced-topics.json         ← Section 6（12問）
├── VALIDATION_REPORT.md         ← 品質検証レポート
└── .analysis.json               ← 分析結果（参照用）
```

**データフォーマット準拠：** すべてのファイルは [JSON スキーマ](./schemas/) に準拠し、SPA Quiz App で直接利用可能です。

### 📊 段階的実行（カスタマイズ）

各ステップで確認・調整しながら実行：

| Step | action | 役割 |
|------|--------|------|
| 1️⃣ | `analyze` | ドキュメント構造を分析、セクション自動検出 |
| 2️⃣ | `configure` | セクション順序・名前を手動調整（オプション） |
| 3️⃣ | `generate` | 確定構成でクイズを生成 |
| 4️⃣ | `validate` | 生成品質を検証（オプション） |

詳細は「[段階的実行フロー](#段階的実行フロー)」を参照してください。

---

## パラメータ仕様

### 対話型オートメーション（action: "auto-flow"）

**4ステップを自動で実行（ユーザー入力不要）**

**データフォーマット準拠:** 出力は [DATA_FORMAT_SPECIFICATION.md](./DATA_FORMAT_SPECIFICATION.md) に完全準拠し、SPA Quiz App との統合を確保します。

| パラメータ | 必須 | デフォルト | 説明 |
|----------|------|----------|------|
| `action` | ✅ | - | `"auto-flow"` に固定 |
| `doc_path` | ✅ | - | ドキュメントフォルダ（例: `"docs"`) |
| `target_audience` | | `"progressive"` | 難度対象: `"beginner"` / `"intermediate"` / `"advanced"` / `"progressive"` |
| `difficulty_distribution` | | `"balanced"` | 難度配分: `"balanced"` / `"beginner_focused"` / `"advanced_focused"` |
| `output_format` | | `"json"` | 出力形式: JSON のみ（データフォーマット仕様準拠） |
| `include_explanation` | | `true` | 各問に日本語の詳細解説を含める |
| `auto_section_filter` | | `true` | ドキュメント数が少ないセクションを自動除外 |
| `min_docs_per_section` | | `1` | セクション保持の最小ドキュメント数 |
| `generate_validation_report` | | `true` | 生成完了後に検証レポート（VALIDATION_REPORT.md）を生成 |
| `verbose` | | `false` | 実行ログを詳細出力（トラブルシューティング用） |

#### 📋 target_audience の選択フロー

**どの難度を選ぶ？**

```
┌─────────────────────────────────────────────┐
│ 学習者のターゲット層は？                     │
└─────────────────────────────────────────────┘
         ├─→ 初心者のみ
         │    → target_audience: "beginner"
         │
         ├─→ 経験者のみ  
         │    → target_audience: "advanced"
         │
         └─→ 初心者～経験者（段階的）★推奨
              → target_audience: "progressive"
```

**各値の選択基準：**

| 値 | 難度配分 | 推奨シーン | 進行度合 |
|----|---------|----------|----------|
| `beginner` | 80% beginner, 15% intermediate, 5% advanced | 初心者対象のコース | 全セクション同じ |
| `intermediate` | 30% beginner, 60% intermediate, 10% advanced | 基本を学んだ学習者 | 全セクション同じ |
| `advanced` | 10% beginner, 30% intermediate, 60% advanced | 専門知識が必要な場面 | 全セクション同じ |
| `progressive` | Section 1: 80% beginner→後半：50% advanced | 初心者から段階的に上達 | **セクション進行で自動上昇** ★推奨 |

**重要：** `progressive` を選んだ場合、セクション番号が進むにつれて難度が自動的に上昇します。後から変更は困難なため、初期選択時に十分検討してください。

**実行例：**
```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "progressive"  # ← 段階的難度（推奨）
output_format: "json"
auto_section_filter: true
min_docs_per_section: 1
```

**実行フロー：**
```
ドキュメント分析
    ↓
自動判断（セクション最適化）
    ↓
クイズセット生成
    ↓
品質検証
    ↓
完了
```

---

### ワンコマンド実行（action: "generate"）

| パラメータ | 必須 | デフォルト | 説明 |
|----------|------|----------|------|
| `action` | ✅ | - | `"generate"` に固定 |
| `doc_path` | ✅ | - | ドキュメントフォルダ（例: `"docs"`) |
| `output_format` | | `"json"` | 出力形式: JSON のみ（固定値） |
| `target_audience` | | `"intermediate"` | 難度対象: `"beginner"` / `"intermediate"` / `"advanced"` / `"progressive"` |
| `difficulty_distribution` | | `"balanced"` | 難度配分: `"balanced"` / `"beginner_focused"` / `"advanced_focused"` |
| `question_count` | | `"auto"` | 全体の問題数（`"auto"` で自動計算） |
| `include_explanation` | | `true` | 各問の解説を含める |

### 段階的実行時

#### Step 1: analyze

```yaml
action: "analyze"
doc_path: "docs"
```

**出力:** `tutorial/.analysis.json`

#### Step 2: configure

```yaml
action: "configure"
analysisFile: "tutorial/.analysis.json"
adjustments:
  seriesName: "修正後のシリーズ名"
  sections:
    - id: "fundamentals"
      name: "修正後のセクション名"
      order: 1
      enabled: true
```

**出力:** `tutorial/.series-config.json`

#### Step 3: generate

```yaml
action: "generate"
configFile: "tutorial/.series-config.json"
target_audience: "progressive"  # ← 段階的難度設定
difficulty_distribution: "balanced"
output_format: "json"
```

**出力:** 各セクションの `quiz.json` と `metadata.json`

#### Step 4: validate

```yaml
action: "validate"
outputDir: "tutorial"
```

**出力:** `tutorial/{シリーズID}/VALIDATION_REPORT.md`

### target_audience の難度設定

| 値 | 説明 | 使用シーン |
|----|------|----------|
| `"beginner"` | 初級者向け | 初心者対象のコース |
| `"intermediate"` | 中級者向け | 基本を学んだ学習者 |
| `"advanced"` | 上級者向け | 専門知識が必要な場面 |
| `"progressive"` | **段階的** | beginnerから徐々にadvancedへ（推奨） |

**「progressive」で段階的難度設定：**
```
Section 1: 80% beginner,    20% intermediate
Section 2: 30% beginner,    60% intermediate,  10% advanced
Section 3: 10% intermediate, 70% advanced,     20% expert
...
```

---

## 対話型オートメーション（auto-flow）の自動判断ロジック

`action: "auto-flow"` 実行時、スキルは以下の基準で自動的に判断しながら実行します。ユーザーの入力は一切不要です。

### 1️⃣ セクション検出 & 最適化

**自動判断基準：**

| 判定項目 | 判定基準 | 判定内容 |
|---------|---------|---------|
| **セクション構成** | ドキュメント階層 | フォルダ構造から自動検出 |
| **セクション順序** | フォルダプレフィックス数字 | `01-xxx`, `02-xxx` で自動ソート |
| **セクション有効/無効** | `min_docs_per_section` | ドキュメント数が閾値未満なら自動除外 |
| **セクション名** | フォルダ名 / README.md H1 | 英数字を日本語に自動翻訳（LLM利用） |
| **ID生成** | ケバブケース化 | 自動生成・重複チェック |

**例：**
```
docs/
├── 00-fundamentals/          → セクション有効（2ファイル）
│   ├── skill-format-overview.md
│   └── README.md
├── 01-basics/                → セクション有効（3ファイル）
│   ├── introduction.md
│   ├── vs-traditional.md
│   └── how-skills-work.md
├── 05-advanced-topics/       → セクション有効（3ファイル）
│   ├── composite-skills.md
│   ├── api-integration.md
│   └── best-practices.md
└── extras/                   → セクション除外（1ファイル < 最小2）
    └── appendix.md
```

### 2️⃣ 難度分布の自動決定

**自動判断ロジック：**

- **target_audience: "progressive"** の場合（推奨）
  ```
  Section 1 (1番目):   80% beginner,    20% intermediate
  Section 2 (2番目):   50% beginner,    40% intermediate,  10% advanced
  Section 3 (3番目):   20% beginner,    50% intermediate,  30% advanced
  Section N (最後):    10% intermediate, 50% advanced,      40% expert
  ```
  → セクション進行に従い、難度が段階的に上昇

- **target_audience: "beginner"** の場合
  ```
  全セクション: 80% beginner, 15% intermediate, 5% advanced
  ```

- **target_audience: "intermediate"** の場合  
  ```
  全セクション: 30% beginner, 60% intermediate, 10% advanced
  ```

- **target_audience: "advanced"** の場合
  ```
  全セクション: 10% beginner, 30% intermediate, 60% advanced
  ```

### 3️⃣ クイズ数の自動計算

**自動判断ロジック：**

```
質問総数 = セクション数 × 21問（1セクションあたり）
           + 調整（ドキュメント数が特に多い場合）

例：
- セクション 3個 → 63問（21 × 3）
- セクション 6個 → 126問（21 × 6）
- セクション 10個 → 210問+α
```

### 4️⃣ 品質検証の自動実行

生成完了時に自動的に以下を検証：

- ✅ JSON スキーマ準拠性
- ✅ セクションごとの問題数
- ✅ 難度分布が設定値に準拠
- ✅ ID形式（ケバブケース）の正当性
- ✅ 必須フィールドの存在
- ✅ メタデータの整合性

**検証レポート：** `tutorial/{シリーズID}/VALIDATION_REPORT.md` に自動生成

---

## 段階的実行フロー

複数ステップに分けて実行することで、各段階でユーザーが検証・調整可能です。

### Step 0: 実行前チェックリスト（推奨）

**実行を開始する前に、以下を確認してください。このステップを実施することで、多くの潜在的な問題を事前に防止できます。**

#### ✅ ドキュメント準備確認

- [ ] `docs/` フォルダが存在するか
- [ ] 各セクションフォルダに最低 1 個のドキュメント（`.md`）があるか
- [ ] すべてのドキュメントに H1 見出し（`# タイトル`）が存在するか
- [ ] フォルダ構造が `01-section/`, `02-section/` のように番号プレフィックスで始まっているか（推奨）

**確認コマンド例（PowerShell）：**
```powershell
# ドキュメント数をカウント
Get-ChildItem docs -Recurse -Filter "*.md" | Measure-Object

# セクションごとのドキュメント数
Get-ChildItem docs -Directory | ForEach-Object { 
  Write-Host "$($_.Name): $(@(Get-ChildItem $_.FullName -Filter '*.md').Count) files" 
}
```

#### ✅ パラメータ検証

- [ ] `doc_path` が正確か（例：`"docs"`）
- [ ] `target_audience` が有効値か（`beginner|intermediate|advanced|progressive`）
- [ ] 段階実行の場合、JSON ファイルパスが正確か
- [ ] `output_format` が有効値か（`json|markdown|both`）

#### ✅ 出力ディレクトリ確認

- [ ] `tutorial/` などの出力先フォルダへの書き込み権限があるか
- [ ] ディスク容量は十分か（大規模プロジェクトの場合、数MB必要）

**これらがすべて確認できたら、Step 1 に進みます。**

---

### Step 1: コンテンツ分析

ドキュメント構造を解析し、シリーズ構成の候補を生成します。

**実行パラメータ：**
```yaml
action: "analyze"
doc_path: "docs"
```

**出力ファイル：** `tutorial/.analysis.json`

**確認項目：**
- ✅ シリーズID・名前が正確か
- ✅ セクション分類が適切か
- ✅ セクション名は分かりやすいか
- ✅ ドキュメント数が期待値と一致しているか

**確認後の選択肢：**
- ✅ 「次へ」→ Step 2 に進む
- 📝 「調整」→ `.analysis.json` を手動編集後 Step 2 に進む

---

### Step 2: シリーズ構成確定（スキップ可能）

Step 1 の分析結果に対して、セクション順序や名前を手動で調整します。

#### 実行判定フロー

**このステップを実施するべきか？**

```
¿ ドキュメント構造
  │
  ├─→ [YES] シンプル（30個以下のドキュメント）
  │         かつセクション名が大意を伝えている
  │         → Step 2 をスキップ、Step 3 へ直進
  │
  ├─→ [YES] セクション名や順序に疑問がある
  │         → Step 2 を実施して調整
  │
  └─→ [YES] 特定セクションをコースから除外したい
            → Step 2 を実施（必須）
```

**判定基準：**

| 判定項目 | Step 2 実施推奨 | 理由 |
|---------|-------------|------|
| **セクション名が不明確** | ✅ YES | UI 表示のため、分かりやすい名前が必須 |
| **セクション順序を変更したい** | ✅ YES | 学習フローを最適化 |
| **特定セクションを除外したい** | 🔴 必須 | enabled: false で除外指定 |
| **ドキュメント構造がシンプル** | ❌ NO | 自動判断で十分正確 |
| **セクション名が十分な場合** | ❌ NO | 時間短縮のためスキップ推奨 |

**実行パラメータ：**
```yaml
action: "configure"
analysisFile: "tutorial/.analysis.json"
adjustments:
  seriesName: "修正後のシリーズ名"
  sections:
    - id: "fundamentals"
      name: "修正後のセクション名"
      order: 1
      enabled: true
    - id: "advanced"
      name: "上級トピック"
      order: 5
      enabled: false    # ← 特定セクションを除外する場合
```

**出力ファイル：** `tutorial/.series-config.json`

**編集可能な項目：**
- セクション順序の変更
- セクション名の修正
- セクションの有効/無効切り替え
- シリーズ名の変更

---

### Step 3: クイズセット生成

確定した構成に基づいて、各セクションのクイズを生成します。生成されたデータは [JSON スキーマ](./schemas/) と [データフォーマット仕様](./DATA_FORMAT_SPECIFICATION.md) に準拠します。

**実行パラメータ（段階的難度設定例）：**
```yaml
action: "generate"
configFile: "tutorial/.series-config.json"
target_audience: "progressive"      # ← beginnerから徐々にadvancedへ
difficulty_distribution: "balanced"
output_format: "json"
include_explanation: true
```

**出力ファイル構成：**

```
tutorial/github-copilot-skills-tutorial/
├── quizSets.json                    ← SPA Quiz App 用メタデータインデックス（必須）
├── metadata.json                    ← シリーズ全体のメタデータ
├── fundamentals.json                ← Section 1（15問，難度：80% beginner）
├── basics.json                      ← Section 2（12問，難度：50% beginner）
├── comparison.json                  ← Section 3（12問，難度：20% beginner）
├── implementation.json              ← Section 4（12問，難度：10% beginner）
├── advanced.json                    ← Section 5（12問，難度：0% beginner）
├── advanced-topics.json             ← Section 6（12問，難度：expert混在）
├── VALIDATION_REPORT.md             ← 品質検証レポート
└── .analysis.json                   ← 分析結果（参照用）
```

**生成内容の仕様準拠性：**
- ✅ 出力ファイル数：セクション数 + メタデータ 1 + インデックス 1
- ✅ 問題形式：`quizSets.json` 仕様（id, name, description, category, icon, questionCount など）
- ✅ 質問形式：[データフォーマット仕様](./DATA_FORMAT_SPECIFICATION.md) 準拠
  - `questions[]` 配列
  - `id`, `question`, `options[]`（4つ固定）, `correctAnswer` (A/B/C/D), `explanation`
- ✅ 総問題数：約 71 問（21問/セクション × 段階的難度適用）
- ✅ 難度分布：progressive 設定で自動段階化
- ✅ 各問に日本語の詳細な解説付き
- ✅ JSON スキーマバージョン 1.0.0 準拠

---

### Step 4: 検証（オプション）

すべてのクイズセットが正しく生成されたか品質を検証します。**この段階は省略可能ですが、本番運用時には推奨されます。**

**実行パラメータ：**
```yaml
action: "validate"
outputDir: "tutorial"
```

**出力ファイル：** `tutorial/{シリーズID}/VALIDATION_REPORT.md`

**検証内容（データフォーマット仕様準拠確認）：**

#### メタデータ検証
- ✅ `quizSets.json` のスキーマ準拠性
- ✅ 各セット：`id`, `name`, `description`, `category`, `icon`, `questionCount` 等の必須フィールド
- ✅ `dataPath` が指定ファイルに対応
- ✅ `parentId`, `group`, `level`, `order` の階層構造整合性
- ✅ `id` がケバブケース形式（例：`github-copilot-skills-fundamentals`）

#### クイズセット検証
- ✅ 各 `{section}.json` の `questions[]` 配列構造
- ✅ 各質問の必須フィールド：`id`, `question`, `options[]` (4個), `correctAnswer` (A/B/C/D), `explanation`
- ✅ オプション形式：`{id: "A", text: "..."}`
- ✅ 回答の一意性（正解は 1 つのみ）
- ✅ 難度分布期待値への準拠（progressive 時の上昇幅）

#### 統合検証
- ✅ セクション数とメタデータの一致
- ✅ 総問題数の計算正確性
- ✅ ファイルの完全性（すべてのセクションが出力されているか）
- ✅ ドキュメントと出力の対応関係

**検証結果レポート例：**
```
✅ 検証完了: このクイズセットは品質要件を満たしています

総合スコア: 91/100（優秀）
├── 難度進行: 95/100 ✅
├── 内容網羅性: 92/100 ✅
├── 問題質: 88/100 ✅
└── データフォーマット準拠: 100/100 ✅

本クイズセットの使用開始を承認します
```

---

## 処理フロー図

### 対話型オートメーション（auto-flow）

```
┌──────────────────────────────────────────────────────┐
│   action: "auto-flow"                               │
│   doc_path: "docs"                                  │
│   target_audience: "progressive"                    │
│   output_format: "json"                             │
└──────────────────────────────────────────────────────┘
          ↓
┌──────────────────────────────────────────────────────┐
│ [内部Step 1] ドキュメント構造を自動解析              │
│ ・フォルダ検出（01-xxx, 02-xxx パターン）            │
│ ・ドキュメント数カウント                             │
│ ・セクション順序決定（プレフィックス数字基準）       │
└──────────────────────────────────────────────────────┘
          ↓
┌──────────────────────────────────────────────────────┐
│ [内部Step 2] セクション自動最適化                    │
│ ・min_docs_per_section 未満は自動除外               │
│ ・セクション名を自動生成（LLM利用）                  │
│ ・ID をケバブケース化                                │
│ ・メタデータ構造を構築（親・子関係）                 │
│ ★ ユーザー判断なし                                  │
└──────────────────────────────────────────────────────┘
          ↓
┌──────────────────────────────────────────────────────┐
│ [内部Step 3] クイズセット生成                        │
│ ・難度分布を自動決定（progressive対応）             │
│ ・各セクション 12～15 問生成                         │
│ ・question 形式：id, question, options[], answer    │
│ ・quizSets.json メタデータを生成                     │
│ ✓ データフォーマット仕様準拠                         │
└──────────────────────────────────────────────────────┘
          ↓
┌──────────────────────────────────────────────────────┐
│ [内部Step 4] 生成品質を自動検証                      │
│ ・JSON スキーマバージョン 1.0.0 準拠確認            │
│ ・難度分布検証（期待値に対する準拠度）               │
│ ・メタデータ整合性チェック（id, parentId等）        │
│ ・必須フィールド検証                                 │
│ ✓ 検証レポート（VALIDATION_REPORT.md）自動生成       │
└──────────────────────────────────────────────────────┘
          ↓
┌──────────────────────────────────────────────────────┐
│ 出力ファイル生成（完全準拠）                        │
│ tutorial/{シリーズID}/                              │
│ ├── quizSets.json          ← SPA 用インデックス    │
│ ├── metadata.json          ← シリーズ全体メタ       │
│ ├── {section}.json × N     ← 各セクション問題      │
│ ├── VALIDATION_REPORT.md   ← 品質検証レポート      │
│ └── .analysis.json         ← 分析結果参照用    │
└──────────────────────────────────────────────────────┘
```

**実行時間目安：** 3～5 秒（セクション数により変動）  
**データ準拠：** [データフォーマット仕様 v1.0.0](./DATA_FORMAT_SPECIFICATION.md)

---

### 従来の段階的実行フロー

```
ドキュメントを自動解析
        ↓
   [Step 1: analyze]
  フォルダ構造検出 → セクション自動分類 → ID・名前自動生成
        ↓
  [Step 2: configure] ← ユーザーが手動調整（オプション）
 セクション順序・名前を修正
        ↓
  [Step 3: generate]
各セクションからクイズを生成 → 難度を段階的に適用 → メタデータ統合
        ↓
tutorial/{シリーズID}/
├── quizSets.json               ← SPA Quiz App 用メタデータインデックス
├── metadata.json
├── fundamentals.json           ← 各セクションを個別 JSON ファイルで出力
├── basics.json
├── comparison.json
├── implementation.json
├── advanced.json
├── advanced-topics.json
└── VALIDATION_REPORT.md        ← 品質レポート
        ↓
  [Step 4: validate] ← オプション（品質確認）
  JSON スキーマ検証 → 難度分布確認 → レポート生成
```

### ID 生成ルール

| ドキュメント | ID自動生成 | 例 |
|-----------|----------|-----|
| `01-introduction/` | `introduction` | フォルダプレフィックス数字削除 |
| `setup-guide/` | `setup-guide` | ケバブケースで使用 |
| `README.md` の H1 | `タイトルをハイフン化` | \"Clean Architecture\" → `clean-architecture` |
| `02-section/01-file.md` | `file` | ファイル名のプレフィックス削除 |

---

## よくあるユースケース

---

### UC-1: 急いでいる（所要時間：3～5秒）

**パターン：** 分析→自動判断→生成→検証を完全自動実行

**推奨：** `auto-flow` を実行

```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "progressive"
output_format: "json"
```

**特徴：**
- ✅ 4ステップを自動で実行（ユーザー判断不要）
- ✅ ドキュメント構造から最適なセクション構成を自動決定
- ✅ セクション最適化：ドキュメント数が少ないセクションを自動除外
- ✅ 難度分布を自動設定（progressive対応）
- ✅ 生成結果を自動検証＋レポート生成

**実行時間：** 3～5秒

**出力例：**
```
tutorial/github-copilot-skills-tutorial/
├── quizSets.json                 ← SPA Quiz App 用メタデータインデックス
├── metadata.json                 ← シリーズメタデータ
├── fundamentals.json             (Section 1: 15問, ~初級)
├── basics.json                   (Section 2: 12問, 初→中級)
├── comparison.json               (Section 3: 12問, 中級)
├── implementation.json           (Section 4: 12問, 中→上級)
├── advanced.json                 (Section 5: 12問, 上級)
├── advanced-topics.json          (Section 6: 12問, 上級→エキスパート)
├── VALIDATION_REPORT.md          ← 自動生成品質レポート
└── README.md                     （オプション）
```
**データフォーマット準拠：** すべてのファイルが [DATA_FORMAT_SPECIFICATION.md](./DATA_FORMAT_SPECIFICATION.md) v1.0 に準拠

---

### UC-2: セクション名をカスタマイズしたい（所要時間：1～2分）

**パターン：** セクション名や順序を手動調整

**推奨：** 段階実行（Step 1→2→3）

**Step 1: 分析**
```yaml
action: "analyze"
doc_path: "docs"
```

**確認：** `.analysis.json` の結果をレビュー

**Step 2: セクションを調整**
```yaml
action: "configure"
analysisFile: "tutorial/.analysis.json"
adjustments:
  seriesName: "修正後のシリーズ名"
  sections:
    - id: "fundamentals"
      name: "修正後のセクション名"
      order: 1
      enabled: true
    - id: "advanced-topics"
      enabled: false    # ← 除外する場合
```

**Step 3: 生成**
```yaml
action: "generate"
configFile: "tutorial/.series-config.json"
target_audience: "progressive"
```

**実行時間：** 1～2分（調整内容による）

**出力：** UC-1 と同じ形式（`quizSets.json` + 6 x flat JSON files）

---

### UC-3: 初心者向けコースを作りたい（所要時間：5秒）

**パターン：** 初級向け難度設定 + 自動生成

**推奨：** `auto-flow` + `target_audience` パラメータ

```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "beginner"              # ← 初級向け固定
difficulty_distribution: "beginner_focused"
output_format: "json"
```

**特徴：**
- ✅ 全セクション同じ難度レベル（beginner優位）
- ✅ 難度分布：50% beginner, 40% intermediate, 10% advanced
- ✅ セクション進行による難度上昇なし（すべて初級向け）

**実行時間：** 5秒

---

### UC-4: 複数の学習パス（初級/上級）を作りたい（所要時間：10秒）

**パターン：** 異なる難度レベルで複数回実行

**推奨：** `auto-flow` を複数回実行

**実行 1 回目：初級向け**
```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "beginner"
output_format: "json"
```

**実行 2 回目：上級向け**
```yaml
action: "auto-flow"
doc_path: "docs"
target_audience: "advanced"
output_format: "json"
```

**出力結果：**
- 2 つの独立したクイズセット（難度が異なる）
- UI で学習者が難度を選択可能

---

### UC-5: 細かい品質チェックを実施したい（所要時間：2～3分）

**パターン：** 生成品質を詳細に検証

**推奨：** 段階実行（Step 1→3→4）

```yaml
# Step 1: 分析
action: "analyze"
doc_path: "docs"

# Step 3: 生成（Step 2 をスキップ）
action: "generate"
configFile: "tutorial/.series-config.json"
target_audience: "progressive"

# Step 4: 検証
action: "validate"
outputDir: "tutorial"
```

**出力：** `VALIDATION_REPORT.md` に詳細レポートを生成

```markdown
# Quiz Set Validation Report

## Summary
- Total Quiz Sets: 6
- Total Questions: 126
- Target Audience: progressive
- Difficulty Distribution: balanced

## Per-Section Details
- fundamentals: 21 questions (beginner 100%)
- basics: 21 questions (beginner 50%, intermediate 50%)
- ...

## Quality Checks
- ✅ All metadata is valid
- ✅ All question sets are valid
- ✅ ID format: kebab-case compliant
```

### メタデータファイル: quizSets.json

**ファイルパス：** `tutorial/{シリーズID}/quizSets.json`

**用途：** SPA Quiz App が直接読み込む統合メタデータインデックス

> **スキーマ**: [quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json) に準拠

```json
{
  "quizSets": [
    {
      "id": "github-copilot-skills-tutorial",
      "name": "GitHub Copilot Skills チュートリアル",
      "description": "基礎から実装、応用活用までを段階的に学ぶ総合学習パス",
      "category": "GitHub Copilot",
      "icon": "🚀",
      "questionCount": 71,
      "difficulty": "beginner to advanced",
      "dataPath": null,
      "parentId": null,
      "group": "github-copilot-skills-series",
      "level": 1,
      "order": 1
    },
    {
      "id": "github-copilot-skills-fundamentals",
      "name": "基礎：スキル形式の選択と実装",
      "description": "Agent Skillsの標準化、対応プラットフォーム、実装形式の選択",
      "questionCount": 15,
      "difficulty": "beginner",
      "dataPath": "github-copilot-skills-tutorial/fundamentals.json",
      "parentId": "github-copilot-skills-tutorial",
      "group": "github-copilot-skills-series",
      "level": 2,
      "order": 1
    },
    {
      "id": "github-copilot-skills-basics",
      "name": "基礎：スキルの基本概念と価値",
      "description": "スキルの定義、実装メリット、プラットフォーム統合",
      "questionCount": 12,
      "difficulty": "beginner to intermediate",
      "dataPath": "github-copilot-skills-tutorial/basics.json",
      "parentId": "github-copilot-skills-tutorial",
      "level": 2,
      "order": 2
    }
  ]
}
```

### メタデータファイル: metadata.json

**ファイルパス：** `tutorial/{シリーズID}/metadata.json`

**用途：** シリーズ全体の統計情報・管理メトデータ

> **スキーマ**: [quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json) に準拠

```json
{
  "series": {
    "id": "github-copilot-skills-tutorial",
    "name": "GitHub Copilot Skills チュートリアル",
    "level": 1,
    "parentId": null,
    "questionCount": 71,
    "childCount": 6
  },
  "quizSets": [
    {
      "id": "github-copilot-skills-fundamentals",
      "name": "基礎：スキル形式の選択と実装",
      "level": 2,
      "parentId": "github-copilot-skills-tutorial",
      "order": 1,
      "questionCount": 15,
      "difficulty": "beginner",
      "dataPath": "fundamentals.json"
    }
  ]
}
```

---

### クイズファイル: {section}.json

**ファイルパス：** `tutorial/{シリーズID}/{section}.json` (e.g., `fundamentals.json`, `basics.json`)

**用途：** 各セクションの問題データを格納

> **スキーマ**: [question-set-schema.json](./schemas/question-set-schema.json) に準拠  
> **個別問題**: [question-schema.json](./schemas/question-schema.json) に準拠

**ファイル一覧：**
- `fundamentals.json` - Section 1: 15問（基礎概念）
- `basics.json` - Section 2: 12問（基本実装）
- `comparison.json` - Section 3: 12問（比較・選択）
- `implementation.json` - Section 4: 12問（実装手法）
- `advanced.json` - Section 5: 12問（応用・チーム活用）
- `advanced-topics.json` - Section 6: 12問（高度な設計パターン）

**形式例（fundamentals.json）：**

```json
{
  "questions": [
    {
      "id": 1,
      "question": "GitHub Copilot Agent Skills の主な特徴は何ですか？",
      "options": [
        {
          "id": "A",
          "text": "Copilot の動作を自動化するスクリプト"
        },
        {
          "id": "B",
          "text": "特定ドメインの知識をプロンプト+ドキュメントで定義するもの"
        },
        {
          "id": "C",
          "text": "Copilot の新機能追加パッチ"
        },
        {
          "id": "D",
          "text": "ユーザーの VS Code 拡張機能の集合"
        }
      ],
      "correctAnswer": "B",
      "explanation": "Agent Skills は、プロンプトやドキュメントを組み合わせて、特定分野の知識を Copilot に教えるための標準化フォーマットです。これにより、チーム全体で知識を共有し、再利用可能な学習リソースを作成できます。"
    },
    {
      "id": 2,
      "question": "問題文...",
      "options": [
        {"id": "A", "text": "..."},
        {"id": "B", "text": "..."},
        {"id": "C", "text": "..."},
        {"id": "D", "text": "..."}
      ],
      "correctAnswer": "A",
      "explanation": "..."
    }
  ]
}
```

**フィールド説明**:
- `questions[].id` - セクション内での問題番号（連番 1～15）
- `questions[].correctAnswer` - **正解（A/B/C/D のいずれか 1つのみ 固定）** ⚠️ 複数選択非対応
- `options[].id` - 選択肢の識別子（A/B/C/D 4つ固定）
- `questions[].explanation` - 解説（検証時のみ自動生成、設定で有効化可能）

⚠️ **重要：複数選択問題非対応** - クイズセット実行アプリが複数選択に対応していないため、生成ロジックは必ず**単一選択問題のみを生成**します。複数選択問題の生成リクエストは無視されます。

詳細は [データフォーマット仕様書](./DATA_FORMAT_SPECIFICATION.md) を参照してください。

---

### 検証レポート: VALIDATION_REPORT.md

**ファイルパス：** `tutorial/{シリーズID}/VALIDATION_REPORT.md`

**用途：** Step 4 で生成される品質チェックレポート

```markdown
# Quiz Set Validation Report

## Summary
- Total Quiz Sets: 6
- Total Questions: 126
- Generation Date: 2026-03-08T10:00:00Z
- Target Audience: progressive
- Difficulty Distribution: balanced

## Per-Section Details
- fundamentals: 21 questions
  - Difficulty: beginner (100%)
  - Schema: ✅ Valid
  
- basics: 21 questions
  - Difficulty: beginner (50%), intermediate (50%)
  - Schema: ✅ Valid

- ... (other sections)

## Quality Checks
- ✅ All metadata is valid (quizset-metadata-schema.json)
- ✅ All question sets are valid (question-set-schema.json)
- ✅ All individual questions are valid (question-schema.json)
- ✅ ID format: kebab-case compliant
- ✅ Required fields present in all objects
- ✅ Parent-child relationships valid
```

---

## メタデータ一元管理の設計

> **根拠**: [データフォーマット仕様書](./DATA_FORMAT_SPECIFICATION.md) で定義されるメタデータ一元管理設計

**構造の利点：**

1. **関心の分離** - メタデータ（表示・管理用）と問題データ（実行用）を分離
   - SPA は `quizSets.json` から全体構造と各セクションの参照を取得
   - 学習アプリは各 `*.json`（fundamentals.json 等）から問題データを取得

2. **保守性** - メタデータ修正時にクイズJSONを編集不要
   - セクション名の変更 → `quizSets.json` と `metadata.json` のみ更新
   - 問題データは変更なし

3. **拡張性** - 新しいクイズセット追加時は `quizSets.json` に追記するだけ
   - 新セクション追加 → `quizSets.json` の `quizSets` に 1 項目追加
   - `{section-name}.json` ファイルを作成（新しいセクション用）

4. **UI連携** - SPAフロントエンドは`quizSets.json`から直接メタデータを読み込み
   - ナビゲーション構築
   - セクション進捗管理
   - 統計情報の表示
   - ナビゲーション構築
   - セクション進捗管理
   - 統計情報の表示

---

## データ品質基準

### 出題品質

- ✅ **コンテンツ正確性** - ドキュメント内容を正確に反映
- ✅ **実用性** - ドキュメント内の具体例・図表を参照した問題
- ✅ **理解度測定** - 実践的で理解度を確認できる問題設計
- ✅ **思考性** - 誤答選択肢が紛らわしく、思考を深める設計

### データ完全性

- ✅ **ID形式** - ケバブケース準拠 ([quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json))
- ✅ **選択肢数** - 正確に 4 つ（A/B/C/D）が必須 ([question-schema.json](./schemas/question-schema.json))
- ✅ **正答形式** - 複数選択非対応（A/B/C/D のいずれか **1つのみ**）
- ✅ **難度値** - 有効な難度のみ（`beginner`, `intermediate`, `advanced`）
- ✅ **階層構造** - level は 1（トップレベル）または 2（子セット）
- ✅ **参照整合性** - 親セット・子セット関係が正しく定義される

### 難度分布パターン

| パターン | Beginner | Intermediate | Advanced |
|---------|----------|--------------|----------|
| `balanced` | 15% | 70% | 15% |
| `beginner_focused` | 50% | 40% | 10% |
| `advanced_focused` | 10% | 40% | 50% |

---

### JSON スキーマ検証

すべての生成ファイルは、以下のスキーマに対して自動検証されます：

| ファイル | スキーマ | 検証内容 |
|---------|---------|----------|
| `quizSets.json` | [quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json) | 階層構造、ID形式、難度値、parent-child関係 |
| `metadata.json` | [quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json) | シリーズ・セクション関係、questionCount |
| `{section}.json` | [question-set-schema.json](./schemas/question-set-schema.json) | 問題配列の構造、各問題の完全性 |
| 個別問題 | [question-schema.json](./schemas/question-schema.json) | 選択肢数（4つ必須）、ID形式（A/B/C/D）、正答の妥当性 |

詳細は [データフォーマット仕様書](./DATA_FORMAT_SPECIFICATION.md) を参照してください。

---

## トラブルシューティング

### Q: ドキュメント構造が複雑で、セクション分類が正確でない

**A:** Step 1（analyze）の結果を確認し、Step 2（configure）で手動調整してください

```yaml
action: "configure"
analysisFile: "tutorial/.analysis.json"
adjustments:
  sections:
    # フォルダ順を変更
    - id: "advanced-topics"
      order: 3
    - id: "basics"
      order: 4
```

---

### Q: 特定セクションのみ生成したい

**A:** Step 2 で `enabled: false` に設定してください

```yaml
action: "configure"
analysisFile: "tutorial/.analysis.json"
adjustments:
  sections:
    - id: "fundamentals"
      enabled: true
    - id: "advanced"
      enabled: false    # ← このセクションをスキップ
```

---

### Q: 生成された問題の品質が低い、または内容が不正確

**A:** 以下を確認してください：

1. **ドキュメント品質**：タイトル、見出しが明確か
2. **形式**：H1/H2 の階層構造が適切か
3. **内容**：具体例や説明が十分か

改善後、再度実行してください。

---

### Q: 難度分布が期待と異なる

**A:** `difficulty_distribution` パラメータを調整してください

```yaml
action: "generate"
configFile: "tutorial/.series-config.json"
target_audience: "progressive"
difficulty_distribution: "beginner_focused"  # ← 初級向けに変更
```

---

## 参考資料

| 資料 | 用途 |
|----|----|
| [データフォーマット仕様書](./DATA_FORMAT_SPECIFICATION.md) | クイズデータの詳細仕様、ネーミング規則、FAQ など |
| [question-schema.json](./schemas/question-schema.json) | 個別問題の JSON Schema (Draft-07) |
| [question-set-schema.json](./schemas/question-set-schema.json) | クイズセット全体の JSON Schema |
| [quizset-metadata-schema.json](./schemas/quizset-metadata-schema.json) | メタデータの JSON Schema |

---

## 活用パターン

### 親シリーズの活用
- 学習ロードマップ表示
- 全体的な理解度測定
- シリーズ進捗管理

### 子クイズセットの活用
- セクション単位での理解確認
- 段階的な難度上昇対応
- セクション別の弱点分析

### メタデータの活用
- UI から全セクション一覧を表示
- ドキュメント品質測定
- 学習カバレッジ検証
- ドキュメント更新による影響度追跡