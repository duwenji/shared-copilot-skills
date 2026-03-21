# クリーンアーキテクチャ教材用 クイズセット生成プロンプト

このドキュメントは、`extras/clean-architecture/` ディレクトリの各教材ファイルから、クイズセットを生成するためのプロンプトを提供します。

---

## プロンプト使用方法

各プロンプトの末尾にある「**生成指示**」セクションをコピーし、LLMに提供してください。最終的に、JSON形式のクイズセットが生成されます。

出力形式は、本プロジェクトの既存クイズセット（`src/data/quizSets.json`）に合わせてください。

---

## STEP 1: 理論基盤

**ファイル**: `clean-architecture-step1-foundation.md`

**学習テーマ**: クリーンアーキテクチャの基本概念、提唱者、理論的背景、SOLID原則との関連性

**生成指示**:

```
以下のクリーンアーキテクチャ基礎教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- クリーンアーキテクチャとは何か（フレームワーク非依存、テスト容易性、保守性）
- Robert C. Martin による提唱背景と歴史
- アーキテクチャの重要性（建物の例）
- 4つの層構造の基本
- SOLID原則との関連性

【クイズ要件】
1. 難易度: 初級（初学者向け）
2. 問題数: 10問
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON（以下の構造）
5. 出力ファイル名: step1-foundation.json
6. 保存先: src/data/clean-architecture/

【JSON形式】
{
  "id": "clean-architecture-step1",
  "title": "クリーンアーキテクチャ基礎 - STEP 1: 理論基盤",
  "description": "クリーンアーキテクチャの基本概念と理論的背景を学ぶクイズ",
  "difficulty": "初級",
  "questions": [
    {
      "text": "クイズの問題文",
      "options": [
        { "text": "正解選択肢1" },
        { "text": "不正解選択肢2" },
        { "text": "不正解選択肢3" },
        { "text": "不正解選択肢4" }
      ],
      "correctOptionIndex": 0,
      "explanation": "解説（なぜその答えが正しいのか、教材から学べる重要なポイント）"
    }
  ]
}

【クイズ出題範囲（教材から）】
- クリーンアーキテクチャの3つのゴール
- 提唱者Rob​ert C. Martinについて
- アーキテクチャなしでの問題点
- 長期的な保守性の重要性
- 4つの層構造の簡潔な説明
- SOLID原則の基本

クイズは教材の重要な概念を網羅し、学習者が基本を理解したかどうかを測定するのに適したものにしてください。
```

---

## STEP 2: 設計方法論

**ファイル**: `clean-architecture-step2-design.md`

**学習テーマ**: SOLID原則の各層への適用、ユースケース駆動設計、ポートとアダプタパターン、依存性注入戦略

**生成指示**:

```
以下のクリーンアーキテクチャ設計教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- SOLID原則を各層に適用する方法
  * Single Responsibility（単一責任）
  * Open/Closed（開放閉鎖）
  * Liskov Substitution（リスコフ置換）
  * Interface Segregation（インターフェース分離）
  * Dependency Inversion（依存性逆転）
- 責務の分離と凝集度
- テスタビリティを考慮した設計
- エンティティ層の設計
- ユースケース層の構造化
- インターフェース・アダプタ層のパターン
- ポートとアダプタパターン（Hexagonal Architecture）
- 依存性注入（DI）戦略

【クイズ要件】
1. 難易度: 中級（理論を理解している学習者向け）
2. 問題数: 12問
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON（上記STEP 1と同じ形式。ただしidとtitleは異なる）
5. 出力ファイル名: step2-design.json
6. 保存先: src/data/clean-architecture/

【カスタマイズ】
- id: "clean-architecture-step2"
- title: "クリーンアーキテクチャ設計 - STEP 2: 設計方法論"
- description: "SOLID原則と設計パターンを学ぶクイズ"
- difficulty: "中級"

【クイズ出題範囲（教材から）】
- 単一責任の原則と各層での実装例
- 開放閉鎖原則と拡張性
- インターフェース設計の重要性
- ポートとアダプタの役割
- 依存性逆転の実装方法
- ユースケース駆動の設計
- 層間通信メカニズム

出題は、設計パターンに対する実務的な理解を測定するのに適したものにしてください。
```

