# 設定履歴・設定依存関係 実装・検証記録

更新日: 2026-10-16

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
  ただし、2026-10-16のユーザー指示により、この相違への対応は今回の対象外とする。

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

- ItemsData長の許容と、候補・データ編集UIの整合は将来の検討事項とする。
  2026-10-16のユーザー指示により、今回の未完了項目から除外した。
- 全variantの残る監査、Axes等の追加連動、初期化範囲・所属の明示的な保持を続ける。
- コンポーネントをまたぐ効果も監査する。R2024a RadioButton資料にはValue=1で以前の選択のValueが0となり、
  親ButtonGroupのSelectedObjectも変わるとある。Checkbox Treeも親子のCheckedNodesを補完する。
  現在のコンポーネント単位resolverだけで、これらの連動まで解決したと主張しない。
- 新規設定の依存関係付き挿入と名前-値追記、解析済み部分木の移動、保存後の位置整合を完成させる。

## Stage 5: 依存関係付き挿入・名前-値追加・共有配置

実装済み（2026-10-16）:

- `PropertySetting`へOwnerMethod・ScopeSpan・InitializationScopeIdを追加し、snapshotへ保持する。
  初期化traceはhelper呼び出しから戻る訪問位置も返し、物理的なファイル順と実行順を分離する。
- `PropertyInsertionPlanner`は既存設定を移動せず、新規設定を安定した依存順で計画する。
  必要な設定より後の候補を、観測される読み取り・不明な処理等の境界までに限定する。
  既存の直列helperへの挿入、反復helperの最後の一意な呼び出し箇所も扱う。
- 各候補は要求された既存値の変更も含めた別の本文へ適用し、再解析と実効状態で検証する。
  正規順だけを強制せず、例えばValueの後のLimitsでclampする合法な候補も確認する。
- 名前-値のみの初期化では、監査済みnameValue対応と依存関係を満たす新規設定を同じ呼び出しへ追加する。
  位置引数だけの呼び出しは同方式と推定せず、混在・未確認対応は生成後代入を使う。
- `FactoryCallEditor`は既存の値・式・コメント・区切りを再構築しない。
  `Name=value`、単一/二重引用符の名前-値ペア、複数行と継続行へトークン挿入する。
  同offsetの追加を結合し、依存順が逆転しないようにする。
- RoundTripGenerator、モデルの実効状態・編集前検証、既存要素のPreviewを同じ挿入計画へ接続した。
  元の設定IDと原文の履歴は維持し、候補だけのSourceSpanを元の編集対象として再利用しない。
  この時点では親変更中のparsed要素を既存のrelocation emitterが所有していた。後述の移動経路で統合する。

検証:

- 初期の挿入12件・初期化scope 10件・構文7件・設定履歴6件の合計35件が合格。
  checkcodeが指摘したscalar判定を`isscalar`へ修正した。
- 追加後の再編集、原子的拒否、Undo/Redoを含むplanner 15件、既存編集12件、RoundTrip 9件、
  親変更9件の合計45件が合格。
- 不透明な引数式の非評価保持1件とnative検証2件が合格。
  nativeではテストが作ったAppBaseクラスだけを実行し、既存3方式×追加2種の6ケース、
  コメント・継続行を持つ呼び出しの構文と、同じ配置を使うPreviewとの一致を確認した。
  この実行の変更13ファイルのcheckcodeも警告なし。
- parser/model/generation/preview/inspectorの378件では377件が合格し、非scalarなstring配列を入力する
  既存の非実行テストで追加判定のscalar条件の問題を発見した。
  この入力を編集配置の対象とせず、従来の解析・非実行確認を維持するよう修正した。
- helper内とconstructor内のreturnで現在のframeだけを終了し、条件付きreturn以降の現在メソッドを
  不確実にする。呼び出し側の不確実性とcalleeの無条件returnを取り違えないよう、専用ケースを追加した。
- 上記の入力形状の修正後、parser 12件・scope 13件・挿入16件・native 2件・callback 6件の
  合計49件が合格。さらに条件付き呼び出し内の無条件returnのケースを加え、関連382件が全件合格。
  Failed=0、Incomplete=0、実測合計482.576秒。変更14ファイルのcheckcodeも警告なし。
  `testResults/property-insertion-area-final.log`と所有作業領域のMAT結果へ記録した。

- helperの無条件returnを不透明な処理境界と誤認しないよう修正し、呼び出し元で続く初期化への挿入を検証した。
  挿入17件・scope 14件・native 2件の合計33件が合格（Failed=0、Incomplete=0）。
  追加変更2ファイルのcheckcodeも警告なし。MATLAB変更14ファイルのUTF-8 BOMなし・CRLFを確認した。

### parsed部分木の移動経路（2026-10-16）

- 所有範囲を最後のPropertyEntryだけから集めず、元の全設定出現から集めて重複を除く。
  createComponents内の一意かつ確実な実行訪問を要求し、反復初期化の所有範囲を移動しない。
- 元の生成呼び出しと代入文を保持し、要求変更はSourceSettingIdが指す値トークンだけへ適用する。
  名前-値設定を代入文として重複出力せず、過去の代入も落とさない。
- 元の文順を安定した順序として、所有者と親の生成に必要な制約を満たす順に配置する。
  移動要素間の交差する代入順、行末コメント、Figureの最終Visible設定を保持する。
- Gridへ移す際に不要になる生成時Position等は、FactoryCallEditorのコードトークン削除で除去する。
  引数内の改行、継続記号、コメントを残し、新しいLayout設定を共通plannerへ渡す。
- 移動ブロックを含む独立した候補ソースを再解析し、保留中のliteral設定を
  PropertyInsertionPlannerで配置する。挿入が移動ブロックを越える場合は拒否する。
  初期化途中の制約違反を直すLimitsも、単純な末尾追加ではなく合法な位置へ挿入する。
