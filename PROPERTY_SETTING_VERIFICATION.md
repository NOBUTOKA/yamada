# 設定履歴・設定依存関係 実装・検証記録

更新日: 2026-10-15

全体状態: 実装中。計画全体の完了条件は未達成。
対象計画: [PROPERTY_SETTING_IMPLEMENTATION_PLAN.md](PROPERTY_SETTING_IMPLEMENTATION_PLAN.md)

## Stage 1: 台帳ポリシーの共通契約

実装済み:

- `PropertyApplicationPolicy`の型付き契約。設定順序、生成時指定の対応、効果ポリシーを分離した。
- `PropertyDefinition.Application`とruntime loaderの任意フィールド対応。
- 展開後の未知依存先、重複、自己参照、循環、許可された親のsurfaceで消える依存先を拒否する。
- 親surfaceへの追加は既存のintrinsicプロパティを重複させず、そのメタデータを保持する。
- 開発schemaの`application`と開発専用`applicationEvidence`。
- groupingのcapability比較・hashとruntime昇格へのポリシー伝搬。
- 許可ポリシーの監査規則と、旧カタログの保守的な既定状態。

検証:

- MATLAB R2024aで`PropertyApplicationPolicyTest` 4件、`ComponentCatalogLoaderTest` 11件、
  `ComponentRegistryBaselineTest` 16件が合格。旧runtimeカタログ48具体variantの読み込みを含む。
- `TestSelectionContractTest` 3件が合格。変更したMATLABファイル6件のcheckcodeは警告なし。
- `tests/verifyApplicationPolicy.ps1`が合格。独立した一時台帳へ候補ポリシーを挿入し、
  不正データ拒否、applicationスキーマ、grouping両段階、runtime昇格、根拠の分離、
  同じ入力の再昇格で同じ出力になることを検証した。実台帳・runtime生成物は変更しない。
- 新規ポリシーは、この段階では実台帳へ監査結果として付与していない。
  effectPolicyの識別子は契約を定義した段階であり、実際の効果resolverの完成を意味しない。

発見事項:

- 既存の開発Dropdown台帳のItemsDataでは`valueContract.matlabClasses`が配列ではなく
  単一文字列で、既存schemaと一致していない。Stage 4の全台帳監査で整合性を確認する。
  Stage 1のschema検証は新しいapplication契約を対象にしており、台帳全体の適合を主張しない。
- 同台帳のItemsDataの`sameLengthAs`は、公式資料の長さ不一致時の動作と照合して、
  MATLABの制約と製品独自の制約を区別する必要がある。

## 設定モデルの移行対象

2026-10-15の利用箇所を調査した。生成時引数とPropertyEntryを別々に変更する経路を、
共通記録の登録とその投影へ移行する。

| 責務 | 主な移行対象 |
|---|---|
| モデル・状態 | PropertyEntry、ComponentRecord、DocumentModel、NewAppFactory |
| registry・文脈 | ComponentRegistry、ComponentDefinition、ParentContextRule |
| 解析・生成 | AppSourceParser、NewAppGenerator、RoundTripGenerator |
| 部分木と参照 | SubtreeSnapshot、SubtreeSourceEdits、SubtreeReparentSourceEdits、SubtreeReferencePolicy |
| 配置とクリップボード | GridChildPlacementPlanner、GridLayoutStructuralEditPlanner、SubtreePlacementPlanner、ComponentClipboard |
| 値の検証・表示 | ModelValidator、PropertyBatchValidator、DefaultValueProvider、InspectorValueFormatter、InspectorView |
| Preview・保存 | PreviewRenderer、DocumentLifecycleService、yamadaの保存後文書更新 |

## Stage 2: 共通設定履歴と位置付き解析

実装済み:

- `PropertySetting`値クラスと、`ComponentRecord.Settings` / `getSettings`の型付き出現履歴。
  元の値・式、設定方式、構文、文/名前/値/引数ペアの範囲、ソース版、実行訪問順、確実性を保持する。
- `PropertyEntry`は最後の明示設定の編集用投影となり、編集中の要求値で元の設定レコードを書き換えない。
- `CreationArguments`は設定履歴と要求値から投影する互換APIとし、解析後の別経路による変更を拒否する。
- 字句解析の`CodeOffsets`を使用し、コメント除去・継続行処理後も元の値トークンの位置を保持する。
- `PropertySettingSyntax`で`"Name", value`、`'Name', value`、`Name=value`、ドット代入を解析する。
  式・未知引数・同一キーの重複も失わず保持する。
