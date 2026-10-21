# handle クラス形式への転換計画

作成日: 2026-10-21

完了日: 2026-10-22

状態: 段階1～3の実装・検証を完了。実装は `353a22c`、AGENTS.md更新は独立した `c2392a2`。クリーンな実装コミットに対するfull profileは692件すべて合格し、 Failed=0・Incomplete=0だった。変更MATLAB 54ファイルの静的解析も指摘ゼロ。 要求ごとの証拠と最終監査は[実装・検証記録](HANDLE_APP_MIGRATION_VERIFICATION.md)を参照。

以下の段階・完了条件は実装時の計画として保持する。現在の未完了作業を表すものではない。

先行修正は `d74ae86` で完了。本体・補助クラス4か所と新規生成テンプレートから `delete` の `arguments` ブロックを除去した。例外規定は `4f1d6d0` で AGENTS.mdだけの独立コミットにした。 関連7テストクラス43件が合格（Failed=0、Incomplete=0）、変更MATLAB 7ファイルの `checkcode` 指摘ゼロ、UTF-8 BOMなし・CRLFと `git diff --check` を確認した。 これは先行修正の検証であり、転換後の検証やfull profileの合格を意味しない。

## 全体構造と目的

yamada本体と読み込み・新規生成の対象を、公開されたMATLABの機能で構成する `handle` クラス形式に統一する。`matlab.apps.AppBase`、`registerApp`、 `createCallbackFcn`、`runStartupFcn` に対する実行時・解析時の依存を取り除く。 従来のAppBase形式を並行してサポートする互換モードや、自動変換機能は作らない。

変更の中心はソース形式の認識・生成とアプリの寿命管理である。 `DocumentModel` の履歴、UIコンポーネントのモデル、プロパティ設定履歴、 配置計画、Safe Previewは既存の基盤を利用する。

## 合意したサポート契約

- `handle` を継承するMATLABクラスを対象とする。
- アプリのUIとして `uifigure` をちょうど1つ持つ。
- 他のUIコンポーネントはすべてその `uifigure` の子孫とする。 Panel、Grid Layout、Tabなどを介する入れ子を含む。
- 子孫であることは利用者が満たす前提とし、この条件のための専用検査や エラー表示は追加しない。外れる構成の正常動作は保証しない。
- ソースはyamadaが対応する静的解析可能な構文で記述する。 任意のMATLABコードを実行して継承関係・生成結果・親子関係を調べることはしない。
- ソースを `.m` ファイルとして維持する。コールバックや開いたアプリは実行しない。

標準生成は `classdef ClassName < handle` とし、既存の `app.Component` 形式を維持する。 外部の基底クラスの探索・実行や任意の変数別名の追跡を、今回の転換に含めない。 既存のモデル整合性検証と安全な編集のための所有範囲検証は維持する。 静的に認識した `uifigure` が0個または複数の場合は対象外として診断する。

## 責任分担

| 層 | 転換後の責任 |
| --- | --- |
| Parser / SourceAnalysis | handle形式の認識、コンストラクタからの初期化追跡、既存ソースの所有範囲 |
| コールバックのソース処理 | 新規登録文とメソッド雛形の生成、対応する既存登録形式の識別 |
| NewAppGenerator / RoundTripGenerator | 新規の骨格生成、既存文の局所編集・保持 |
| 部分木のソース処理 | 既存初期化文の保持・移動、新規部品の生成への共通処理の利用 |
| DocumentModel | 編集の検証、履歴の原子性、handle継承メンバーとの名前衝突判定 |
| yamada / 生成アプリ | Figureとアプリ所有リソースの寿命管理 |
| Safe Preview | 許可されたモデル値だけからUIを再構築。ユーザーコードを実行しない |

## 現在の根拠

以下は計画作成時点の実装である。行番号ではなくクラス・メソッドを追跡する。

