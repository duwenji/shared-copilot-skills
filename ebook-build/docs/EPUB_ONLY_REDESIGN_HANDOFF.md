# EPUB-Only Redesign Handoff

## 目的

`shared-copilot-skills/ebook-build` を次の方針に合わせて再設計する。

- page-list は廃止する
- 生成物は EPUB のみとする
- 章節はフォルダ・ファイル体系で決める
- 章節番号はフォルダ名・ファイル名の先頭数値を表示にも使う

この文書は、実装担当がそのまま着手できる粒度で、変更対象ごとの作業内容と受け入れ条件を定義する。

## 確定方針

### 契約

- 出力形式は EPUB のみ
- `page-list` は設定ではなく機能として廃止
- 章は `sourceRoot` または `sourceRoot/docs` 直下の `^\d{2}-` フォルダ
- 節は各章フォルダ直下の `^\d{2}-.*\.md$` ファイル
- `00-COVER.md` は章節体系の外にある表紙ファイル
- 3 階層以上のネストは非対応
- root `README.md` 自動 TOC 更新の改善は今回の対象外

### タイトル決定ルール

- 章タイトルはフォルダ名の slug から生成する
- 節タイトルはファイル名の slug から生成する
- 章 README や各 Markdown の H1 は章節名の決定源に使わない
- 先頭番号は並び順だけでなく、生成見出しにも表示する

例:

- `01-introduction` -> `01. Introduction`
- `02-core-principles` -> `02. Core Principles`
- `03-key-concepts.md` -> `03. Key Concepts`

## 実装順

1. Runner を EPUB-only にする
2. Converter から AZW3/MOBI/page-list を除去する
3. 章節タイトル決定を体系主導に固定する
4. 仕様書・README・SKILL を更新する
5. Validation とテンプレートを更新する
6. Consumer repo 設定を移行する
7. Representative repo で build 検証する
8. 残存語を横断検索して掃除する

## ファイル別変更指示

### 1. `ebook-build/scripts/invoke-ebook-build.ps1`

#### 変更目的

- runner の入力契約を EPUB-only に変更する
- page-list 関連の staging と patch を除去する
- artifact 回収を EPUB 1 件前提に簡素化する

#### 現状の問題

- `EnablePageList` が既定有効
- `Formats` が複数形式前提
- page-list helper の存在確認と staging がある
- staged converter に対して page-list 無効化パッチを当てている
- artifact 回収が format ループ前提

#### やること

1. `param` から `EnablePageList` を削除する、または互換のため残す場合でも使用禁止にする
2. `Resolve-Value` による `EnablePageList` 解決を削除する
3. `Formats` のデフォルトを `@('epub')` に変更する
4. `formats` に `epub` 以外が含まれていたら失敗させる
5. `add-pagelist-functions.ps1` の有無確認を削除する
6. page-list helper の staging コピーを削除する
7. staged converter の文字列置換による page-list 無効化処理を削除する
8. artifact 回収処理を EPUB 1 件専用に書き換える
9. `Requested format not found` の warning 分岐を削除する
10. `No requested artifacts were copied` ではなく、EPUB が生成されなかったことを明示する失敗文言に変える

#### 完了条件

- page-list に関する変数、警告、helper コピー、patch が runner から消えている
- runner が EPUB のみを回収する
- `formats` に `azw3` や `mobi` を指定すると明示エラーになる、または設定項目自体を廃止している

#### 依存関係

- 先行着手可
- converter 側の整理前でも修正に着手できる

### 2. `ebook-build/scripts/convert-to-kindle.ps1`

#### 変更目的

- converter の責務を EPUB 生成だけに絞る
- 章節名の決定源をファイルシステム由来に固定する
- page-list 依存を元実装から除去する

#### 現状の問題

- AZW3/MOBI 変換関数が存在する
- `ebook-convert` を探している
- page-list helper を読み込んでいる
- `Add-PageListToEpub` を呼んでいる
- 章タイトルが章 README の H1 に寄る
- 節タイトルが各 Markdown の H1 に寄る

#### やること

1. `Convert-ToAzw3` を削除する
2. `Convert-ToMobi` を削除する
3. `ebook-convert` 検出と関連出力パスを削除する
4. AZW3/MOBI に関するログと最終案内を削除する
5. page-list helper の dot-source を削除する
6. `Add-PageListToEpub -EpubPath $epubOutput` を削除する
7. `Get-BookChapterTitle` が章 README の H1 に依存しないようにする
8. `Get-BookSectionTitle` が本文 H1 に依存しないようにする
9. `Get-EpubChapterTitle` と `Get-EpubSectionTitle` が slug 由来タイトル + 接頭番号だけで決まるよう整理する
10. Kindle/AZW3/MOBI を前提にしたコメントや説明文を EPUB 前提に置き換える

#### 実装メモ

- `Convert-SlugToTitle` を章節タイトルの単一ソースとして扱うのが妥当
- `Remove-LeadingNumberMarker` は本文 H1 用の補助に降格するか、不要なら削除する
- `Get-MarkdownH1Title` を章節名生成に使わない形に寄せる
- root `README.md` の TOC 更新ロジックは今回の改善対象外なので、壊さない範囲で維持する

#### 完了条件

- converter 実行中に `ebook-convert` を要求しない
- EPUB だけを出力する
- 章 README や本文 H1 を変えても章節タイトルが変わらない設計になっている
- page-list への参照が converter 本体から消えている

#### 依存関係

- runner と並行可能
- title 決定ルールの変更は後続 docs 更新前に完了させる

### 3. `ebook-build/scripts/add-pagelist-functions.ps1`

#### 変更目的

- 廃止対象の page-list 実装を shared から除去する

#### やること

