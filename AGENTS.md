# Repository workflow

- Create a dedicated feature branch before implementing a new feature.
- Keep every Git commit atomic: one independently understandable behavior or
  repository concern per commit.
- Use specific commit messages that explain the observable change.
- Do not mix refactors, formatting, documentation, tests, or unrelated fixes
  into a feature commit unless they are required for that exact change.
- Stage files deliberately and review the staged diff before committing so
  each change remains traceable and can be reverted independently.