- PropertySourcePlanを実効状態resolverとPreviewの共通入口にした。
  元の設定ID・SourceSpanを変更せず、移動後の候補の実効値だけを元の明示設定・編集要求へ対応付ける。
- 設定が空のparsed親コンテナで、空のOrigin配列とstringを比較してPreviewが失敗する問題も修正した。

検証:

- 新しいPropertyRelocationTestは、混在履歴、既存値の再編集とUndo/Redo、反復初期化の拒否、
  保留Value、名前-値方式の保持、途中状態を修復するLimits、Gridへの変換、交差する文順、
  最終Visible、未評価式の非実行保持の10件を含む。
- 既存のSubtreeReparentTest 9件が合格。新しい契約テストの初期失敗は、所有fixtureの絶対配置引数と
  元の設定ID比較（移動が追加するPositionの保留設定を除外）を修正して解消した。
- PropertyInsertionRuntimeTestに移動の実機比較を追加した。テスト自身が作ったAppBaseクラスのみを実行し、
  既存3方式とGrid移動の4ケースで選択値・親子関係・Grid配置をPreviewと比較して合格した。
  Position値の内部にも継続行とコメントを入れ、引数除去後のMATLAB構文を確認した。
- 変更8ファイルのcheckcodeは警告なし。UTF-8 BOMなし・CRLFも確認した。
- parser/model/generation/preview/inspectorの関連area 394件が全件合格。
  Failed=0、Incomplete=0、実測合計515.954秒。
  `testResults/property-relocation-area.log`と所有作業領域のMAT結果へ記録した。
  この結果は、残る台帳監査やCopy/Paste・保存checkpoint・full profileの完了根拠にはしない。

### Copy/Pasteの実効設定計画（2026-10-16）

- SubtreeSnapshotの元Recordsは変更せず、独立したCopyConfigurationを保持する。
  SubtreeCopyPlannerは凍結した元レコードを共通resolverへ渡し、コピー時点の実効値を計画する。
  原文のValue=20が後続Limitsで50となるケースでも、元履歴20を残し、複製先の明示値は50とする。
- 元の名前-値引数は、位置情報に対応する引数indexからコピー用の生成引数列から除く。
  numeric/state/discrete/range等の位置引数を残し、値設定は共通plannerによる生成後代入に一本化する。
- 元に明示設定がないValueやModeも、確認済みsetter効果で決まる値は複製先の新しい設定として保持する。
  元コンポーネントの設定履歴へ暗黙値をpushしない。貼り付け先は新しいcomponent/setting IDを作り、
  SourceSpan・SourceSettingIdを元の編集先として引き継がない。
- auto目盛配列の実効値は不明のままとする。最後のliteral入力とautoモードを出力することで、
  描画前の値と描画後の自動計算の両方を保持し、計算済み配列を推測して明示設定にしない。
- 自動モードで説明できない不明な実効値は、理由を付けてCopyを拒否する。
  通常のCopyは設定計画も凍結し、原本や以前の複製を後から編集しても内容を変えない。
  未準備のsnapshotを直接Pasteする経路も凍結レコードを使い、異なるsource版の位置情報を拒否する。
- Pasteは候補ソースを再解析し、配置変更を除く全既知期待値を比較してから原子的に適用する。
  参照値は既存のSubtreeReferencePolicyで新IDへ対応付ける。
- 汎用factory定義で名前-値引数を一度解析した後、位置引数から具体variantを選び、
  variantが変わる場合は具体surfaceで再解析する。numeric専用RoundFractionalValues等を未知式へ落とさない。

検証:

- 既存のSubtreeSnapshot 6件・ComponentClipboard 13件・SubtreeWorkflow 6件、計25件が合格。
- 新しいPropertyCopyTest 10件が合格。補正値、両名前-値構文、ItemsData変更後の選択、numericの丸め、
  state/discrete/range、暗黙Value、新ID・空SourceSpan、Undo/Redo、コピーの凍結、auto目盛、不明値の拒否を含む。
  variant追加で見つかったcell値の期待値struct展開も修正した。
- parser 12件・設定構文7件を含む初期27件が合格。参照6件と実機比較を含む15件も合格。
- テスト自身が作った4つのAppBaseクラスのみを実行し、Sliderのclamp、Dropdownのdomain変更、
  NumericEditFieldの丸め、Sliderのauto目盛で、元と複製の実効値およびPreviewが一致した。
  autoへの変更直後に直前の配列が残る実機結果を受け、配列を削除する初期案を修正した。
  描画前後の一致を確認し、Sliderの所有fixtureは固定の高さ3で検証した。
- 変更6ファイルのcheckcodeは警告なし。UTF-8 BOMなし・CRLFも確認した。
- parser/model/generation/preview/inspectorの関連area 405件が全件合格。
  Failed=0、Incomplete=0、実測合計546.160秒。
  `testResults/property-copy-area.log`と所有作業領域のMAT結果へ記録した。
  この結果は、残る台帳監査・保存checkpoint・full profileの完了根拠にはしない。

残作業:

- 保存後の再編集と位置整合、全variantの残る監査を完了する。
- コンポーネント間の選択連動等は、共通resolver側の監査・実装に従ってCopy計画にも反映する。
  現在のコピー検証で、未監査setterの効果まで解決したとは扱わない。
- 未監査の公式資料では、表示だけの依存（ImageのScaleMethodと整列、LabelのInterpreterとfont等）と、
  setterで保存値を変える連動を区別する必要がある。PositionとInnerPosition/OuterPositionの同値記述も、
  読み取り専用・alias・相互代入の範囲を分けて確認する。資料候補の共起だけから順序辺を追加しない。

## Stage 6追加: 保存側の位置と編集基準の分離（2026-10-16）

実装済み:

- `SavedSourceCheckpoint`は、`SourceWriter.normalize`と共通の正規化後の出力を非実行で再解析する。
  コンポーネント集合・親子関係と、共通resolverが既知とする実効値を保存前に照合する。
  未知の自動計算値や任意式は評価・補完しない。