1. runner と converter から参照が消えたことを確認する
2. ファイルを削除する

#### 完了条件

- shared 配下に page-list 実装ファイルが残っていない

#### 依存関係

- `invoke-ebook-build.ps1` と `convert-to-kindle.ps1` の参照削除後

### 4. `ebook-build/SKILL.md`

#### 変更目的

- 外向け契約を EPUB-only に更新する

#### やること

1. skill description から `EPUB, AZW3, MOBI` を削除する
2. overview と does セクションから Kindle/page-list/AZW3/MOBI 前提を除去する
3. requirements から Calibre を削除する
4. inputs 表の `formats` と `enablePageList` を削除する、または `epub` 限定に書き換える
5. shared files 一覧から `add-pagelist-functions.ps1` を削除する
6. output 例を `project-name.epub` のみにする
7. validation 導線を EPUB-only の文書構成に合わせて更新する

#### 完了条件

- skill を読むだけで EPUB-only 契約が分かる
- Kindle/AZW3/MOBI/page-list を使うと誤解させる記述が残っていない

### 5. `ebook-build/EBOOK_BUILD_SPECIFICATION.md`

#### 変更目的

- 実装と仕様のずれをなくす

#### やること

1. goal を EPUB-only 契約に合わせる
2. chapter contract に「章フォルダ直下の番号付き Markdown が節」という 2 層制約を明記する
3. `00-COVER.md` を体系外の例外として明記する
4. build steps から page-list patching の概念を削除する
5. page-list behavior セクションを削除する
6. format behavior を EPUB-only に変更する
7. error strategy から optional format warning を削除する
8. project-specific responsibilities から不要な多形式前提を除去する

#### 完了条件

- 仕様書の記述だけで実装方針が再現できる
- 現行コードと矛盾しない

### 6. `ebook-build/docs/README.md`

#### 変更目的

- 利用ガイドを新運用に合わせる

#### やること

1. prerequisites から `ebook-convert` と Calibre を削除する
2. run command はそのままでもよいが、期待成果物を EPUB のみにする
3. validation 導線から Kindle 前提文書への依存を外す
4. troubleshooting から `ebook-convert not found` を削除する
5. markdown 検出条件に 2 層契約と表紙例外が分かる説明を追加する

#### 完了条件

- README を読むだけで Pandoc があれば十分と分かる
- 利用者が Kindle/AZW3/MOBI を期待しない

### 7. `ebook-build/VALIDATION_CHECKLIST.md`

#### 変更目的

- 受け入れ観点を EPUB-only に合わせる

#### やること

1. AZW3 出力確認を削除する
2. MOBI 出力確認を削除する
3. page-list ステップ確認を削除する
4. EPUB 出力、TOC、内部リンク、章節順、見出し番号表示、表紙、コードブロック、nav 妥当性を確認項目に入れる
5. compatibility セクションを EPUB viewer 前提に書き換える

#### 完了条件

- checklist を実施すれば EPUB-only build の品質確認になる

### 8. `ebook-build/docs/KINDLE-COMPATIBILITY-CHECKLIST.md`

#### 変更目的

- EPUB-only 方針と矛盾する Kindle/AZW3 運用文書を除去する

#### やること

次のいずれかを選ぶ。

1. ファイルを削除する
2. EPUB viewer 向け文書へ全面改稿し、別名にする

推奨は削除。

#### 完了条件

- shared 側の validation 導線が Kindle デバイス必須を要求しない

### 9. `templates/ebook-build/repo.build.template.json`

#### 変更目的

- consumer repo に配る設定を新契約へ揃える

#### やること

1. `formats` を削除する、または `epub` のみを許可する形に変える
2. `enablePageList` を削除する
3. 他のキーは維持する
4. 必要ならコメント相当の README で、EPUB-only 契約を補足する

#### 完了条件

- 新規 consumer repo がテンプレートから複数形式前提を持ち込まない

### 10. Representative consumer configs

対象:

- `clean-architecture/.github/skills-config/ebook-build/clean-architecture.build.json`
- `amazon-kdp-guide/.github/skills-config/ebook-build/amazon-kdp-guide.build.json`
- 他の consumer repo の同等 build config

#### 変更目的

- shared 契約変更に consumer 設定を追随させる

#### やること

1. `formats` を削除する、または `epub` のみにする
2. `enablePageList` を削除する
3. `projectName`、`sourceRoot`、`metadataFile` などの残存キーが新契約でも有効なことを確認する

#### 完了条件

- representative repo の config が shared の新契約でそのまま読める

## 検証手順

### 実装完了後の確認

1. `shared-copilot-skills` 全体で次を検索する

```text
page-list|EnablePageList|add-pagelist-functions|azw3|mobi|ebook-convert|Calibre|Kindle
```

2. 意図して残すもの以外が消えていることを確認する
3. `clean-architecture` で build して EPUB が生成されることを確認する
4. `amazon-kdp-guide` で build して EPUB が生成されることを確認する
5. 章節順がフォルダ名・ファイル名順であることを確認する
6. 見出し番号が表示されることを確認する
7. README や本文 H1 を変えても章節タイトルが変わらないことを確認する
8. Calibre 未導入環境でも失敗しないことを確認する

## スコープ外

- root `README.md` 自動 TOC 更新ロジックの改善
- `convert-to-kindle.ps1` のファイル名変更
- 3 階層以上の章節モデル対応
- 既存 EPUB の見た目最適化そのもの

## 実装上の注意

- shared 側は破壊的変更を許容する前提で進める
- ただし、consumer repo の config 追随更新は同じ変更セットで行う方が安全
- 仕様書更新を後回しにすると再度 Kindle 前提が混入しやすいので、コード変更直後に docs を更新する