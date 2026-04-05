# PUBLISHING

## Shared skill release flow
1. 対象 skill・`templates/`・`docs/` を更新する
2. 代表 consumer repo で実動確認する
   - `amazon-kdp-guide`
   - `clean-architecture`
   - `spa-quiz-app`（flat-docs profile）
3. `ebook-build` の場合は以下 3 成果物を確認する
   - `ebook-output/<project>.epub`
   - `ebook-output/<project>.pdf`
   - `ebook-output/<project>-kdp-registration.md`
4. `CHANGELOG.md` を更新する
5. tag / release の準備を行う
6. consumer repo の submodule pointer を更新する

## Suggested verification commands

```powershell
# shared repo 側の変更を反映した状態で consumer repo を確認
powershell -NoProfile -ExecutionPolicy Bypass -File .\.github\skills-config\ebook-build\invoke-build.ps1
```

If the release adds or changes the `ebook-build` contract, also verify that:

- `README.md` / `PUBLISHING.md` / template docs are updated
- `formats` / `kdpMetadataFile` examples still match the current implementation
- PDF generation prerequisites are documented clearly

If the release touches tutorial scaffolding, also verify that:

- `templates/tutorial-content/README.template.md` and `00-COVER.template.md` contain the standard `spa-quiz-app` callout
- the wording remains `関連トピックをクイズ形式で復習できます`

