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

## 未完了の段階

- Stage 1の残り: 設定レコード・resolver・plannerの具体APIと全variantの監査状況表を、後続実装で確定する。
- Stage 2: 共通の設定出現・位置付き解析・既存APIへの投影。
- Stage 3: 元位置での更新、変更意図、原子的履歴とスナップショット。
- Stage 4: 公式資料に基づく全variant監査、実台帳の更新、実効状態と適用計画。
- Stage 5: 名前-値追記、依存関係付き代入挿入、全生成経路とPreviewへの接続。
- Stage 6: 保存後の再編集、全体テスト、公開仕様の更新、完了条件の監査。

この記録に部分的なテスト合格を追記しても、全体完了の扱いにはしない。