---

## STEP 3A: C# での実装

**ファイル**: `clean-architecture-step3a-csharp.md`

**学習テーマ**: C#での具体的な実装、.NETプロジェクト構成、DI Container、Entity Framework Core との統合

**生成指示**:

```
以下のクリーンアーキテクチャC#実装教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- C#プロジェクト構成とフォルダ設計
  * 層別プロジェクト分割戦略
  * フォルダ構造設計
  * プロジェクトファイル（.csproj）基本設定
- エンティティ層の実装（C#クラスとインターフェース）
- ユースケース層の実装
- インターフェース・アダプタ層の実装（Controller, Repository）
- フレームワーク・ドライバー層の実装
- Microsoft.Extensions.DependencyInjection の基本設定
- Entity Framework Core との統合
- 環境別設定の切り替え
- 完全な実装例

【クイズ要件】
1. 難易度: 中級（C#基本文法を理解している学習者向け）
2. 問題数: 11問
5. 出力ファイル名: step3a-csharp.json
6. 保存先: src/data/clean-architecture/
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON

【カスタマイズ】
- id: "clean-architecture-step3a-csharp"
- title: "クリーンアーキテクチャC#実装 - STEP 3A: C# での実装"
- description: "ASP.NET Core環境でのクリーンアーキテクチャ実装を学ぶクイズ"
- difficulty: "中級"

【クイズ出題範囲（教材から）】
- .NETでの層別プロジェクト分割の利点
- Microsoft.Extensions.DependencyInjection の使用方法
- インターフェースと実装クラスの関係
- Entity Framework Core の活用方法
- プロジェクト間の依存関係管理
- DI Container への登録パターン
- C#でのエンティティ実装の特徴

出題は、C#開発者がクリーンアーキテクチャを.NETプロジェクトに適用する際の実務知識を測定するのに適したものにしてください。
```

---

## STEP 3B: TypeScript/JavaScript での実装

**ファイル**: `clean-architecture-step3b-typescript.md`

**学習テーマ**: Node.js/React環境でのクリーンアーキテクチャ、モジュール構成、DI（tsyringe, inversify）、層分離

**生成指示**:

```
以下のクリーンアーキテクチャTypeScript実装教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- プロジェクト構成とモジュール設計
  * フォルダ構造設計
  * npm package.json 構成例
  * モジュール分割戦略
- エンティティ層の実装（TypeScriptクラス）
- ユースケース層の実装
- インターフェース・アダプタ層の実装（API Handler, Repository）
- フレームワーク層の設定
- DI依存性注入（tsyringe, inversify）
- モジュール管理とNamespace
- React/Vue との層分離
- 環境別設定の切り替え
- 完全な実装例

【クイズ要件】
1. 難易度: 中級（TypeScript基本文法を理解している学習者向け）
2. 問題数: 11問
5. 出力ファイル名: step3b-typescript.json
6. 保存先: src/data/clean-architecture/
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON

【カスタマイズ】
- id: "clean-architecture-step3b-typescript"
- title: "クリーンアーキテクチャTypeScript実装 - STEP 3B: TypeScript/JavaScript での実装"
- description: "Node.js/React環境でのクリーンアーキテクチャ実装を学ぶクイズ"
- difficulty: "中級"

【クイズ出題範囲（教材から）】
- Node.js環境でのモジュール分割戦略
- TypeScriptのインターフェース活用
- tsyringe/inversify による DI 設定
- フォルダ構造の命名規約
- React コンポーネントとドメインロジックの分離
- npm モジュール管理の工夫
- 環境別設定の実装方法

出題は、フロントエンド/バックエンド開発者がNode.js/React環境でクリーンアーキテクチャを適用する際の実務知識を測定するのに適したものにしてください。
```

---

## STEP 3C: Java での実装

**ファイル**: `clean-architecture-step3c-java.md`

**学習テーマ**: Spring Boot での実装、Maven/Gradle構成、Spring DI、JPA/Hibernateとの統合

