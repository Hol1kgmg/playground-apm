# playground-apm

[APM (Agent Package Manager)](https://github.com/microsoft/apm) で agent skill を管理する動作検証用リポジトリ。

## Prerequisites

This project uses [mise](https://mise.jdx.dev/) for tool management.

If you haven't installed `mise` yet:

```bash
# Install mise (macOS)
brew install mise
# OR via curl
curl https://mise.run | sh

# Shell integration (for zsh)
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc
```

## Setup

```bash
mise run setup
```

This installs the tools in `mise.toml` and registers the `lefthook` pre-commit hook (gitleaks secret scan), then runs `apm install` to deploy skills declared in `apm.yml`.

## APM による agent skill 管理

### 仕組み

- `apm.yml` に依存を宣言し、`apm.lock.yaml` に解決済みコミットとファイルハッシュを固定する
- 任意の Git リポジトリの `skills/<name>/SKILL.md` をそのまま取得できる（npm 公開不要）
- 取得物のキャッシュは `apm_modules/`（Git 除外）、展開先は `targets` で決まる

### 手順

```bash
apm install <owner>/<repo>                   # 追加して apm.yml に記録
apm install <owner>/<repo> --skill <name>    # 特定スキルだけ
apm install                                  # apm.lock.yaml から再現
apm audit                                    # 隠し Unicode 検査 + ドリフト検出
```

### このリポジトリでの構成

- 依存: [Hol1kgmg/skills](https://github.com/Hol1kgmg/skills)（`dependabot-review`, `speckit-explain`）
- ターゲット: `agent-skills` → `.agents/skills/<name>/` に実ファイルをコピー
  - Claude Code は `.claude/skills -> ../.agents/skills` のシンボリックリンク経由で認識する

### direnv による自動展開

`.envrc` がディレクトリ進入時と `apm.yml` / `apm.lock.yaml` 変更時に `apm install --frozen` を実行し、ロック通りにスキルを展開する。

```bash
direnv allow   # 初回のみ
```

- 上流の更新を取り込むときは `apm update` → `apm.lock.yaml` の差分をコミット
- 他の人は `git pull` 後にディレクトリへ入り直す（または lock 変更で direnv が再実行される）だけで追従する

### 注意

- `targets: [claude]` だと `.claude/skills` がシンボリックリンクのため `Unsafe skill destination` で拒否される。`agent-skills` を使う
- 展開されたスキルは Git 管理外（`.agents/skills/.gitignore`）。手書きスキルを置く場合は `!<name>/` を追記する
- 依存はタグ/SHA 未指定（`#main`）。`apm.lock.yaml` でコミットは固定されるが、再現性を上げるなら `Hol1kgmg/skills#<tag>` で固定する
