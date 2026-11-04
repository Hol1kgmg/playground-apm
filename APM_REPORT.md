# APM 検証レポート

- 検証日: 2026-11-04
- 環境: apm 0.35.0 / direnv / mise / macOS / Claude Code
- 参考: <https://github.com/microsoft/apm>（`docs/src/content/docs/` 配下の `concepts/primitives-and-targets.md`, `reference/package-types.md`, `reference/manifest-schema.md`, `reference/lockfile-spec.md`, `reference/targets-matrix.md`）
- 比較対象: [playground-pnpm-skills](https://github.com/Hol1kgmg/playground-pnpm-skills)

## 結論

**APM を使うと、任意の Git リポジトリにある agent skill などを `apm.yml` / `apm.lock.yaml` でバージョン固定して取り込める。ただし管理対象は「エージェントのコンテキスト（プリミティブ）」に限られ、ハーネスの設定ファイルや任意のファイルは管理できない。**

- npm 公開は不要。`skills/<name>/SKILL.md` を置いた GitHub リポジトリをそのまま依存にできる
- `apm.lock.yaml` にコミット SHA と展開ファイルの SHA-256 が記録され、`apm install --frozen` で再現できる
- 持ってくるファイルの **種類** に制限はない（スキルディレクトリ内なら何でもコピーされる）が、ソース側の **配置・形式** と、展開側の **置き場所** は APM が決める

## 仕組み

```
[配布側: 任意の Git リポジトリ]        [利用側]
owner/repo                            apm.yml        ← 依存を宣言（ref / semver 範囲）
└── skills/<name>/SKILL.md   ──────▶  apm.lock.yaml  ← commit SHA + ファイルハッシュを固定
    └── references/ scripts/ ...            │ apm install (--frozen)
                                            ▼
                                      apm_modules/           ← 取得キャッシュ（gitignore）
                                      .agents/skills/<name>/ ← target ごとの固定パスに展開
```

| pnpm agent skills | APM |
|---|---|
| npm パッケージに `skills/` を同梱して publish が必要 | Git リポジトリをそのまま参照（GitHub / GitLab / Bitbucket / ADO / 任意 git） |
| `package.json` + `pnpm-lock.yaml` | `apm.yml` + `apm.lock.yaml` |
| `.agents/skills/pnpm-<pkg>-<skill>` に symlink | target ごとのディレクトリに **実ファイルをコピー** |
| `permissions.<pkg>.skills` で承認 | インストール時に隠し Unicode などをスキャン、MCP の推移依存・実行可能コードは承認制 |
| skills のみ | skills / instructions / prompts / agents / hooks / plugins / MCP / LSP |
| Dependabot で更新 PR | `apm outdated` / `apm update`（Dependabot 対応は未確認） |

## 管理できるもの（プリミティブ）

| プリミティブ | ソース側の形式 | `claude` target の展開先 |
|---|---|---|
| Skills | `SKILL.md`（ルート）/ `skills/<name>/SKILL.md` / `.apm/skills/<name>/SKILL.md` | `.claude/skills/<name>/` |
| Instructions | `.apm/instructions/*.instructions.md` | `.claude/rules/<name>.md` |
| Prompts → Commands | `.apm/prompts/*.prompt.md` | `.claude/commands/<name>.md`（`/command` になる） |
| Agents | `.apm/agents/*.agent.md` | `.claude/agents/<name>.md` |
| Hooks | `hooks/*.json` / `.apm/hooks/*.json`（＋参照スクリプト） | `.claude/settings.json` に **マージ** |
| Plugins | `plugin.json` / `.claude-plugin/` | 分解して上記プリミティブとして展開 |
| MCP サーバー | `apm.yml` の `dependencies.mcp` | Claude の MCP 設定（ドキュメント上は `.claude.json`） |
| LSP サーバー | `apm.yml` の `dependencies.lsp` | 各ハーネスの設定 |
| 生成物 | instructions から `apm compile` | `CLAUDE.md`（`.claude/rules/` に展開済みのものは除外） |

### バージョン指定

| 指定 | 例 | 挙動 |
|---|---|---|
| なし | `owner/repo` | デフォルトブランチ。ロックで commit 固定 |
| ブランチ | `owner/repo#main` | ロックで commit 固定。`apm update` で前進 |
| タグ | `owner/repo#v1.0.0` | 不変 |
| SHA | `owner/repo#f162fbc` | 完全固定 |
| semver 範囲 | `ref: ^1.2.0`（オブジェクト形式） | リモートのタグ（`v1.2.3` 等）と照合し最大を選択。プレリリースは対象外 |
| サブパス | `owner/repo/skills/foo` / `owner/repo/x.prompt.md` | リポジトリの一部だけを依存にできる |
| スキル選択 | `--skill <name>`（`skills:` として `apm.yml` に記録） | コレクションから一部だけ展開 |
| ローカル | `./packages/foo` | 開発用。固定なし |

Git 依存に `version:` は書けない（`ref:` を使う）。`version:` はマーケットプレイス / レジストリ依存用。

## 管理できないもの（境界）

| 対象 | 理由 |
|---|---|
| プリミティブ形式でないファイル（README, LICENSE, 任意の設定ファイル） | 展開されない。単一ファイル依存は `.agent.md` / `.instructions.md` / `.prompt.md` のみ |
| パッケージ構造を持たない任意のディレクトリ | 「arbitrary directories are not packages」。探索は非再帰 |
| 任意の展開先 | 展開先は target ごとに固定。変えられるのは `alias`（ディレクトリ名）のみ |
| ハーネス設定のうち APM が書いていない部分 | hooks エントリのみマージで所有。手書きの MCP エントリも非所有 |
| 自リポジトリ内のローカルプリミティブ（`.apm/`） | バージョン管理は Git そのもの。ロックにはハッシュのみ |

**抜け道**: Skill bundle はディレクトリ構造ごとコピーされるため、スクリプトやテンプレートもスキル内に置けば一緒にバージョン管理される（例: `dependabot-review/references/*.md`）。

## `.claude/` での具体例

| パス | APM 管理 | 備考 |
|---|---|---|
| `.claude/skills/<name>/`（SKILL.md + 同梱ファイル） | ✅ | skills。同梱の `.sh` や `.md` も含めて丸ごと |
| `.claude/rules/<name>.md` | ✅ | instructions から |
| `.claude/commands/<name>.md` | ✅ | prompts から変換 |
| `.claude/agents/<name>.md` | ✅ | agents から |
| `.claude/settings.json` の `hooks` | △ | hook パッケージのエントリをマージ。APM が書いたエントリのみ所有 |
| `.claude/settings.json` の `permissions` / `statusLine` / `env` / `language` | ❌ | ハーネス設定は対象外 |
| `.claude/settings.local.json` | ❌ | 同上 |
| `.claude/statusline.sh` | ❌ | `.claude/` 直下への任意配置はできない。hook でもないので hooks 経由も不可 |
| `.claude/statusline.sh` 相当をスキル内に同梱 | △ | `.claude/skills/<name>/statusline.sh` としてなら配布可。ただし参照する `statusLine` 設定は手で書いてコミットが必要 |
| `CLAUDE.md` | △ | `apm compile` で instructions から生成。手書き内容の配布ではない |

`settings.json` / `statusline.sh` を共有したい場合は、従来どおり Git で直接管理するか dotfiles 等の別手段を使う。

## このリポジトリでの検証結果

| 項目 | 内容 | 検証 |
|---|---|---|
| mise で apm 導入 | `"github:microsoft/apm" = "0.35.0"` | ✅ |
| GitHub リポジトリから skill 導入 | `apm install Hol1kgmg/skills` で 2 スキル展開 | ✅ |
| `targets: [claude]` | `.claude/skills` が symlink のため `Unsafe skill destination` で拒否 | ❌ |
| `targets: [agent-skills]` | `.agents/skills/` に直接展開、`.claude/skills` symlink 経由で認識 | ✅ |
| エージェントからの認識 | Claude Code が即座に認識 | ✅ |
| ロック | `resolved_commit` と各ファイルの sha256 を記録 | ✅ |
| ドリフト検出 | `apm audit` → `No drift detected` | ✅ |
| direnv で自動展開 | `.envrc` で `apm install --frozen`（`apm.yml` / `apm.lock.yaml` を watch） | ✅ |
| スキル実体の Git 除外 | `.agents/skills/.gitignore`（`*` + `!.gitignore` `!.gitkeep`） | ✅ |
| 削除後の lock からの復元 | 実ファイル削除 → `apm install` | ⚠️ 未検証 |
| semver 範囲での指定 | `Hol1kgmg/skills` にタグがないため不可 | ⚠️ 未検証 |
| hooks / MCP / instructions の配布 | | ⚠️ 未検証 |

### 構成

```yaml
# apm.yml
targets:
  - agent-skills
dependencies:
  apm:
    - Hol1kgmg/skills
```

```bash
# .envrc
watch_file apm.yml apm.lock.yaml
mise x -- apm install --frozen
```

## 注意

- APM 公式は展開物のコミットを推奨（「Commit `apm.yml`, `apm.lock.yaml`, and target-owned outputs」）。このリポジトリでは pnpm 版に合わせて Git 除外し、direnv で展開している
- `.claude/skills` を `.agents/skills` への symlink にしている構成では `claude` target が使えない
- SKILL.md の frontmatter は ASCII のみ・`name` はディレクトリ名と一致が必要
- ドキュメントは apm main ブランチ基準。CLI 0.35.0 と細部が異なる可能性がある