**生成指示**:

```
以下のクリーンアーキテクチャJava実装教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- プロジェクト構成とパッケージ設計
  * Maven/Gradle 構成例
  * パッケージ構造設計
  * pom.xml / build.gradle の設定
  * プロジェクト依存関係
- エンティティ層の実装
- ユースケース層の実装
- インターフェース・アダプタ層の実装（REST Controller, Repository）
- フレームワーク層の実装
- Spring DI コンテナの活用
  * @Component / @Service による自動登録
  * @Autowired と Constructor Injection
  * @Configuration での明示的設定
- JPA/Hibernate との統合
- 環境別設定の切り替え
- 完全な実装例

【クイズ要件】
5. 出力ファイル名: step3c-java.json
6. 保存先: src/data/clean-architecture/
1. 難易度: 中級（Java基本文法とSpring Bootの基本を理解している学習者向け）
2. 問題数: 11問
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON

【カスタマイズ】
- id: "clean-architecture-step3c-java"
- title: "クリーンアーキテクチャJava実装 - STEP 3C: Java での実装"
- description: "Spring Boot環境でのクリーンアーキテクチャ実装を学ぶクイズ"
- difficulty: "中級"

【クイズ出題範囲（教材から）】
- Spring Boot でのパッケージ設計戦略
- Maven/Gradle での依存関係管理
- Spring DI コンテナの登録パターン
- Constructor Injection の重要性
- @Configuration クラスの役割
- JPA エンティティと Domain エンティティの分離
- repository パターンの実装
- テストのしやすさを考慮した設計

出題は、Java/Spring Boot開発者がクリーンアーキテクチャをエンタープライズプロジェクトに適用する際の実務知識を測定するのに適したものにしてください。
```

---

## STEP 4: 適用判断

**ファイル**: `clean-architecture-step4-judgment.md`

**学習テーマ**: メリット・課題・適用判断フレームワーク、段階的導入戦略、リスク評価

**生成指示**:

```
以下のクリーンアーキテクチャ適用判断教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- クリーンアーキテクチャのメリット
  * テスト容易性の向上
  * テスト時間の削減（実例：8秒 → 0.5秒）
  * ビジネスロジックの再利用性
  * フレームワーク独立性
  * チーム保守性の向上
- 導入時の課題
  * 学習コスト
  * 開発速度への初期的な影響
  * 複雑性の増加
  * チームスキル要件
- 適用判断フレームワーク
  * プロジェクト規模別の判定
  * チーム構成別の判定
  * ビジネス要件別の判定
  * 技術スタック別の判定
- 段階的導入戦略

【クイズ要件】
5. 出力ファイル名: step4-judgment.json
6. 保存先: src/data/clean-architecture/
1. 難易度: 中級（実務経験者向け）
2. 問題数: 10問
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON

【カスタマイズ】
- id: "clean-architecture-step4"
- title: "クリーンアーキテクチャ適用判断 - STEP 4: 適用判断"
- description: "プロジェクトにクリーンアーキテクチャを適用すべきか判断するクイズ"
- difficulty: "中級"

【クイズ出題範囲（教材から）】
- テスト性が向上することでの相対的なメリット
- 導入コストと長期メリットのバランス
- プロジェクト規模による適用判定
- チーム規模・スキルレベルによる判定
- ビジネス要件の長期性
- 既存レガシーコードへの適用可能性
- 初期段階での採用判断基準

出題は、意思決定者やアーキテクトが自社プロジェクトへのクリーンアーキテクチャ導入の是非を判断するための実務知識を測定するのに適したものにしてください。
```

---

## STEP 5: 実践応用

**ファイル**: `clean-architecture-step5-practice.md`

**学習テーマ**: 完全な実装例、アンチパターン、制約条件下での適応、FAQ

**生成指示**:

```
以下のクリーンアーキテクチャ実践応用教材に基づいて、日本語の複数選択形式（単一選択）のクイズセットを生成してください。

【教材内容】
- 完全な実装例（タスク管理アプリ）
  * ユースケース定義
  * 要件・設計方針
  * ドメイン分析
  * 実装コード（すべての層）
- よくあるアンチパターンと対策
  * パターン1: 依存性の逆転に失敗
  * パターン2: 層の責務が曖昧
  * パターン3: インターフェースの乱用
  * パターン4: 過度な抽象化
  * パターン5: テスト戦略の欠落
- リソース制約下での適応
  * 小規模チーム（2-3人）での導入
  * 既存レガシーコードへの部分適用
  * MVP 開発での適合レベル調整
- よくある質問 (FAQ)
5. 出力ファイル名: step5-practice.json
6. 保存先: src/data/clean-architecture/

【クイズ要件】
1. 難易度: 上級（実装経験者向け）
2. 問題数: 12問
3. 形式: 単一選択方式（選択肢4個）
4. 出力形式: JSON

【カスタマイズ】
- id: "clean-architecture-step5"
- title: "クリーンアーキテクチャ実践応用 - STEP 5: 実践応用"
- description: "クリーンアーキテクチャの実装例とアンチパターンを学ぶクイズ"
- difficulty: "上級"

【クイズ出題範囲（教材から）】
- 実装例（タスク管理アプリ）の設計・実装の詳細
- アンチパターンの具体的な事例
- 依存性逆転に失敗する具体例
- 過度な抽象化の危険性
- テスト戦略の重要性
- 小規模チームでの効率的な導入方法
- レガシーコードへの段階的適用
- MVP開発でのトレードオフ

出題は、実装経験を積んだ開発者がクリーンアーキテクチャを実務で効果的に適用し、よくある落とし穴を回避するための知識を測定するのに適したものにしてください。
```

---

## 全体的な注意事項

### 出力形式の統一性

すべてのクイズセット（STEP 1～5）は以下の形式で生成してください：

```json
{
  "id": "clean-architecture-stepX",
  "title": "タイトル",
  "description": "説明",
  "difficulty": "初級|中級|上級",
  "questions": [
    {
      "text": "問題文",
      "options": [
        { "text": "オプション1" },
        { "text": "オプション2" },
        { "text": "オプション3" },
        { "text": "オプション4" }
      ],
      "correctOptionIndex": 0,
      "explanation": "解説"
    }
  ]
}
```

### クイズの品質チェックリスト

各クイズセット生成時に、以下の基準を確認してください：

- [ ] 問題文は明確で曖昧でない
- [ ] 選択肢4個はすべて教材に基づいている
- [ ] 正解は教材に明記または強く示唆されている
- [ ] 解説は単なる正解の繰り返しではなく、学習ポイントを含む
- [ ] 難易度は指定したレベルに合致している
- [ ] カバレッジは教材の重要なトピックを網羅している
- [ ] 選択肢の引っかかりやすさは適度（極度に簡単・困難でない）

### 推奨される使用シーン

各STEPのクイズはリニアに学習する想定で設計されています：

1. **STEP 1** → 基礎理論の習得確認
2. **STEP 2** → 設計パターン理解の確認
3. **STEP 3A/B/C** → 言語別実装の習得確認
4.出力先ディレクトリ: `src/data/clean-architecture/`
- 既存クイズセット: `src/data/quizSets.json`
- プロジェクト構成: [ARCHITECTURE.md](../docs/ARCHITECTURE.md)

## ファイル一覧（生成予定）

生成されるクイズセットは以下のファイルとして `src/data/clean-architecture/` に保存されます：

- `step1-foundation.json` - STEP 1: 理論基盤
- `step2-design.json` - STEP 2: 設計方法論
- `step3a-csharp.json` - STEP 3A: C# での実装
- `step3b-typescript.json` - STEP 3B: TypeScript/JavaScript での実装
- `step3c-java.json` - STEP 3C: Java での実装
- `step4-judgment.json` - STEP 4: 適用判断
- `step5-practice.json` - STEP 5: 実践応用

---

## 参考リンク

- 教材ファイル: `extras/clean-architecture/`
- 既存クイズセット: `src/data/quizSets.json`
- プロジェクト構成: [ARCHITECTURE.md](../docs/ARCHITECTURE.md)