- `AppSourceParser.findAppBaseClass` はAppBaseだけを照合する。 コールバック式の遅延実行判定にも `createCallbackFcn` の特例がある。
- `AppClassIdentityRewriter.rewrite` の宣言照合もAppBase固定である。
- `InitializationSourceAnalyzer.callTarget` は通常の同一クラス呼び出しに加え、 AppBaseのstartupラッパーと継承メソッドを特別扱いする。
- `NewAppGenerator.generate` はAppBase骨格と `registerApp` 呼び出しを生成する。
- 登録文の組み立てが `NewAppGenerator`、`CallbackSourceEdits`、 `RoundTripGenerator.additionEdits`、 `SubtreeReparentSourceEdits.generatedInitialization` の4経路に重複している。
- `DocumentModel.applyCallbackAction` が現在 `(app, event)` の雛形を組み立てる。
- `CallbackSourceAnalyzer.binding` は `createCallbackFcn(app, @Method, true)` と `@app.Method` を識別する。匿名関数の任意の本体を安全な登録と認定してはいない。
- `DocumentModel` の名前変更・Pasteの予約名にAppBaseのメンバーが使われている。
- 読み込み済み部品の親変更では、既存の設定文をソースから保持して移動する。 既存登録文を一律に再生成しているわけではない。
- コールバック付き部分木のCopyは現在拒否される。今回これを拡張しない。
- yamada本体は既に匿名関数で通常のコールバックを登録し、 `CloseRequestFcn -> closeRequest -> delete(app)` の経路を持つ。

## 実装時に確認した設計上の補足

- Figureの直接削除は `ObjectBeingDestroyed` リスナーで所有者へ伝える。 `DeleteFcn` は書き換えず、所有者が既に破棄中ならリスナーは何もしない。
- コールバックが構築途中の所有者を保持すると、コンストラクタのエラーだけでは Figureが残る場合があった。本体・生成物のコンストラクタは明示的に所有者を 削除して元の例外を投げ直す。この形だけは成功時の初期化経路として解析する。 例外を握りつぶすcatchや条件付き処理の確実性は引き上げない。
- 現行コードとROADMAPを確認したところ、`callbackSignature` と `handlerSuffix` は 独立した将来計画であり、現行runtime catalogのフィールドではなかった。 段階1のメタデータ利用は、既存のcatalogによるcallback分類と共通命名関数を維持する。 入力は現行どおり未型付けとし、新しいイベント型の推測や台帳の一括監査は行わない。
- handle継承への変更で、既存のドラッグ・リサイズ補助処理の未宣言状態が静的解析に 現れたため、使用されている8項目をprivateな型付きプロパティとして明示した。

## 段階1: ソース形式とコールバック生成の基盤

1. AppBase専用のクラス宣言判定・クラス名変更をhandle形式に置き換える。 認識できないクラスには従来どおり診断を返し、実行による補完はしない。
2. 初期化解析からAppBaseのstartupラッパー・メンバー参照を取り除く。 通常のコンストラクタから同一クラスのメソッドを辿る基盤を維持する。 コールバック登録や匿名関数の本体は初期化として実行・追跡しない。
3. `uifigure` の単一ルート判定を既存のルート検証に接続する。 子孫条件を検証するための新しい全階層監査は追加しない。
4. 新規登録文とメソッド雛形の生成を既存の `CallbackSourceEdits` に集約する。 標準形式は `app.Component.Callback = @app.Handler;` と `function Handler(app, source, event)` とする。 既存のイベント型・命名メタデータを利用し、イベント型を名前から推測しない。
5. 通常のAddと新規部品の生成4経路を共通処理に接続する。 既存文の保持・移動は文字列の局所編集として扱い、登録文を正規化し直さない。
6. 名前予約をhandleのメンバーと生成アプリの実際のメンバーに合わせる。 既存のユーザーメソッド、プロパティ、改名前後の名前も引き続き保護する。

確認項目（段階2と結合して検証）: handle形式の読み込み・新規生成・Save As・コールバックAdd/Delete・ 名前変更・新規部品を含む親変更が一貫した構文を使い、解析・生成がコールバックを実行しない。 通常の初期化呼び出し、繰り返し、再帰・動的呼び出しの診断も維持する。

## 段階2: 生成アプリと本体の寿命管理

1. 新規生成をhandle骨格に置き換え、AppBase登録とstartupラッパーを生成しない。 初期化は通常のメソッド呼び出しとし、設定完了後にFigureを表示する。
2. `CloseRequestFcn` は終了判断を担当し、終了が許可されたら `delete(app)` を呼ぶ。 `delete` はFigureとアプリ所有リソースの後始末だけを担当し、 `arguments` ブロックを持たない。構築途中や既に破棄されたUIにも耐える。
3. 生成アプリの既定の終了登録と、ユーザーが編集する `CloseRequestFcn` の関係を コールバック所有範囲に明示する。既定登録は基盤として識別し、Addでは編集用の 終了ハンドラへ置き換え、Deleteでは既定の終了登録へ戻す。 編集用の終了ハンドラの雛形には `delete(app)` を入れる。 登録を重複させたり、削除操作で終了経路を失わせたりしない。
4. `DeleteFcn` を併用する場合もユーザーのコールバックを無断で上書きしない。 Figureの直接削除から所有者を片付ける経路と、アプリ削除からFigureを片付ける 経路には再入防止を設ける。具体的な接続方法は所有範囲のテストと一緒に決める。
5. 出力変数なしの起動でもFigure側の登録がアプリを保持し、閉じた後は残留しない ことを確認する。AppBase用の `clear app` 慣習は必要性を検証して整理する。
6. yamada本体の継承先を変更する。既存の保存確認・キャンセル、タイマー停止、 ダイアログとInspectorの破棄を保持し、AppBaseに委ねていた部分だけを補う。

