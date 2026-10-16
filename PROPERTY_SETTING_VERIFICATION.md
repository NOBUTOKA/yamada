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

## 対象範囲の変更（2026-10-16）

- ItemsとItemsDataの長さが異なる場合の対応は、データ編集UIの大きな変更を伴うため、
  ユーザーの指示により今回は扱わない。着手した未コミット変更4ファイルはすべて戻した。
- 既存の`sameLengthAs`契約、検証、選択候補、データ編集UIを維持する。
  長さ不一致への対応は今回の完了条件に含めず、ほかの台帳監査と実装を継続する。
- 復元先は`a7ab303`であり、その実装は上記の関連area 405件で検証済み。
  今回は対象範囲を記録する文書のみを変更し、MATLABの動作変更は加えていない。

## 未完了の段階（更新）

- Stage 1の残り: 既存ソース挿入plannerの具体APIと全variantの監査状況表を後続実装で確定する。
- Stage 2の残り: 初期化範囲の保持と、後続resolver・plannerへのAPI接続を最終確認する。
- Stage 3の残り: 新規設定の挿入plannerの診断・編集前検証・保存処理の接続を最終監査する。
- Stage 4: 全variantの残る監査、Axes等の追加効果と共通resolverの拡充。
  ItemsData長の契約修正は今回の対象外。
- Stage 5: 複製経路の回帰確認と、残る共通効果ポリシーの反映。
- Stage 6: 全体テスト、公開仕様と完了条件の最終監査。

この記録に部分的なテスト合格を追記しても、全体完了の扱いにはしない。
