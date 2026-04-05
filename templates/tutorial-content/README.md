# tutorial-content templates

These files standardize the landing-page copy for new tutorial/material repositories.

## Files

| Template file | Copy to consumer repo as |
|---|---|
| `README.template.md` | `README.md` |
| `00-COVER.template.md` | `docs/00-COVER.md` |

## Standard quiz callout

Use this exact note in both `README.md` and `docs/00-COVER.md`:

```md
> 💡 ブラウザで https://duwenji.github.io/spa-quiz-app/ を開くと、関連トピックをクイズ形式で復習できます。
```

This wording stays accurate whether the repository has a dedicated quiz set or only related topic coverage in `spa-quiz-app`.

## Recommended flow

1. Copy the template files into the new repository.
2. Replace the placeholder sections with the project title, summary, and learning goals.
3. Keep the quiz callout unchanged unless the destination URL itself changes.
4. If quiz coverage is newly added later, keep the same wording for consistency across repositories.
