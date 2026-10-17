# 設定履歴・依存関係の対応範囲

更新日: 2026-10-17

## 完了の意味

設定の全出現を保持し、既存設定を元位置・元方式で更新する。追加は依存関係と実際の初期化順で配置する。
対応する有限の効果について途中状態と最終要求値を確認し、未確認・未対応の場合は安全性を保証しない。
全variantの列挙は、全プロパティの独立性やMATLAB全体の再現を証明するものではない。
ItemsとItemsDataの長さ差、新しい設定履歴UI、参照編集UI、描画環境依存の精密計算は今回の範囲外。

## 元の完了条件との対応

| 条件 | 実装と根拠 | 残る境界 |
|---|---|---|
| 両方式の共通履歴・全出現・位置 | PropertySetting、PropertySettingHistoryTest、PropertySettingSyntaxTest | 条件分岐・反復・所有不明の設定は原文を保持して編集を制限 |
| 明示値・要求値・実効値・編集可否 | PropertyState、PropertyStateResolver、PropertyEffectBoundaryTest | 未監査の保存入力の仮定と独立確認を区別し、未展開initializerは実行しない |
| 元位置更新・依存関係付き追加 | PropertyInsertionPlannerTest、PropertyInsertionRuntimeTest | 安全な挿入区間やconstructor対応が不明なら代入または拒否 |
| 台帳からruntimeまでの契約 | verifyApplicationPolicy、verifyApplicationPolicyReview、verifyComponentLedgerSchema | 監査状況とconstructor証拠は別管理 |
| 各生成経路・Previewの共通効果 | PropertyApplicationPlanner、PropertySourcePlan、各有限policy | 生成・再解析だけで未対応のnative動作の一致を証明しない |
| 保存・Undo・部分木の整合 | SavedSourceCheckpoint、PropertySaveCheckpointTest、PropertyCopyTest、PropertyRelocationTest | 未知の実効値を必要とする操作は確定前に拒否 |
| 関連・全体・静的検証 | PROPERTY_SETTING_VERIFICATION.mdの各最終状態の記録 | 過去コミットのfullを現在の結果として流用しない |
| 公開仕様・コミット | SPECIFICATION.md、PROPERTY_SETTING_IMPLEMENTATION_PLAN.md、Git履歴 | 計画文書は削除しない |

## 全variantのプロパティ別監査一覧

正本は`dev/component-data/R2024a/APPLICATION_EFFECT_REVIEW.json`。
全1,825プロパティについて、release固定の資料、確認状況、影響先、未対応・未確認理由を列挙する。
記載の欠落、public SetAccess、既定値、constructor合格だけから独立性を付与しない。
下表の未監査は未完了の調査であり、独立性の証拠ではない。`unknown`だけでは編集を禁止せず、
確実なリテラルと既定値は保存入力が保持される前提で扱う。問題が判明した連動は個別対応する。
従来の表示対象外・読み取り専用・値検証・ソース所有権による制限は別に維持する。

| variant | プロパティ数 | 独立確認済み | 有限policy | 未対応 | 未監査 |
|---|---:|---:|---:|---:|---:|
| axes | 155 | 54 | 54 | 18 | 29 |
| geoaxes | 85 | 36 | 17 | 6 | 26 |
| polaraxes | 110 | 44 | 39 | 4 | 23 |
| uiaxes | 157 | 55 | 54 | 18 | 30 |
| uibutton-push | 31 | 21 | 4 | 2 | 4 |
| uibutton-state | 32 | 22 | 3 | 2 | 5 |
| uibuttongroup | 41 | 23 | 4 | 4 | 10 |
| uicheckbox | 27 | 17 | 3 | 2 | 5 |
| uicolorpicker | 22 | 12 | 3 | 2 | 5 |
| uicontextmenu | 12 | 6 | 0 | 2 | 4 |
| uidatepicker | 32 | 19 | 2 | 4 | 7 |
| uidropdown | 34 | 18 | 5 | 4 | 7 |
| uieditfield-numeric | 35 | 19 | 7 | 4 | 5 |
| uieditfield-text | 32 | 20 | 3 | 4 | 5 |
| uifigure | 48 | 29 | 3 | 3 | 13 |
| uigauge-circular | 35 | 18 | 8 | 4 | 5 |
| uigauge-linear | 35 | 18 | 8 | 4 | 5 |
| uigauge-ninetydegree | 36 | 19 | 8 | 4 | 5 |
| uigauge-semicircular | 36 | 19 | 7 | 5 | 5 |
| uigridlayout | 24 | 11 | 2 | 5 | 6 |
| uihtml | 21 | 9 | 3 | 4 | 5 |
| uihyperlink | 31 | 19 | 3 | 2 | 7 |
| uiimage | 26 | 15 | 3 | 2 | 6 |
| uiknob-continuous | 33 | 15 | 9 | 4 | 5 |
| uiknob-discrete | 28 | 14 | 4 | 4 | 6 |
| uilabel | 29 | 19 | 3 | 2 | 5 |
| uilamp | 19 | 9 | 3 | 2 | 5 |
| uilistbox | 33 | 17 | 5 | 4 | 7 |
| uimenu | 21 | 14 | 0 | 2 | 5 |
| uipanel | 38 | 22 | 3 | 4 | 9 |
| uipushtool | 20 | 13 | 0 | 2 | 5 |
| uiradiobutton | 26 | 16 | 4 | 2 | 4 |
| uislider-range | 36 | 18 | 9 | 4 | 5 |
| uislider-slider | 34 | 16 | 9 | 4 | 5 |
| uispinner | 37 | 21 | 7 | 4 | 5 |
| uiswitch-rocker | 29 | 15 | 3 | 5 | 6 |
| uiswitch-slider | 29 | 15 | 3 | 5 | 6 |
| uiswitch-toggle | 29 | 15 | 3 | 5 | 6 |
| uitab | 24 | 13 | 2 | 4 | 5 |
| uitabgroup | 25 | 12 | 2 | 5 | 6 |
| uitable | 53 | 34 | 3 | 4 | 12 |
| uitextarea | 31 | 21 | 3 | 2 | 5 |
| uitogglebutton | 30 | 20 | 4 | 2 | 4 |
| uitoggletool | 23 | 15 | 0 | 3 | 5 |
| uitoolbar | 15 | 8 | 0 | 2 | 5 |
| uitree-checkbox | 36 | 22 | 3 | 4 | 7 |
| uitree | 35 | 22 | 3 | 3 | 7 |
| uitreenode | 15 | 7 | 0 | 2 | 6 |
| 合計 | 1825 | 936 | 328 | 193 | 368 |

