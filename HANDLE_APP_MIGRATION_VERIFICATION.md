# handle クラス転換の実装・検証記録

検証日: 2026-10-21 ～ 2026-10-22 / MATLAB R2024a / Windows / 対話ユーザーのライセンス環境

状態: 実装・最終検証完了。full profileは692件合格、失敗・未完了ともゼロ。

## 検証対象

- 転換前の基準コミット: `f272716`。
- AGENTS.mdの新契約: 独立コミット `c2392a2`。
- full profileの対象はクリーンな `353a22cd730664502487c7e89d6ba592e6a0dc3c`。
- 最終実行の対象ファイル一覧は `testResults/handle-final-inputs.json`。 一覧ファイル自体のSHA-256は `e4709cd4111f4eeef1d4315943f79e474e16b3c0167e6edf30e0980c9f4053ad`。
- 実行ログ・結果JSONは生成記録として `testResults/` に置き、ソースと分ける。
- 最初のfullはPreviewテストのfixtureフォルダー参照2か所の切替漏れを発見して中断した。 その後の関連検証で、既定の終了登録に不要なsource-expression警告が出る点も修正した。 登録は引き続きソース式として保持し、リテラル編集を許可しない。 中断したfullは完了の証拠には用いない。
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
| 出力変数なしの起動 | Figure側が所有者を保持 | 生成アプリ・本体の両方で、起動後の有効性とclose後の無効化を確認して合格 |
| 通常終了・明示delete | CloseRequestFcnから所有者を削除 | 所有者とFigureの無効化、二重deleteの実行テスト合格 |
| Figure直接削除・ユーザーDeleteFcn | ObjectBeingDestroyedリスナーと再入防止 | ユーザーDeleteFcnが実行され、所有者も無効になる実行テスト合格 |
| 終了キャンセル | 終了判断をデストラクタから分離 | close後は所有者・Figureが有効で、明示deleteでは片付く実行テスト合格 |
| 構築失敗 | コンストラクタが所有者を削除して元の例外を再送出 | Figure作成前・作成後の例外で残留なし。元のエラーIDも確認 |
| 名前衝突とSource保持 | handleメンバー・実際の生成メンバーを予約 | Rename / RoundTrip関連テスト合格。既存登録文の再配置は原文から行う |
| Copyの既存制限を維持 | DocumentModel.copySubtree | コールバック付き部分木の複製対応は追加せず、fullの既存Clipboardテストも合格 |
| 保存・履歴・UI | 既存モデル基盤・EditorLifecycle / EditorInteraction | EditorInteraction 40件、EditorLifecycle 13件を含むfull profileが合格 |
| fixture原本を維持 | tests/fixtures/handleに派生版を追加 | 原本7ファイルは変更なし。派生版READMEに原本のSHA-256と変更内容を記録 |
| 文書・help・UI文言 | README / SPECIFICATION / doc/ARCHITECTURE / CONTRIBUTING / AGENTS / Open・Save文言 | 新契約へ更新。過去の測定・検証記録は当時の記録として維持 |

## 実行結果

- 関連9テストクラス: **91 passed / 0 failed / 0 incomplete**。 `testResults/handle-focused2.log` の `HANDLE_FOCUSED` を参照。 この実行の開始時に検出した本体の静的解析指摘は修正し、次項で再確認した。
- Previewのfixture参照修正、ルート数テスト強化、既定の終了登録の診断修正後: **40 passed / 0 failed / 0 incomplete**。`testResults/handle-preview2.log` を参照。
- 変更したプロジェクト所有MATLAB 54ファイル: **checkcode指摘ゼロ**。`testResults/handle-final-checkcode.log` の `HANDLE_FINAL_CHECKCODE Files=54 Issues=0` を参照。
- 補足の `verifyHandleAppContract`: **Counts=0,1,2 / Passed=1**、checkcode指摘ゼロ。 `testResults/handle-root-contract.log` を参照。
- `runYamadaTests("full")`: **692 passed / 0 failed / 0 incomplete**。 ログは `testResults/handle-full-final.log`、結果JSONは `testResults/handle-full-final-results.json`。両者の件数と全件合格を照合した。 結果JSONのSHA-256は `7d60bb5668b10d8f3d11cfa3f9b081a34c974557a9425830ced532fa1160329f`。 `HandleAppMigrationTest` 11件、初期化解析14件、CallbackSourceAnalyzer 10件、 CallbackGeneration 7件、PreviewRenderer 7件、ProjectConventions 3件、 TestSelectionContract 3件もこのfull結果に含まれる。

fullログの警告は既存の垂直Slider固定幅テストが出したnative警告2件で、当該テストも合格した。 デストラクタのエラーや未完了は記録されていない。

いずれもプロジェクトルートと `tests` をパスに追加し、AGENTS.mdに従って 昇格したMATLAB実行で検証した。`MATLAB_PREFDIR` は変更していない。

## 最終監査

- full終了直後に入力61ファイルすべてのSHA-256一致を確認した。 `testResults/handle-full-matched-inputs-audit.json` に記録した。
- その後、`EditorInteractionTest` の既存H1コメント1行だけを宣言名 `inspectorProbesRuntimeDefaultsWithoutEntries` に揃えた。最終ファイルからその1行を 元へ戻したバイト列が検証時のハッシュと一致し、他の60ファイルはそのまま一致する。 テスト本体・製品コードに機能差分はない。修正後の同ファイルのcheckcodeも指摘ゼロ。 この照合は `testResults/handle-final-audit.json`、静的解析は `testResults/handle-final-help-checkcode.log` に記録した。
- 61ファイルのUTF-8 BOMなし・CRLF、プロジェクト所有54ファイルの宣言先頭と 完全な末尾GPL通知を確認した。49クラス・831関数のH1名と直後配置も照合して問題ゼロ。 保存入力fixtureはこのdocstring監査の対象に含めていない。
- 原本fixture 7ファイルのハッシュは派生版READMEの由来記録と一致し、 `f272716` の原本とGitの改行正規化を考慮した内容比較でも一致する。
- 製品の `+macd` と `yamada.m` にAppBase・registerApp・createCallbackFcn・ runStartupFcnの参照はない。対象外診断のテスト文字列と歴史的資料・原本fixtureは別に保持する。
- 段階1～3と上記要求表の全項目を確認し、契約に反する互換モードや子孫条件専用検査は追加していない。 保存・履歴・コールバック・配置の既存安全境界と、保留中の独立作業は維持した。
- full終了後の追加変更は、上記H1コメントと文書だけである。README冒頭を対象クラスの短い説明にし、コールバック詳細を後方へ移動した。プロジェクトMarkdownの段落内改行も整理し、コードブロック・表・箇条書きの構造と本文を照合した。
- `git diff --check` を確認し、完了記録とH1表記修正は実装とは別の文書コミットで確定する。
