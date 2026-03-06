# Contributing to Zuzu

Thank you for your interest in improving Zuzu.

## Setup

```bash
git clone https://github.com/parolkar/zuzu.git
cd zuzu
bin/setup          # installs Java 21, JRuby, and gems
```

## Running Locally

```bash
ZUZU_DEV=1 bin/zuzu new my_test_app   # scaffolds with local gem path
cd my_test_app
bundle install
bin/zuzu start
```

Set `ZUZU_DEV=1` so scaffolded apps point to your local checkout instead of the
published gem.

## Code Style

- Keep files short. If a class exceeds ~200 lines, split it.
- No meta-programming magic. Prefer explicit, readable Ruby.
- Every public method gets a one-line comment.
- `frozen_string_literal: true` in every file.

## Pull Requests

1. Fork the repo and create a feature branch.
2. Keep commits small and focused.
3. Add or update tests where applicable.
4. Run `rake test` before submitting.
5. Open a PR against `main` with a clear description.

## Reporting Issues

Use [GitHub Issues](https://github.com/parolkar/zuzu/issues). Include:
- JRuby version (`jruby -v`)
- Java version (`java -version`)
- OS and version
- Steps to reproduce

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