完了条件: 起動・通常終了・終了キャンセル・明示的なアプリ削除・Figure直接削除・ 構築失敗の各経路で、Figureや所有リソースの残留、二重解放、再帰がない。 Safe Previewにはこれらのユーザーコードを実行させない。

## 段階3: テスト資産と製品文書の移行

- プロジェクト所有の合成ソースと期待値をhandle形式へ移行する。 AppBaseの互換動作を期待するテストは残さず、対象外としての診断を確認する。
- 保存入力fixtureの原本は一括改変しない。必要なhandle形式のfixtureを別途用意し、 由来と変更内容を記録する。ユーザー出力へエディタのGPLを自動挿入しない。
- `README.md`、`SPECIFICATION.md`、UIのOpen/Save文言、クラスhelp、 `ROADMAP.md` を新契約へ揃える。過去の検証記録は当時の記録として保持する。
- `AGENTS.md` のAppBase固有の対象・生成物の記述を新契約に直す。 `delete` の例外と既存のソース保護・文字コード・ライセンス規定は維持する。 AGENTS.mdの変更は独立コミットにする。
- この計画の実装状態と検証結果を更新し、計画上の完了と実際の完了を区別する。

## 検証とコミット単位

関連するMATLAB単体テストが通ったまとまりでコミットする。 段階1と2の切り替え、およびそれに必要なテスト資産の移行は、読み込み・生成・実行が 一緒に成立する転換単位として扱う。Parserだけをhandle形式にして生成器はAppBaseのまま、 という壊れた中間状態はコミットしない。事前に分離できる共通処理の抽出や回帰テストは 独立して検証・コミットしてよい。中間コミットで全製品の転換が完了したとは扱わない。

| 検証 | 主な確認内容 |
| --- | --- |
| Parser / 初期化 | handle継承、uifigureの0/1/複数、入れ子、通常の初期化追跡、非実行 |
| 生成 / Round trip | 新規出力の実行、無編集時の原文保持、既存設定位置・全出現の保持 |
| コールバック | 標準登録、Add/Delete/rename、共有・間接参照の拒否、終了登録の復元 |
| 部分木 / 保存 | 元の登録文の保持、新規生成の共通処理、Copyの既存制限、Undo/Redo、再読込 |
| 寿命 | 出力あり/なしの起動、Closeキャンセル、明示delete、Figure直接delete、部分構築 |
| UI | 本体のNew/Open/Save As、Preview、Inspector、コールバック管理、終了確認 |

最終段階で `runYamadaTests("full")`、変更MATLABファイルの `checkcode`、 UTF-8 BOMなし・CRLF、`git diff --check` を確認する。 MATLABはAGENTS.mdどおり対話ユーザーのライセンス環境で実行する。 件数はその時点のtestsuiteから取得し、過去の件数を合格根拠に使わない。

最終監査では製品コードにAppBaseと3メソッドへの依存がないことを検索で確認する。 歴史的文書・保存fixture・対象外診断用の文字列は、実行時依存と区別して記録する。

## 今回の範囲外

- AppBase入力の継続サポートと自動変換。
- 任意の継承階層・任意のMATLAB構文・外部UIファクトリへの対応拡大。
- uifigureの子孫条件のための専用監査・診断。
- コールバック付き部分木のCopyや、ハンドラ共有・複製の新仕様。
- 保留中の部品対応、性能最適化、UIの責任分割など独立した機能変更。

## 参考となる公開仕様

- [Ways to Build Apps (R2024a)](https://www.mathworks.com/help/releases/R2024a/matlab/creating_guis/ways-to-build-matlab-guis.html)
- [Class Methods for Graphics Callbacks (R2024a)](https://www.mathworks.com/help/releases/R2024a/matlab/matlab_oop/class-methods-for-graphics-callbacks.html)
- [Handle Class Destructor (R2024a)](https://www.mathworks.com/help/releases/R2024a/matlab/matlab_oop/handle-class-destructors.html)
