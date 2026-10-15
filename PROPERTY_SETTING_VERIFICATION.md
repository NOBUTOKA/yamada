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

## Stage 4: 公式資料の収集・部分監査・共通適用順序

- `dev/component-data/AuditApplicationPolicies.ps1`を追加した。
  台帳が参照するMathWorksのR2024a固定URLだけを読み、本文・出典・hash・相互作用候補を
  明示された作業キャッシュへ保存する。ページのスクリプトやサンプルコードは実行しない。
- 48/48具体variantの公式プロパティ本文を取得し、全台帳とのID照合を確認した。
- 監査状況を`dev/component-data/R2024a/APPLICATION_POLICY_AUDIT.json`へ記録した。
  候補抽出は監査判断と別にし、全variantのpolicy reviewとruntime verificationはpendingと明記した。
- キャッシュは出典URLとSHA-256が前回の収集記録に一致する場合だけ再利用する。
  同じキャッシュから48件を再抽出できることと、collectorのPowerShell構文を確認した。
- 収集時点では、実台帳の適用ルールの監査・昇格や生成順序の実行確認は完了していない。

追加実装:

- `APPLICATION_POLICY_REVIEW.json`へ、公式資料で確認したルールと推論した順序を区別して記録した。
  対象はitemSelection、Slider/KnobのLimitsとValue、Numeric Edit/Spinnerの値制約、
  DatePicker、FigureのWindowStyle、Units/Position、FontUnits/FontSize、目盛りとMode。
- GaugeのValueはLimitsの範囲外でも許され、Limits変更時にも変化しない。
  4具体variantから誤った`withinLimitsOf`制約を除去し、Sliderの制約を流用しない。
- `ApplyApplicationPolicyReview.ps1`は全ルールを検証してから台帳を更新する。
  出典のrelease・variant照合、グラフ検証、重複拒否を行い、候補抽出だけではルールを採用しない。
- `APPLICATION_POLICY_RUNTIME_REVIEW.json`へ所有fixtureの実行根拠を記録した。
  検証したプロパティに限って`nameValue=supported`とし、未検証のDatePicker等はunknownを保持する。
- 26/48具体variantに計113プロパティの適用メタデータを付与してruntimeへ昇格した。
  この件数は順序ルールに加え、実行確認した生成時指定の対応も含む。
  policy reviewは26件がpartial・22件がpending、runtime verificationは21件がpartial・27件がpending。
  partialは当該variantの全プロパティの監査完了を意味しない。
- `PropertyApplicationPlanner`は完全グラフの依存関係を実際の設定entryへ投影する。
  省略された中間ノードを経由する依存関係も維持し、準備できた独立entryは元の順序を優先する。
  Inspector順は流用せず、元entryや設定履歴を変更しない。
- 新規AppBase、新規コンポーネント挿入、親変更時の生成ノード、新規文書のPreviewを共通順序へ接続した。
  既存ソースの無編集出力は並べ替えない。
- 既存ソースのPreviewは生成時引数で構築後、既存の確実なリテラル代入を訪問順に再生する。
  最後の明示設定だけを並べ替えることで、Limitsによる補正などの既存の副作用を消さない。
  これはnative Previewにおける再生であり、Inspectorや検証器の共通実効状態resolverの完成ではない。

検証（追加）:

- 最初のplanner・native・policy・loader・baselineの43件が合格。
- 生成時引数と逐次代入の結果を比較する検証を加えた後、planner 6件、native 7件、
  GenerationTest 8件、設定履歴6件、Preview回帰2件の合計29件が合格。
  この実行の末尾のcheckcodeでは配列生成の記述を指摘され、明示的な二次元サイズへ修正した。
- native fixtureでは21具体variantを対象に、30組の名前-値引数初期化と逐次代入を比較した。
  項目と選択、既定範囲外の数値・空値、Gaugeの範囲外値、目盛りと最終auto mode、座標とフォント単位を含む。
- `verifyApplicationPolicyReview.ps1`が合格。監査結果の適用、未検証対応のunknown、
  Gaugeの例外、再適用時の同一出力、後半ルールが不正な場合の台帳無変更を確認した。
- `verifyApplicationPolicy.ps1`が合格。空の任意ポリシーも保守的な既定値に正規化する。
- grouping/promotionのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- 関連area検証の初回は、検証中にruntimeを再昇格した操作ミスでカタログの一部が欠落したため無効。
  誤りを復旧し、以後は所有作業ディレクトリへ昇格後に反映する。無効な実行を合格根拠に含めない。
  復旧後の固定カタログでは282/286件が合格し、残る4件の原因を確認した。
- 回帰期待を新しい設定契約へ合わせた。group数は315から316へ更新し、全variantのbaselineに
  Applicationの展開結果と根拠のruntime非混入の照合を追加した。
  外部参照削除fixtureはOriginalTextだけを差し替えず、追加後の本文を再解析してから編集する。
  Axes fixtureの未解決`geolimits`は、初期化範囲解析が意図的に返すwarningとして明示確認する。
- runtime再昇格で古いGaugeのstyle別輪郭が復活することを発見し、元のruntime構築メタデータを
  quarterCircle/semicircleへ修正した。昇格検証にこの保持を追加した。
- これらの修正後、固定カタログで`runYamadaTests("area", ["parser", "model", "generation", "preview"])`が
  286/286件合格（Failed=0、Incomplete=0、実測合計346.979秒）。変更対象10ファイルのcheckcodeも警告なし。
  `testResults/property-application-area-final.log`と所有作業領域のMAT結果へ記録した。
  full profileとStage 6の完了検証を代替する結果ではない。

## Stage 4追加: 独立した実効状態と編集前チェック

実装済み:

- `PropertyState`値クラスで、元の明示値、編集中の要求値、実効値の既知/不明、最後の設定ID、
  効果の原因ID、不明理由と編集可否を分けた。`PropertyEntry`や元の設定履歴を変更しない。
- `PropertyStateResolver`は初期化の訪問順に元の設定を再生し、要求値は元の設定IDの位置へ重ねる。
  新規保留設定は共通plannerの順序で適用する。既定値や暗黙変更を元の履歴へpushしない。
- 監査済み`defaultLiteral`をapplication契約へ追加し、loaderの非評価literal parserで検証する。
  空値、Inf、NaT、許可された日付リテラルも扱い、任意の関数呼び出しや式は拒否する。
- 台帳の部分監査は27具体variant・125プロパティの適用メタデータへ進んだ。
  Text EditのCharacterLimitsによる空文字化、Numeric Edit/Spinnerの条件付き空値も含む。
  Numeric Valueの一律`allowsEmpty=false`を修正し、AllowEmptyの状態をモデルとバッチ検証で確認する。
- Slider/Range Slider/Knobのclamp、数値の丸め・空値、テキストの消去、項目選択、tick modeの暗黙変更を
  有限ポリシーで解決する。自動計算されるtick配列、native寸法に依存する単位換算、
  未確定の開区間への補正は、値を捏造せず理由付きで不明とする。
- 生成時引数は一律の個別setter再生にしない。Valueのdomainは呼び出し全体で検証し、
  ModeやUnitsの引数順による効果を保持する。所有fixtureで両者の違いを観測した。
- `ModelValidator`は最後の明示リテラルを実効値と取り違えず、resolverの値と途中の不正状態を検証する。
  変更後の生成・再解析に続き、要求した各値が実際に残ることも編集前に確認する。
  元リテラルと同値の要求や、バッチ内でraw値が同じ要求も、この確認を省略しない。
- Inspectorの表示と候補トランザクションを共通実効状態へ接続した。
  例としてValue=20の後にLimits=[50 100]がある場合、表示は50、明示設定履歴は20のままとする。
  不明な効果を既定値で埋め戻さず、不明理由を表示する。
- `ComponentRecord.getProperty`の不存在を型付きemptyに統一した。空doubleを型付き引数へ渡した際に
  既定コンストラクターで架空のPropertyEntryができる問題を避ける。
- 失敗した入力の古い下書きが、後の成功・Undoでも復元されるUI問題を発見した。
  次のcommit callback前に古いエラー下書きを解除し、失敗時だけ再設定する。

検証:

- `ProbeApplicationInteractions`の固定28ケースで、R2024aの引数順序とsetterの副作用を観測した。
  実機観測をそのまま実行ポリシーへ自動昇格させず、期待値の根拠としてレビューする。
- `PropertyStateResolverTest`12件と`PropertyStateRuntimeTest`2件が合格。
  後者では同じ所有fixtureに対するnative結果とsymbolicな解決結果、全promoted seedの初期値を照合する。
- 固定slotで失われる要求の拒否、途中の不正、生成時の一括変更、原子的失敗、Undo/Redoを
  `PropertyEditTransactionTest`へ追加し、同クラス12件の合格を確認した。
- Inspectorの所有fixtureで、補正後の表示、失敗した編集の無変更、成功した編集、Undo後の再表示が合格。
  この実行の変更対象11ファイルのcheckcodeは警告なし。
- optionalなtransaction pathをhasValueで照会する場合は不存在をfalseとする。
  `PropertyTransactionTest`10件と、既存のListBox/DatePickerのInspector回帰3件が合格。
- `verifyApplicationPolicyReview.ps1`と`verifyApplicationPolicy.ps1`が合格。
  seedとtextValueのgrouping/runtime伝搬、再適用の同一性、未確認対応のunknownを含む。
- `runYamadaTests("area", ["parser", "model", "generation", "preview", "inspector"])`が
  360/360件合格（Failed=0、Incomplete=0、実測合計536.987秒）。変更20ファイルのcheckcodeも警告なし。
  `testResults/property-state-area.log`と所有作業領域のMAT結果へ記録した。
- MATLAB変更20ファイルのUTF-8 BOMなし・CRLF、125プロパティのapplicationスキーマを確認した。
  このarea結果をfull profileや未実装のStage 5/6の完了根拠にはしない。

未完了:

- ItemsData長の許容と、候補・データ編集UIの整合をまとめて修正する。
- 全variantの残る監査、Axes等の追加連動、初期化範囲・所属の明示的な保持を続ける。
- コンポーネントをまたぐ効果も監査する。R2024a RadioButton資料にはValue=1で以前の選択のValueが0となり、
  親ButtonGroupのSelectedObjectも変わるとある。Checkbox Treeも親子のCheckedNodesを補完する。
  現在のコンポーネント単位resolverだけで、これらの連動まで解決したと主張しない。
- 新規設定の依存関係付き挿入と名前-値追記、解析済み部分木の移動、保存後の位置整合を完成させる。

## 未完了の段階（更新）

- Stage 1の残り: 既存ソース挿入plannerの具体APIと全variantの監査状況表を後続実装で確定する。
- Stage 2の残り: 初期化範囲の保持と、後続resolver・plannerへのAPI接続を最終確認する。
- Stage 3の残り: 新規設定の挿入plannerの診断を編集前検証へ接続し、保存処理との整合を確認する。
- Stage 4: 全variantの残る監査、ItemsData長の契約修正、Axes等の追加効果と共通resolverの拡充。
- Stage 5: 名前-値追記、既存初期化への依存関係付き代入挿入、解析済み部分木の移動経路への接続。
- Stage 6: 保存後の再編集、全体テスト、公開仕様の更新、完了条件の監査。

この記録に部分的なテスト合格を追記しても、全体完了の扱いにはしない。