- 現在の初期化呼び出し順の解析を再利用し、条件分岐内・条件付き呼び出しの設定を不確実として保持する。
  同じ直列helperの反復呼び出しは訪問順を保持する。ファイルの物理順を実行順と同一視しない。
- 既存の名前-値引数と代入の値更新は元の値範囲だけに限定する。無編集時の値内コメントも保持する。
- SubtreeSnapshotで元の設定履歴を独立した値として保存・復元する。
  削除では最後の設定だけでなく全出現を所有範囲に含め、共有する生成文を重複削除しない。
- 外側が引用符でも内部に未エスケープの引用符がある連結式は、リテラルと判定しない。

検証:

- MATLAB R2024aの`runYamadaTests("area", ["parser", "model", "generation"])`が
  250/250件合格（Failed=0、Incomplete=0）。実測合計時間273.305秒。
- その後の追加変更を含む`PropertySettingSyntaxTest` 7件、`PropertySettingHistoryTest` 6件、
  `LexicalParsingTest` 8件、`TestSelectionContractTest` 3件の合計24件が合格。
- 設定履歴関連15ファイルのcheckcodeが警告なし。追加変更を含む4ファイルの再確認も警告なし。
  両チェックを合わせた対象は16種類のMATLABファイル。
- 上記のareaは既存のCopy/Cut/Paste、親変更、モデル・生成器・Inspectorのsmoke回帰を含むが、
  名前-値引数を持つ部分木の全移動ケースや保存後の位置再設定まで完了した根拠ではない。

後続の必須作業:

- 新規設定の保留意図、編集前の設定ID固定、依存関係付きの原子的preflightを完成させる。
- 名前-値引数の追加、既存初期化への依存関係付き挿入、全生成/移動経路の共通化。
- 最後の明示設定と、他setterにより変わる実効状態の共通resolver。
- 保存・再読込後のソース版とUndo/Redoの整合、全variant監査とruntime適用ポリシーの実データ整備。

## 未完了の段階

## Stage 3: 編集前検証・保留設定・履歴

実装済み:

- 未生成の新規設定にも`PropertySetting`を作成し、元ソース位置を与えず、安定した保留設定IDを保持する。
  同じ設定を編集しても出現を増やさず、元の設定値と要求値を分離する。
- 単体・バッチ変更の履歴に対象設定IDを固定し、異なる出現に結び直された履歴の再適用を拒否する。
- 同値の単体・バッチ要求で不要な履歴やdirty変更を作らない。
- registry付きのモデル編集では、独立した候補状態で生成・再解析し、要求した各リテラルが残ることを確認してから適用する。
  InspectorとPreviewの位置編集をこの経路へ接続した。
- parserのソース版と本文を保持し、位置情報だけを残してOriginalTextを差し替えた場合は生成を拒否する。
- Reset/Undoと親変更の状態復元に、元の設定履歴と保留値の結び付きを含めた。

検証:

- 初期の`PropertyEditTransactionTest`・設定履歴・モデル・親変更・値トランザクションの合計61件が合格。
- UI回帰で、UITable.ColumnWidthへGrid専用検証が適用される問題と、
  rootのみの文書で空の子配列の向きによりスナップショットが失敗する問題を発見した。
  factoryによる検証の区別、空配列の向きに依存しない階層照合を追加した。
- 修正後の`PropertyEditTransactionTest` 7件と、上記に対応するEditorInteractionTest 2件の合計9件が合格。
- 変更MATLABファイル9件のcheckcodeが警告なし。

依存関係付きの挿入位置決定と、setterの暗黙変更を含む途中/最終状態の検証はStage 4以降で接続する。
現時点のpreflightは生成・再解析・リテラル保持の検証であり、その完了を代替しない。

## 未完了の段階（更新）

- Stage 1の残り: 設定レコード・resolver・plannerの具体APIと全variantの監査状況表を、後続実装で確定する。
- Stage 2の残り: 初期化範囲の保持と、後続resolver・plannerへのAPI接続を最終確認する。
- Stage 3の残り: 依存関係付きplannerの診断を編集前検証へ接続し、保存処理との整合を確認する。
- Stage 4: 公式資料に基づく全variant監査、実台帳の更新、実効状態と適用計画。
- Stage 5: 名前-値追記、依存関係付き代入挿入、全生成経路とPreviewへの接続。
- Stage 6: 保存後の再編集、全体テスト、公開仕様の更新、完了条件の監査。

この記録に部分的なテスト合格を追記しても、全体完了の扱いにはしない。