## 残作業の扱い

- 基盤の再実装を残作業に数えない。新しい効果は同じ契約・生成候補・保存・Copyの経路へ追加する。
- RadioButton/ToggleButtonの選択は親と兄弟を含めて扱い、単体の最後のValueだけから推定しない。
- Axesの縦横比・カメラ、非単純な位置getter、GeoAxesの未確認TickDirは明示した境界の中で未知とする。
- メニュー・ツール・TreeNodeの監査は、保存値、描画の優先順位、callback実行を分ける。Preview描画の新設を必須にしない。
- 未確認プロパティの追加対応は個別の根拠と所有fixtureを伴う。監査表の未知状態を一括して確認済みに変えない。

## 契約と証拠の境界

- `none`は効果処理を選ばないことだけを表し、独立性の確認ではない。旧catalogは読み込めるが、status省略時は`unknown`とする。
- `unsupported`と`unknown`は監査の影響先と理由を保持する。`unknown`の確実なリテラルは通常編集でき、他の状態を無条件には未知にしない。未対応効果または未監査の不確実なソース設定では、空の影響先は同じcomponentの全状態を対象にする。
- 非空の生成時CreateFcn、未展開initializer、未知のsetter、未対応のParent/Children設定は文書単位の保証を停止する。通常の匿名callback登録は実行と区別する。
- 親の位置設定が子の確定した位置より後にある場合は、AutoResizeChildrenが明示offでない限り子の幾何情報を未知とする。子の描画位置を計算するものではない。
- RadioButton/ToggleButtonは同種の兄弟と親SelectedObjectを生成順に再生する。新規生成・複製は兄弟生成後にValueを設定し、既存のValueは元の場所で更新する。
- sliderの固定厚さと一部knob/gaugeの正方形補正は所有fixtureで確認した有限規則。装飾や描画に依存するInnerPosition/OuterPositionとの同一性は推定しない。
- 旧監査集計の部分42・保留6はレビュー資料の進捗であり、48variantの実装件数やnative監査完了数ではない。

新規部分木の生成anchorは、確実な初期化の実行順と既存の親の位置設定を共有して決める。
親のPosition初期化前に子を作り、後のresizeで要求位置を失う配置を避ける。
同じinitializer内に安全な位置を証明できない場合は追加を拒否する。

- 未対応効果または未監査の不確実なソース設定が上流にある場合、後続の連動setterだけで影響が解消したとは推定しない。後続の独立確認済みsetterによる自身の保存値の復元は区別する。
- 引数がappでない不明な明示呼び出しも独立とは推定しない。許可する純粋なデータ生成呼び出しは、限定した標準関数と不活性なリテラル引数に限る。
- Push ButtonのContextMenuは所有fixtureで保存値への限定した影響を確認し、既存の参照コピーを維持した。未確認の他variantへ同じ結果を推定しない。
- ToggleTool.StateはFigure種別と準備状態によってcallbackの観測が異なるため未対応とする。HTMLの外部実行を含む場合も文書の実効状態を既知にしない。

## 方針改訂前の全体検証（2026-10-17）

実装`b7307f6`のfull 571件が全件合格し、関連area 526件の包含・合格も照合した。
変更MATLAB 37ファイルは静的解析警告ゼロ、台帳のPowerShell検証3本が合格した。
完了条件は本書の有限の対応範囲と未対応境界に対して満たした。
各実行の区別、所有fixture、失敗からの修正、commit/hashは
[検証記録](PROPERTY_SETTING_VERIFICATION.md)を参照。

## unknown編集方針の改訂と検証（2026-10-17）

実装`92b47fd`で、`unknown`だけを理由にした編集禁止を解除した。
監査分類は維持し、製品上の表示対象外・読み取り専用、式、不確実な設定、既知の未対応連動は別に扱う。
Inspectorの既定値と関連値も同じ条件へそろえた。Switch各種・半円ゲージのPositionは対応保留。
関連142件と実UI 4件が合格し、追加278件を合わせてquick全416件の包含・合格を確認した。
重複除外総数424件、変更MATLAB 8ファイルの静的解析警告ゼロ、台帳検証3本合格。
fullの再実行は行っていない。詳細と試行の区別は[検証記録](PROPERTY_SETTING_VERIFICATION.md)を参照。