- 値オブジェクトのsnapshotへ保存側の全設定履歴と新しい位置・source版を保持し、
  `ComponentMap`で編集側の安定IDと対応付ける。返されたsnapshotからのmaterializeも独立する。
- `DocumentModel.confirmSavedSource`は、書き込み成功後にだけ保存checkpoint・class名・pathと
  saved history位置を更新する。書き込みの間に変更意図が変わった場合は確定を拒否する。
  原子的な確定前に、独立した候補文書で生成結果も再照合する。
- 元の`OriginalText`、設定ID、SourceSpan、変更意図、Undo/Redo履歴は維持する。
  保存出力の新しい位置を元の編集基準へ混ぜない。再読込は新文書へ置き換える既存境界を使う。
- 保存前の生成も独立した候補文書で行い、失敗した生成・書き込みで実文書の生成結果や診断を上書きしない。
  既存のDiff Previewでは従来どおり生成結果を更新する。

検証:

- `PropertySaveCheckpointTest` 9件が合格。両名前-値構文、過去の代入、保留設定、再読込後の編集、
  複数保存をまたぐUndo/Redo、移動・複製・削除、未知式の保持、古いcheckpoint拒否を含む。
- 所有一時ファイルで、Save As後のclass名、Unicode、LF正規化、UTF-8 BOMなしの実バイトと
  再解析したValueSpanを照合した。部分木生成時の改行混在も、保存時の正規化後の位置で扱う。
- 最後の明示Valueが20でLimits変更後の実効値が50となるケースでは、保存出力の明示値20を維持し、
  再解析後の実効値50を確認した。auto tickの計算値は未知のまま保持する。
- `EditorLifecycleTest`に、実メニューでのSave As・Undo/Redo・連続保存・再読込後の再編集と、
  2回目の書き込み失敗時にcheckpoint・履歴・要求値・生成結果・診断・ファイルを維持するテストを追加した。
  追加した2件を含むライフサイクル全13件が合格。
- MATLAB変更6ファイルのcheckcodeは警告なし。UTF-8 BOMなし・CRLF、`git diff --check`も確認した。
- 計画指定のparser/catalog/model/generation/preview/inspector/lifecycleの関連area 427件が全件合格。
  Failed=0、Incomplete=0、実測合計799.248秒。
  `testResults/property-save-area.log`と`testResults/property-save-area-results.mat`へ記録した。
  既存の所有fixtureによる生成・適用順序の実行テストもこのareaに含まれる。
  この結果は、残る台帳監査・full profile・計画全体の完了根拠にはしない。

残作業:

- 全variantの残る台帳監査と共通効果の拡充を継続する。
- 残る資料監査では候補抽出だけに依存しない。RadioButtonのValue節には、0への変更で別のRadioButtonが
  選択されることと、初回追加順がChildren順と一致するとは限らないことが記載されているが、
  現在の候補抽出にはこの段落が現れない。CheckBoxTreeの親子CheckedNodes補完も本文で照合する。
  いずれも収集済みR2024aの対応プロパティページが根拠であり、共通resolverへの反映はまだ未完了。
- Button・Checkbox・Hyperlink・Label・Lamp等のPositionとInnerPosition/OuterPositionの別名関係は、
  既存台帳のomitted/readOnly分類を含めて監査する。ColorPickerではOuterPositionも指定可能と記載されている。
  また、ToggleToolのState節にはOnCallback/OffCallbackの実行が記載されており、
  ユーザー操作時だけのcallbackと区別する。これらを表示上の依存だけとして処理しない。
- 全体のfull profileと、公開仕様・各完了条件の最終監査は未完了。

## Stage 4追加: Axesの確認済み値・Mode連動（2026-10-16）

根拠と範囲:

- R2024aの[Axes](https://www.mathworks.com/help/releases/R2024a/matlab/ref/matlab.graphics.axis.axes-properties.html)、
  [UIAxes](https://www.mathworks.com/help/releases/R2024a/matlab/ref/matlab.ui.control.uiaxes-properties.html)、
  [PolarAxes](https://www.mathworks.com/help/releases/R2024a/matlab/ref/matlab.graphics.axis.polaraxes-properties.html)、
  [GeographicAxes](https://www.mathworks.com/help/releases/R2024a/matlab/ref/matlab.graphics.axis.geographicaxes-properties.html)
  の対応する値・Mode節を照合した。収集済みsource/hashと、補足の所有fixtureを分けて保持する。
- 49組はFontSize、CLim/ALim、Cartesian/Polarの目盛・ラベル・回転・範囲、対応するTickDir、
  PolarのRAxisLocation、GeographicのMapCenter/ZoomLevelを対象とする。
  canonicalの値→Mode順は推論として記録し、既存ソースの並べ替えの根拠にしない。
- `ProbeAxisModeInteractions`は非表示の所有axesだけで88組を調べ、getter、Mode、両constructor順を記録する。
  地理データのタイルを要求しないようBasemapはnoneとし、開いた入力アプリやユーザーcallbackは実行しない。
  49組の適用ポリシーでは、setterのmanual化・値の一致・constructor順とcanonical順を確認済み。

実装済み:

- 任意のMode接尾辞へ一般化せず、監査済みプロパティにだけ`valueMode`を付与する。
  開発schema・正規化・grouping/hash・runtime・loaderへ同じ許可識別子を伝搬した。
- 値のsetterで対応Modeを暗黙にmanualとする。autoモードまたは未評価のMode式は、
  再計算され得る値を未知とする。Infを含む自動端点の入力も解決済み実効値として扱わない。
  暗黙Modeを新しい明示設定やUndo履歴として追加しない。
- 新規生成と新規名前-値追記は最終Modeを値の後へ置く。既存Modeが値より先にある場合は、
  元位置の変更で実現できない要求を拒否し、後勝ちの代入や設定の移動で隠さない。
- Copyはauto値の最後の明示入力とModeを保持し、計算済みgetter値の一致を主張しない。
  保存側の再解析でも入力とModeを残し、値の未知状態を維持する。
- 部分監査は27具体variant・219プロパティの適用メタデータへ進んだ。
  policy reviewは27 partial / 21 pending、runtime reviewは22 partial / 26 pendingであり、全variant監査は未完了。

検証:

- `axisValueModesAreOrderedAndPreserved`が49組のnative setter・constructor・canonical順を検証して合格。
  `APPLICATION_POLICY_RUNTIME_REVIEW.json`は、この実行結果から確認したpathだけへ生成時対応を付与する。
- `AxisModeSourceTest` 5件が合格。両名前-値構文、assignment追加、元位置を維持する拒否、
  Copy時の新IDと未知値、保存側の位置・明示入力を含む。
- `verifyApplicationPolicyReview.ps1`と`verifyApplicationPolicy.ps1`が合格。
  未確認の地理TickDirへの一般化を拒否し、依存辺・Mode seed・constructor根拠・再適用・昇格の再現性を確認した。
- groupingのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- 変更MATLABファイル7件のcheckcodeは警告なし。UTF-8 BOMなし・CRLFと`git diff --check`も確認した。
- 計画指定のparser/catalog/model/generation/preview/inspector/lifecycleの関連area 436件が全件合格。
  Failed=0、Incomplete=0、実測合計841.323秒。
  `testResults/axis-mode-area.log`と`testResults/axis-mode-area-results.mat`へ記録した。
  この結果は、未監査ポリシー、full profile、計画全体の完了根拠にはしない。

残る監査対象:

- 色Modeは表示色の決定と保存getterの変更を区別する。対応する色・alphaのModeを一括でvalueModeにしない。
- manualなPlotBoxAspectRatioも、手動limitsとDataAspectRatioを併用するとgetterが補正される。
  カメラ・縦横比、LineWidth→GridLineWidth→MinorGridLineWidthのmode依存追従は別途実装する。
- GeographicAxesのTickDirは、資料の既定Mode manualと所有Basemap=none fixtureのautoが一致せず、
  out指定直後のgetterもinとなるため保留した。他variantのTickDir規則を流用しない。
- 残る台帳監査・コンポーネント間効果・full profile・計画全体の完了監査は未完了。

## Stage 4追加: 描画Modeと線幅の条件付き追従（2026-10-16）

根拠と範囲:

- 上記R2024aの4種類の公式プロパティ資料を根拠に、色・alphaの22組を`modeFlag`へ分けた。
  保存getterと描画色・透明度の選択を混同せず、autoへの復帰で保存値を計算し直したと扱わない。
- Axes/UIAxesのLineWidth、GridLineWidth、MinorGridLineWidthと2つのModeを`axisWidth`で扱う。
  公式資料はautoでの上流追従とmanualでの保持、値の指定でmanualになることを記載している。
- 資料だけで判断できなかった生成時引数は所有fixtureで補足した。
  `GridLineWidth=4, MinorGridLineWidthMode=manual`は、引数順を逆にしてもminor幅が初期値0.5となる。
  constructorは各値とModeの指定後に追従値を同期し、代入文を順に実行する場合とは異なる。
  これを一般的なgetterの再計算や全コンポーネントの生成規則へ拡張しない。

実装済み:

- 両ポリシーを開発schema・正規化・grouping/hash・runtime・loaderへ伝搬した。
  部分監査の適用メタデータは27具体variant・273プロパティとなった。
  全variantのpolicy/runtime reviewは引き続きpartial/pendingを維持する。
- 線幅はautoなら既知の上流値を追従し、manualなら直前のgetterを保持する。
  不明なMode・上流値は理由付き未知状態として伝搬し、明示的な受け側の指定で復帰できる。
  保持した既定値にも原因ModeのIDを対応付けるが、元ソースの明示設定を増やさない。
- 名前-値引数では値・Modeだけを順に反映し、引数全体の後に追従値を同期する。
  生成後代入は各setterの直後に追従する。元の引数・代入順は変更しない。
- 新規の上流線幅を挿入する際、元ソースにあるmanual保持指定より後の位置を選ぶ。
  生成時指定が確認できる場合は同じconstructor内でも保持点を越えて追記し、書式を維持する。
- Copyでは暗黙のauto追従幅を明示代入してmanualへ変えてしまうことを避ける。
  一方、constructorで手動保持された既定値はコピー側へ明示し、代入方式への変換後も同じ値を再現する。
  再解析後の既知値を照合し、元の設定履歴・位置・IDは維持する。

検証:

- 所有native fixtureで色Mode 22組のgetter保持・render後の値・両constructor順・canonical順を確認した。
  Axes/UIAxesでは各13ステップのsetterを共通resolverと逐次照合し、既定値・manual保持・auto復帰、
  5プロパティのcanonical constructorと手動保持の両constructor順も確認した。
- 専用の関連52件が合格。実効値の元位置編集、名前-値追加、保持点の後への代入追加、
  constructorの同期、Copy、保存、Undo/Redo、不明なModeと上流の扱いを含む。
- `verifyApplicationPolicyReview.ps1`と`verifyApplicationPolicy.ps1`が合格。
  2つのポリシーの伝搬、Modeの依存辺、0.5 seed、constructor根拠、再適用・昇格の再現性を確認した。
- groupingのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- 変更MATLABファイル7件のcheckcodeは警告なし。UTF-8 BOMなし・CRLFと`git diff --check`も確認した。
- 計画指定のparser/catalog/model/generation/preview/inspector/lifecycleの関連area 449件が全件合格。
  Failed=0、Incomplete=0、実測合計872.395秒。
  `testResults/axis-render-area.log`と`testResults/axis-render-area-results.mat`へ記録した。
  この結果は、未監査の効果、full profile、計画全体の完了根拠にはしない。

残作業:

- 縦横比・カメラ・地理TickDirの残る監査と、コンポーネント間の選択連動等を続ける。
- 残る全variantの監査、full profile、計画全体の完了条件の監査は未完了。

## 位置setterのアクセス観測とCheckbox Treeの修正（2026-10-16）

根拠:

- R2024a固定の14具体variantの位置節は、InnerPosition/OuterPositionのgetterとPositionの同一性を記載する。
  例: [Checkbox Tree Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.container.checkboxtree-properties.html)、
  [Lamp Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.lamp-properties.html)。
  これはgetterの関係であり、setter可否や別名同士を独立に扱えることの根拠にはしない。
- 所有fixtureはpush/state/toggle Button、Checkbox、ColorPicker、HTML、Hyperlink、Image、Label、Lamp、
  RadioButton、TextArea、Tree、Checkbox Treeを対象とし、外部HTML・画像・アプリ・callbackを実行しない。
  各3プロパティについてmeta.property SetAccessと直接代入を独立に確認した。
- 公開setter 28ケースは受理され、OuterPositionの14ケースはrestrictedかつ
  `MATLAB:class:SetProhibited`で拒否された。受理された28ケースはdrawnow後の3 getterが一致し、
  Positionと別名の両constructor順でも最後の指定が反映された。
- [ColorPicker Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.colorpicker-properties.html)の
  OuterPositionにはspecifiedという記載があるが、native setterはrestrictedだった。
  原文を変更せず、観測を別の根拠として保持する。
- Lampの補足観測では、初期20×20から80×20、20×80を指定しても20×20のままで警告された。
  35×130は35×35、80×80は80×80、130×35は35×35となった。
  これらの例は指定幅・高さの小さい側への補正と一致するが、一般的な補正policyはまだ導入していない。

実装済み:

- runtime reviewに独立した`setterAccess`観測を追加した。再適用時は全件を検証してから書き込み、
  不合格・不明access・重複target・documentedReadOnlyとの衝突を拒否する。
  setter観測だけではconstructor supportを付与せず、documentation policy reviewも完了扱いにしない。
- 詳細なruntimeObservationsは開発台帳だけに保持し、groupingからruntimeへはアクセス区分を伝搬した。
  Checkbox TreeのPosition/InnerPositionをunresolvedからpublicへ、OuterPositionをrestrictedへ修正した。
  Positionは従来のnumericVector編集、InnerPosition/OuterPositionは従来どおりInspectorでomittedとする。
- Checkbox Treeの既存Position/InnerPositionを往復時に保持し、既存Positionの値トークンだけを更新する。
  代入文、Name=Value、'Name',Valueの3形式を回帰検証した。設定IDと方式を保持し、再解析後も値が一致する。
- application policyは27具体variant・273プロパティのまま。policy reviewはpartial 27/pending 21、
  native runtime verificationはpartial 36/pending 12となる。アクセス観測を全propertyの監査完了とは扱わない。

検証:

- nativeアクセスの専用1件と、その後の関連5 suite・56件が全件合格。
  Failed=0、Incomplete=0、関連suiteの実測合計120.473秒。
  `testResults/position-access-native.log`と`testResults/position-access-focused-results.mat`へ記録した。
- `verifyApplicationPolicyReview.ps1`が、再適用の再現性、観測の隔離、不正な観測・constructor指定の
  原子的な拒否を確認した。新しいアクセス区分・観測42件も実際のschemaの該当部分との照合に合格した。
  `verifyApplicationPolicy.ps1`のapplication schema・grouping・昇格の検証も合格した。
- groupingのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- 変更MATLABファイル4件のcheckcodeは警告なし。Lampの補足観測は
  `testResults/lamp-position-constraint.json`へ記録した。そこでのnative警告は無視せず上記の制約として記録する。
- 計画指定の関連area 452件が全件合格。Failed=0、Incomplete=0、実測合計856.848秒。
  `testResults/position-access-area.log`と`testResults/position-access-area-results.mat`へ記録した。
- 全台帳をschema.jsonと照合する追加監査では、今回の変更前からの不整合により48文書が不合格だった。
  クラス名リスト602項目の単一文字列化、Axes/UIAxesのまとめ見出し64項目の空summaryを確認した。
  さらに、既存の`deferredComponentReference` reason codeとListBoxの`multiselectProperty`がschemaに未収録だった。
  前記PowerShellテストのschema合格はapplication契約の範囲であり、台帳全体のschema合格を意味しない。
  `testResults/ledger-schema-audit.json`へ記録した。カタログ固定中のarea実行には変更を加えていない。

残作業:

- 同一alias groupの最後のsetterを実効値・原因設定IDへ反映する共通policyを追加する。
  未評価の別名式は全getterを未知とし、後続の確実なリテラルで復帰させる必要がある。
- Previewのskip対象別名を単に無視せず、共有した既知のPositionへ投影する。
- Copyでは別名をPositionへ集約し、配置offsetが後から別名で上書きされることを防ぐ。
  `SubtreePlacementPlanner`が生のPositionを読む経路と、placement changesを照合から除外する経路も確認する。
- Grid配下のlayout-managed geometry、Lampの補正、残るコンポーネント間の効果、全variant監査、
  full profile、計画全体の完了条件監査は引き続き未完了。
- 上記の台帳serialization・summary・schemaの不整合は、次節の変更で是正した。

## 全文書のschema検証と台帳の是正（2026-10-16）

根拠と変更:

- [Axes Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.graphics.axis.axes-properties.html)と
  [UIAxes Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.uiaxes-properties.html)の
  X/Y/Zを併記する16種の公式見出しを確認した。各ページでX/Y側の32項目、合計64項目の空summaryを補完した。
  Z側の説明と同じ公式見出しに基づく転記であり、プロパティ名から新しい契約や効果を推定しない。
- `valueContract.matlabClasses`の単一文字列602項目を、既存schemaどおり要素1個の配列へ揃えた。
  受理するクラス名は変更していない。変更前の48文書との意味比較でも、この配列化とsummary補完以外の
  フィールドに差がないことを確認した。ItemsDataの長さに関する既存契約は変更しない。
- 既存95項目が使用する`deferredComponentReference` reason codeと、ListBoxの既存契約
  `multiselectProperty`をschemaへ収録した。任意のreasonや未定義フィールドを許可する変更ではない。
- `ComponentLedger.ps1`へ、全concrete文書をschemaで検証する共通preflightを追加した。
  台帳ポリシー適用、grouping artifact生成、grouping design生成、runtime昇格の4入口は、
  最初の出力書き込みより前に呼び出す。従来のapplication graph・source・parity検証も維持する。
- runtimeの受理クラスはもともと配列へ正規化されており、設定効果の動作は変えない。
  補完した64項目の説明はruntime定義へ伝搬し、全プロパティの説明と受理クラス集合を既存baselineで照合する。

検証:

- 48文書・1825プロパティを含む全concrete文書がschema検証に合格した。
- `verifyComponentLedgerSchema.ps1`は、全台帳の再適用・再生成の再現性と公式見出しのruntime伝搬を確認した。
  クラスの単一文字列化、空summary、未知reason、peer pathの型違い、未知policy field、不正JSONを
  4入口それぞれへ入力し、計24ケースで文脈付きの拒否と、書き込み前後の全ファイルhashの一致を確認した。
- `verifyApplicationPolicyReview.ps1`と`verifyApplicationPolicy.ps1`も合格した。
  これらの入口でも、従来のpolicy部分検証に加えて全文書のschema検証を実行する。
- groupingのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- MATLABで追加したクラス集合の照合は、初回に並び順まで一致させて失敗した。
  runtimeが集合をソートする既存契約に合わせて修正し、再実行で合格した。初回の記録は
  `testResults/ledger-schema-focused-initial.log`へ保持した。
- MATLABの関連39件が全件合格。Failed=0、Incomplete=0、実測合計45.930秒。
  `testResults/ledger-schema-focused.log`と`testResults/ledger-schema-focused-results.mat`へ記録した。
  変更したMATLABテスト1ファイルのcheckcodeは警告なし。UTF-8 BOMなし・CRLFと
  `git diff --check`も確認した。実行時の適用契約が不変であることは上記の全48文書の差分で確認している。

未完了:

- このschema合格は、全propertyの依存関係監査や全計画の完了を示さない。
  位置の別名効果・Lamp補正・その他の残る効果、全variant監査、full profile、完了条件監査は継続する。

## 位置別名の実効値・Preview・複製（2026-10-16）

根拠:

- R2024a固定の[Button Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.button-properties.html)など、
  先行する14具体variantの位置節の監査に基づく。Position/InnerPositionは公開setter、
  OuterPositionは同じ値を返す読み取り専用getterとして区別する。
- [Lamp Properties](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.lamp-properties.html)は
  幅と高さの独立変更を制限する。小さい側を採る補正は資料から断定せず、所有native fixtureで補足した。
- 14種類×6ケースの追加観測で、ゼロ・小数を保持し、負のサイズを拒否することを確認した。
  Lampのゼロ・小数も同じ正方形補正に従う。結果は`testResults/position-alias-boundaries.json`へ記録した。
  native座標には約1 ulpの丸め差があり、native比較だけに1e-12 pixelの許容を使う。
  ソース値や一般的な値比較を丸めたり、全プロパティの比較を緩めたりはしない。

実装済み:

- `positionAlias`を13種類、`squarePositionAlias`をLampへ適用した。42プロパティのpolicyを
  schema・grouping・runtime・loaderへ通し、公開28プロパティのconstructor指定も確認して対応を記録した。
  部分監査は41具体variant・315プロパティ。policy reviewはpartial 41/pending 7であり、完了扱いにはしない。
- `PositionAliasPolicy`は最後の公開setterの値と原因設定IDを全getterへ投影する。
  明示値・設定場所・ID・方式はそのまま保持する。未知の別名式はグループを未知にし、後の確実なリテラルで復帰する。
  Grid管理下の別名はリテラルがあってもgeometryの根拠にせず、layout-managedの理由を返す。
- 既存Positionが後の別名に上書きされる場合、元位置で要求を満たせない編集を原子的に拒否する。
  Positionを新規追加する場合は、代入形式と両名前-値構文で候補ソースを検証し、要求が残る位置を選ぶ。
- Previewでは既知のPositionを1回投影し、未知の場合は診断を出す。
  解析済みconstructorのskipプロパティはnative生成前に除外し、元ソース・生成時引数の所有記録は変更しない。
  名前-値のImageSourceはconstructorへ直接渡さず、代入と同じローカルアセット処理で適用する。
- Copyの元snapshotは全出現を保持し、独立したコピー設定だけを1つの実効Positionへ集約する。
  配置plannerはその凍結値を使い、再解析後はoffsetを含む配置変更も照合する。
  Gridでは無効な別名をコピー設定から除き、Grid座標または渡された実測geometryを使う。
- 親変更は元の別名文を保持し、必要なPositionを配置する。Undo/Redoでも元の履歴と生成結果を維持する。

検証:

- nativeの公開setter 28ケース・読み取り専用14ケースと、両constructor順を共通resolverと照合して合格した。
  さらに84ケースの境界比較も合格した。`testResults/position-alias-native-results.mat`へ記録した。
- 実装中に、親別surfaceが列ベクトルになる経路で反映処理が配列の向きを仮定していた不具合を検出し、
  向きを揃えて修正した。その後、挿入・複製・親変更・resolverの関連67件が全件合格した。
- Previewを含む追加の25件が全件合格した。所有sentinelでCreateFcn/DeleteFcnが生成・破棄のいずれでも
  実行されないこと、HTMLSourceがPreview引数から除かれること、名前-値画像が既存adapterを通ることを確認した。
  `testResults/position-alias-focused-results.mat`と`testResults/position-alias-preview-results.mat`へ記録した。
- `verifyApplicationPolicyReview.ps1`、`verifyApplicationPolicy.ps1`、`verifyComponentLedgerSchema.ps1`が合格。
  台帳全48文書のschema検証、再適用・昇格の再現性、readonly aliasへのconstructor対応の不付与を含む。
- groupingのintrinsic parityは48/48、parent-effective parityは144/144で合格。
- 関連area 465件が全件合格した。Failed=0、Incomplete=0、実測合計906.987秒。
  `testResults/position-alias-area.log`へ記録した。これ以降に下記の仕上げを加えたため、最終状態の根拠は
  仕上げ後の専用テストとfull profileで区別して記録する。
- 仕上げでは、解析済みの位置別名をPreviewのconstructorからも除き、解決済みPositionの投影と二重適用しない。
  また、コピーの既知ゼロサイズを配置とModelValidatorで同じ条件に揃えた。ゼロを拒否していた既存の
  不正geometry fixtureは、nativeでも拒否される負の幅へ変更し、不正geometryの検出契約を保った。
- 追加ケースで、親変更の配置要求が後続別名に上書きされても移動が確定されることを検出した。
  生成ソースの再解析後に配置要求の既知実効値を照合し、確定前に原子的に拒否する処理を追加した。
- 仕上げ後のモデル・配置・親変更・Previewの関連76件は全件合格した。
  Failed=0、Incomplete=0、実測合計136.399秒。`testResults/position-alias-final-focused-results.mat`へ記録した。
- 変更MATLABファイル13件のcheckcodeは警告なし。初回full profileは512件中511件が合格し、
  テスト選択契約のUI総数固定値136と、現在の160件との不一致だけが失敗した。
  quickの対象集合と限定UI smokeの2つの照合は合格していた。
- full UIの増加とquickのUI startup制限を混同しないよう、総数の固定値を除いた。
  quickが全non-UIテストと指定UI smokeだけを含む契約は維持する。
  初回fullの記録を`testResults/position-alias-full-initial.log`へ保存した。
- 選択契約3件の再実行が合格した後、最終状態のfull profile 512件が全件合格した。
  Failed=0、Incomplete=0、実測合計1327.060秒。
  `testResults/position-alias-full.log`と`testResults/position-alias-full-results.mat`へ記録した。
  最終の変更MATLABファイル14件のcheckcode、UTF-8 BOMなし・CRLF、`git diff --check`も合格した。

残作業:

- この14種類の規則を、OuterPositionが装飾を含むSlider/Knob/Switchや、Container/Axesへ自動的に広げない。
- 未着手7種類はContextMenu、GridLayout、Menu、PushTool、ToggleTool、Toolbar、TreeNode。
  [GridLayout資料](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.container.gridlayout-properties.html)には
  occupied tracksによるRowHeight/ColumnWidth保持、[ToggleTool資料](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.container.toolbar.toggletool-properties.html)にはStateによるcallback実行がある。
  このほか、
  Icon/CDataやMenu.Checkedの描画上の優先・無効条件がある。順序依存と描画条件を分けて監査する。
- Axesの縦横比・カメラ・地理TickDir、コンポーネント間の選択効果などの残る監査・実装を続ける。
- この時点のfull profileは合格した。全variantの残る監査・効果の実装と、最終状態での完了条件監査は未完了。
  ItemsDataの長さ差は引き続き対象外とする。

## GridLayoutのtrackと子の配置（2026-10-16）

根拠:

- [GridLayout Properties（R2024a）](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.container.gridlayout-properties.html)
  のRowHeight/ColumnWidthは、track数と子の占有状態の関係を明記している。
  既存の子を配置したまま占有中の行・列を削ることはできない。`fit`は内容に応じたサイズ指定であり、
  保存されるtokenと実測pixel値を区別する。
- [uigridlayout（R2024a）](https://www.mathworks.com/help/releases/r2024a/matlab/ref/uigridlayout.html)
  は既定の2×2、位置引数のサイズ、名前-値引数、左から右・上から下の既定配置を説明している。
- `ProbeGridLayoutInteractions`の所有する非表示fixture 32ケースが例外なしで完了した。
  補足観測は`testResults/grid-layout-probe.json`と同logに保存した。
  占有に足りないtrackは`1x`で補完され、子を移すと暗黙の補完分が解除される。
  先行する空きセルがあっても、次の子は現在の最後の占有セルの後へ配置される。
  この補完値と穴埋めをしない挙動は、資料だけから決めずnative観測で補った。

実装:

- RowHeight/ColumnWidthへ`gridTracks`と資料由来の既定値を追加した。
  パーサは名前-値引数のない生成も含め、initializer実行順の生成sequenceと確実性を記録する。
- `GridLayoutStatePolicy`が明示したtrackの基準値と、子の生成・Layout.Row/Columnを再生する。
  実効track・暗黙配置はsource occurrenceを作らず返し、未評価の配置は該当状態を未知にする。
- 追加した配置が後続の暗黙配置へ与える影響も、共通の挿入plannerの候補で解決する。
  新規子の生成は生成器と同じ最後のparsed生成spanへ配置する。
  複数のpending設定は`PropertySourcePlan.combined`で全体候補を生成・再解析し、
  モデル・Copy・Preview・オーバーレイが同じ結果を参照する。生成中の一時候補だけは保守的に未知とし、
  部分的な候補や末尾へ適用した結果を最終状態として返さない。
- Previewは既知の実効track・子の配置を投影し、Copyは暗黙配置と補完済みtrackも凍結する。
  グリッド編集オーバーレイとtrack変更操作も同じ実効値を使い、明示listが短い場合の補完trackを表示・編集する。
  `fit`のpixel値、未評価式、入力アプリの実行はこのpolicyの対象外。
- 単一property編集とparsed grid batchは、生成・再解析した結果で要求値が残ることを確かめる。
  trackのセル配列が複数のhistoryレコードに展開される既存不具合も修正し、Undo/Redoを確認する。

検証状況:

- native constructor契約1件が合格した。cell/numeric/stringのtrack指定と占有補正の解除を含む。
  `testResults/grid-layout-native-contract-results.mat`へ保存した。
- 初期接続後の関連53件が全件合格した。Failed=0、Incomplete=0、実測合計96.188秒。
  `testResults/grid-layout-final-focused-results.mat`へ保存した。生成順序の追加確認はこの後に行う。
- 台帳の再適用・昇格・schema検証のPowerShell 3本が合格した。
  groupingのintrinsic parity 48/48、parent-effective parity 144/144が合格した。
- 台帳の部分監査は42 variant、保留6 variant。policy対象propertyは317。
  runtime部分検証は37 variant、保留11 variant。全体の完了を意味しない。
- 追加の生成順序・挿入planner・テスト選択契約34件が全件合格した。
  `testResults/grid-layout-source-order-results.mat`へ保存した。Failed=0、Incomplete=0、実測合計67.515秒。
- オーバーレイを含む専用回帰23件が全件合格した。
  `testResults/grid-layout-overlay-focused-results.mat`へ保存した。Failed=0、Incomplete=0、実測合計79.460秒。
- 複数のpending設定と保存checkpointを加えた専用15件はFailed=0、Incomplete=0だった。
  同じ起動の静的解析でテスト名がMATLABの63文字上限を超えたため、名前を短縮した。
- 全体候補への接続前のarea 483件は、複数設定直後のCopy・Previewを補完するため中断した。
  `testResults/grid-layout-area-before-combined.log`へ保存し、合格の根拠には含めない。
- 補完後の専用16件が全件合格した。Failed=0、Incomplete=0、実測合計59.464秒。
  `testResults/grid-layout-combined-final-results.mat`へ保存した。複数設定直後のCopy・Preview・
  オーバーレイ・保存checkpoint・Undoを含む。
- 次のareaで、GridLayout用の比較が同名のUITable.ColumnWidthへ誤適用される不具合を検出した。
  `testResults/grid-layout-area-before-table-fix.log`へ保存し、修正のため中断した。
  `PropertyState.EffectPolicy`で台帳の`gridTracks`に限定し、通常のtable schemaの比較を維持した。
- 修正後のGridLayout・プロパティ編集・オーバーレイ38件が全件合格した。
  Failed=0、Incomplete=0、実測合計109.335秒。`testResults/grid-layout-table-fix-results.mat`へ保存した。
  同じColumnWidthでも台帳のpolicyが異なればtrack用の表現変換を適用しないことを確認した。
- 最終状態の変更MATLAB 14ファイルはcheckcode警告なし。
  計画指定の関連area 485件が全件合格した。Failed=0、Incomplete=0、実測合計1004.248秒。
  `testResults/grid-layout-area.log`と`testResults/grid-layout-area-results.mat`へ保存した。
- area後の仕上げとして、生成モデルのlegacy constructor引数は、他の生成後設定が存在しても
  track初期値として読むよう条件を補完した。位置引数サイズと名前-値override、Padding代入を混在させ、
  新規生成・再解析・保存checkpointの一致を確認する回帰を追加した。
  この補完後の生成・保存・GridLayout回帰35件が全件合格した。
  Failed=0、Incomplete=0、実測合計97.026秒。
  `testResults/grid-layout-generated-final-results.mat`と同logへ保存した。
  仕上げの2ファイルもcheckcode警告なし。前段のareaと仕上げ後の専用検証を区別して記録する。
- 変更MATLAB 14ファイルのUTF-8・BOMなし・CRLFと、`git diff --check`を確認した。
  ItemsとItemsDataの長さ差は引き続き対象外。
  残るvariant・効果の監査と、最終状態での全完了条件の監査は継続する。

## 対象範囲の変更（2026-10-16）

- ItemsとItemsDataの長さが異なる場合の対応は、データ編集UIの大きな変更を伴うため、
  ユーザーの指示により今回は扱わない。着手した未コミット変更4ファイルはすべて戻した。
- 既存の`sameLengthAs`契約、検証、選択候補、データ編集UIを維持する。
  長さ不一致への対応は今回の完了条件に含めず、ほかの台帳監査と実装を継続する。
- 復元先は`a7ab303`であり、その実装は上記の関連area 405件で検証済み。
  今回は対象範囲を記録する文書のみを変更し、MATLABの動作変更は加えていない。

## 未完了の段階（更新）

- Stage 1: 共通契約と`PropertyInsertionPlanner.plan(document, component, registry)`は実装済み。
  全variantの監査状況は`dev/component-data/R2024a/APPLICATION_POLICY_AUDIT.json`で管理する。
  残りは保留variantと部分監査variantの未確認property・効果の監査。
- Stage 2: 設定履歴、initializerの実行順・確実性、生成イベントをresolver・plannerへ接続済み。
  最終監査では、未対応構文を含む所有・未知状態・原文保持の境界を再確認する。
- Stage 3: 挿入診断・編集前候補検証・保存checkpointは実装・専用検証済み。
  複数pending planの全体候補への接続と、未対応の効果を未知とする境界を完了条件の監査に含める。
- Stage 4: 保留6 variant・部分監査42 variantの残る監査、Axes等の追加効果と共通resolverの拡充。
  ItemsData長の契約修正は今回の対象外。
- Stage 5: 独立した設定snapshot・実効copy計画・保存checkpointは実装・回帰検証済み。
  残る共通効果ポリシーを加えるたび、複製・移動・保存への反映を確認する。
- Stage 6: 全体テスト、公開仕様と完了条件の最終監査。

この記録に部分的なテスト合格を追記しても、全体完了の扱いにはしない。
