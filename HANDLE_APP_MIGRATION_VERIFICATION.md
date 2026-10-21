# handle クラス転換の実装・検証記録

検証日: 2026-10-21 / MATLAB R2024a / Windows / 対話ユーザーのライセンス環境

状態: 実装済み。修正後の関連40件・静的解析54ファイルが合格し、full profileの最終確認が残っている。

## 検証対象

- 転換前の基準コミット: `f272716`。
- AGENTS.mdの新契約: 独立コミット `c2392a2`。
- 最終実行の対象ファイル一覧は `testResults/handle-final-inputs.json`。
  一覧ファイル自体のSHA-256は
  `e4709cd4111f4eeef1d4315943f79e474e16b3c0167e6edf30e0980c9f4053ad`。
- 実行ログ・結果JSONは生成記録として `testResults/` に置き、ソースと分ける。
- 最初のfullはPreviewテストのfixtureフォルダー参照2か所の切替漏れを発見して中断した。
  その後の関連検証で、既定の終了登録に不要なsource-expression警告が出る点も修正した。
  登録は引き続きソース式として保持し、リテラル編集を許可しない。
  中断したfullは完了の証拠には用いない。
- 補足した `tests/verifyHandleAppContract.m` は、UIを作らず独立して実行・静的解析した。

## 要求と実装・証拠の対応

| 要求 | 実装・検証箇所 | 現在の証拠 |
| --- | --- | --- |
| handle形式だけを読み込み・生成 | AppSourceParser、AppClassIdentityRewriter、NewAppGenerator | 関連Parser / Generation / Save As用テスト。AppBaseは対象外診断の入力だけに残る |
| uifigureがちょうど1つ | 既存ModelValidatorのルート数検証 | verifyHandleAppContractで有効なfactory呼び出しを0/1/2個とし、認識数とエラーを照合して合格 |
| 子孫条件は利用者の前提 | README / SPECIFICATION、新しい専用検査は追加しない | ModelValidatorの変更はhelpのみ。既存整合性・所有範囲検証を維持 |
| 通常の初期化追跡と非実行 | InitializationSourceAnalyzer、CallbackSourceAnalyzerのscope | InitializationScopeTest、Parserの非実行sentinel、cleanup-and-rethrowの成功経路と例外握りつぶしの区別 |
| 登録文・雛形の共通化 | CallbackSourceEdits.bindingText / handlerText | 4つの生成経路から共通formatterを使用。関連Callback / Generationテスト合格 |
| 登録の呼出規約 | @app.Handler / (app, source, event) | 実行テストでsource.Textとevent.Suffixを使って実際のボタンを更新 |
| CloseRequestFcnのAdd/Delete | 既定登録を基盤として識別し、Deleteで復元 | 登録が1個であること、メソッド削除、Undoで原文に戻ることを確認 |
| 出力変数なしの起動 | Figure側が所有者を保持 | 生成アプリの実行テスト合格。本体の同等テストをfull profileに含む |
| 通常終了・明示delete | CloseRequestFcnから所有者を削除 | 所有者とFigureの無効化、二重deleteの実行テスト合格 |
| Figure直接削除・ユーザーDeleteFcn | ObjectBeingDestroyedリスナーと再入防止 | ユーザーDeleteFcnが実行され、所有者も無効になる実行テスト合格 |
| 終了キャンセル | 終了判断をデストラクタから分離 | close後は所有者・Figureが有効で、明示deleteでは片付く実行テスト合格 |
| 構築失敗 | コンストラクタが所有者を削除して元の例外を再送出 | Figure作成前・作成後の例外で残留なし。元のエラーIDも確認 |
| 名前衝突とSource保持 | handleメンバー・実際の生成メンバーを予約 | Rename / RoundTrip関連テスト合格。既存登録文の再配置は原文から行う |
| Copyの既存制限を維持 | DocumentModel.copySubtree | コールバック付き部分木の複製対応は追加しない。fullの既存Clipboardテストで照合 |
| 保存・履歴・UI | 既存モデル基盤・EditorLifecycle / EditorInteraction | full profileで最終確認中 |
| fixture原本を維持 | tests/fixtures/handleに派生版を追加 | 原本7ファイルは変更なし。派生版READMEに原本のSHA-256と変更内容を記録 |
| 文書・help・UI文言 | README / SPECIFICATION / doc/ARCHITECTURE / CONTRIBUTING / AGENTS / Open・Save文言 | 新契約へ更新。過去の測定・検証記録は当時の記録として維持 |

## 実行結果

- 関連9テストクラス: **91 passed / 0 failed / 0 incomplete**。
  `testResults/handle-focused2.log` の `HANDLE_FOCUSED` を参照。
  この実行の開始時に検出した本体の静的解析指摘は修正し、次項で再確認した。
- Previewのfixture参照修正、ルート数テスト強化、既定の終了登録の診断修正後:
  **40 passed / 0 failed / 0 incomplete**。`testResults/handle-preview2.log` を参照。
- 変更したプロジェクト所有MATLAB 54ファイル:
  **checkcode指摘ゼロ**。`testResults/handle-final-checkcode.log` の
  `HANDLE_FINAL_CHECKCODE Files=54 Issues=0` を参照。
- 補足の `verifyHandleAppContract`: **Counts=0,1,2 / Passed=1**、checkcode指摘ゼロ。
  `testResults/handle-root-contract.log` を参照。
- `runYamadaTests("full")`: 修正後の**692件を再実行予定**。
  ログは `testResults/handle-full-final.log`、成功時の結果は
  `testResults/handle-full-final-results.json` に保存する。

いずれもプロジェクトルートと `tests` をパスに追加し、AGENTS.mdに従って
昇格したMATLAB実行で検証した。`MATLAB_PREFDIR` は変更していない。

## 最終監査の残り

- full profileの完了・全件合格と、結果JSONの件数を照合する。
- 固定した入力ファイルのSHA-256が検証後も一致することを確認する。
- 追加verifierを含めた文字コード・改行・GPL配置と `git diff --check` を確認する。
- 製品コードのAppBase依存ゼロ、原本fixtureの不変、現在の文書の整合を再確認する。
- 実装と計画・検証記録をコミットし、作業ツリーを確認して完了判定する。
