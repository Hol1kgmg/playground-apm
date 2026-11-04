# APM / layat 比較・運用構成レポート

- 作成日: 2026-11-05
- 比較対象:
  - 本リポジトリ（APM 0.35.0）: [APM_REPORT.md](./APM_REPORT.md)
  - [playground-layat](https://github.com/Hol1kgmg/playground-layat)（layat / Nix flake）: `LAYAT_SKILLS_REPORT.md`
- 参考: <https://github.com/microsoft/apm> `docs/src/content/docs/reference/lockfile-spec.md`

## 結論

**「ツールは自動マージ、skill / プロンプトはレビュー必須」という運用を前提にすると、Nix（ツール + layat）と APM（skill / プロンプト）の併用が適切。**

- 固定の厳密さ（再現性・不変性）では layat が上。監査性・供給元の安全性では APM が上
- ツールを Nix に統一すれば、両者の差は「配置物が read-only か（layat）/ コピーか（APM）」に縮まる
- 併用の最大の利点は **レビュー方針を lock ファイル単位で分けられること**。layat 単体ではツールと skill が同じ `flake.lock` に乗るため、パスベースの保護（CODEOWNERS）で分離できない

## 1. 管理の厳密さの比較

両リポジトリとも同じコミット `f162fbc53d1cece940fd2735edc918ea36b22111` を固定しており、内容は同一。差は固定の仕組みにある。

| 観点 | layat (Nix flake) | APM | 優位 |
|---|---|---|---|
| ソース固定 | `flake.lock` に `rev` + `narHash`（ソースツリー全体） | `apm.lock.yaml` に `resolved_commit` + `content_hash`（展開ツリー） | 同等。どちらも取得時に照合 |
| 配置後の改変 | `/nix/store` への symlink。read-only で構造的に編集不可 | 実ファイルのコピー。編集可能で、`apm audit` を実行すれば検出 | layat |
| ツール自体の固定 | layat / nixpkgs（gitleaks・lefthook・jq 含む）を `flake.lock` で rev + hash 固定 | mise で `apm 0.35.0` のみバージョン指定。他は `latest`、`mise.lock` なし | layat（※本リポジトリの設定起因） |
| 配置内容の可視性 | lock は rev / hash のみ。配置対象は `readDir` で導出され lock に残らない | lock に `deployed_files` とファイルごとの sha256。PR 差分で変更ファイルが見える | APM |
| 内容の安全検査 | なし（`flake.nix` への記述が承認） | 隠し Unicode 等のスキャン、MCP / 実行可能コードの承認制 | APM |
| 管理対象 | 任意のファイル / ディレクトリを任意パスへ（symlink / copy） | プリミティブ（skills / instructions / prompts / agents / hooks / MCP / LSP）のみ。展開先は target ごとに固定 | 用途次第 |
| 設定へのマージ | 不可（ファイル単位で配置） | hooks を `settings.json` へ、MCP を設定へマージ | APM |
| マルチハーネス変換 | なし | 1 ソースから claude / codex / cursor 等へ変換 | APM |

`content_hash` について lockfile-spec は「For remote dependencies it verifies that downloaded or cached content still matches the lock」と記載しており、APM も取得時の整合性検証を行う。

## 2. 運用要件

| 対象 | 変更の性質 | 期待する扱い |
|---|---|---|
| ツール（apm, gitleaks, lefthook, jq, layat 本体, nixpkgs） | 実行ファイル。CI / 静的解析で品質を確認できる | Dependabot + CI 通過で自動マージ |
| skill / プロンプト / hooks / MCP | エージェントの振る舞いを変える自然言語・設定。静的解析では妥当性を判断できない | 人のレビュー必須 |

## 3. 構成案の比較

| 項目 | APM + Nix(layat) 併用 | layat 単体 |
|---|---|---|
| lock ファイル | `flake.lock`（ツール）/ `apm.lock.yaml`（skill） | `flake.lock` のみ |
| レビュー要否の分離 | ファイル単位。CODEOWNERS + ブランチ保護で強制できる | 同一ファイル内の input 単位。PR メタデータで判定する workflow が必要（Dependabot が input ごとに PR を分ける前提、未検証） |
| 判定ミス時の影響 | ブランチ保護が最終防衛線になる | skill 更新が自動マージされうる |
| skill 配置物の不変性 | コピー（`apm audit` で検出） | read-only symlink |
| 更新経路 | 2 系統（Dependabot nix / `apm update`） | 1 系統 |
| ツール数 | Nix + direnv + apm | Nix + direnv |

**判断**: 更新経路が 2 系統になるコストより、レビュー強制をブランチ保護に委ねられる確実性を優先し、併用を採用する。

## 4. 推奨構成

### 責務分離

| 管理対象 | 手段 | lock | 更新 PR |
|---|---|---|---|
| ツール | Nix flake（devShell） | `flake.lock` | Dependabot → CI → 自動マージ |
| skill / プロンプト / hooks / MCP | APM | `apm.lock.yaml` | 更新 PR → Code Owner レビュー → マージ |
| プリミティブ外の設定ファイル（statusline 等） | layat | — | 本リポジトリ内に置き、通常の PR レビュー |

**注意**: layat の配置元に外部 input（`flake = false`）を使うと、その更新は `flake.lock` に乗り **自動マージ側に入ってしまう**。レビューが必要なファイルを layat で配置する場合は、配置元を本リポジトリ内（`src = ./config` 等）に限定し、`flake.lock` の外部 input はツールのみとする。

### 全体像

```
                ┌──────────── flake.nix / flake.lock ────────────┐
Dependabot(nix) │ nixpkgs, layat, apm(要パッケージング)           │ ──▶ CI ──▶ 自動マージ
                │ devShell: gitleaks / lefthook / jq / apm / layat│
                │ layat: リポジトリ内の設定ファイルを配置          │
                └────────────────────────┬───────────────────────┘
                                         │ direnv: use flake
                                         ▼
                ┌──────────── apm.yml / apm.lock.yaml ───────────┐
apm update(定期)│ Hol1kgmg/skills など                            │ ──▶ CI ──▶ Code Owner レビュー ──▶ マージ
                │ apm install --frozen → .agents/skills/          │
                └─────────────────────────────────────────────────┘
```

### 設定例（未検証）

```bash
# .envrc
use flake
watch_file apm.yml apm.lock.yaml
apm install --frozen
```

```
# .github/CODEOWNERS
apm.yml        @Hol1kgmg
apm.lock.yaml  @Hol1kgmg
```

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "nix"
    directory: "/"
    schedule:
      interval: "weekly"
```

```yaml
# .github/workflows/dependabot-auto-merge.yml
name: dependabot-auto-merge
on: pull_request
permissions:
  contents: write
  pull-requests: write
jobs:
  automerge:
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: ubuntu-latest
    steps:
      - run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

ブランチ保護（Repository rulesets）:

| 設定 | 値 | 目的 |
|---|---|---|
| Require a pull request before merging | on | |
| Required approvals | 0 | ツール PR を承認なしで通す |
| Require review from Code Owners | on | `apm.*` を含む PR のみ承認必須にする |
| Require status checks to pass | on（CI / gitleaks 等） | 自動マージの品質ゲート |
| リポジトリ設定 Allow auto-merge | on | `gh pr merge --auto` の前提 |

自動マージ workflow は振り分けを行わず一律に `--auto` を付ける。skill を含む PR は Code Owner 承認が付くまでブランチ保護で止まる。

### CI に追加するチェック

| チェック | 目的 |
|---|---|
| `apm install --frozen` | lock と manifest の整合 |
| `apm audit` | 展開物のドリフト検出（コピー方式の弱点の補完） |
| `nix flake check` | flake の評価確認（`unknown flake output 'layat'` warning は想定どおり） |
| gitleaks | シークレット混入検出 |

## 5. 未検証事項

| 項目 | 影響 | 代替案 |
|---|---|---|
| apm の Nix パッケージ有無（nixpkgs） | なければツール統一ができない | GitHub Release をハッシュ指定で取得する derivation を自作 |
| Dependabot の APM 対応 | skill 更新 PR の自動作成 | 定期 workflow で `apm update` → PR 作成 |
| `GITHUB_TOKEN` で作成した PR で CI が起動するか | 起動しない仕様のため、上記代替案では CI が走らない | GitHub App トークン / PAT で PR を作成 |
| Rulesets で Required approvals 0 + Code Owner review の組み合わせ | 想定どおりならツール PR のみ無承認で通る | 実リポジトリで確認 |
| Dependabot `nix` ecosystem の動作（`flake = false` input 含む） | ツール自動更新の前提 | 定期 workflow で `nix flake update` → PR |
| layat で `settings.json` 等を配置した場合のハーネスからの書き込み | read-only symlink だと書き込めない可能性 | `method = "copy"` |
| layat の API 安定性（MVP） | 将来の破壊的変更 | layat input を固定し、更新はレビュー対象にする |

## 6. 判断を見直す条件

- **layat 単体に寄せる**: skill の配布元が自分のリポジトリのみで、レビュー要否の分離が不要になった場合
- **APM の比重を上げる**: 複数ハーネス（Codex / Cursor 等）での利用、第三者の skill / MCP の取り込み、hooks / MCP を既存設定へマージしたくなった場合
