# 部分木編集の実装・検証記録

対象: SUBTREE_EDITING_IMPLEMENTATION_PLAN.md

## 要件と根拠

| 計画の要件 | 実装 | 検証の根拠 |
| --- | --- | --- |
| 安定順の全子孫収集、欠損・循環・重複検出 | SubtreeSnapshot | SubtreeSnapshotTest |
| 元handleから独立した値、取得時の無変更 | SubtreeSnapshot.materialize / ComponentRecord.restoreProperties | SubtreeSnapshotTest、SubtreeDeletionTest |
| 親・construction style・root・循環の検証 | SubtreePlacementPlanner | SubtreePlacementPlannerTest、SubtreeReparentTest |
| 絶対配置・Grid間の変換、span、占有、指定セル | SubtreePlacementPlanner.prepare | SubtreePlacementPlannerTest、EditorReparentDragTest |
| 部分木の一括削除・挿入・親変更、一つの履歴 | DocumentModel.removeSubtree / pasteSubtree / reparentSubtree | SubtreeDeletionTest、SubtreeReparentTest、ComponentClipboardTest |
| 元の順序、ID、親、配置、saved checkpointの復元 | DocumentModelの構造編集履歴 | SubtreeDeletionTest、SubtreeReparentTest |
| 失敗時の文書・履歴・診断・ソース・選択・clipboard保持 | 独立candidateによる生成preflight、成功後のUI更新 | SubtreeDeletionTest、ComponentClipboardTest、SubtreeWorkflowTest、EditorReparentDragTest |
| 内部・外部・外部からの参照の区別 | SubtreeReferencePolicy、SubtreeSourceEdits | SubtreeReferenceTest、SubtreeDeletionTest、SubtreeWorkflowTest |
| 内部参照の再対応、外部参照の同一性、参照先の生成順序 | SelectedTab / ContextMenuの限定policy、遅延代入 | SubtreeReferenceTest |
| コールバック本文・未知コード保持と非実行 | 静的source分析と局所編集 | SubtreeReparentTest、CallbackDiscovery/Generation系、SubtreeWorkflowTest |
| 生成・parsed混在、親変更後の削除とPaste | SubtreeReparentSourceEdits、RoundTripGenerator | SubtreeWorkflowTest |
| 独立Copy、即時Cut、反復Paste、名前長・衝突回避 | ComponentClipboard、DocumentModel.copySubtree / pasteSubtree | ComponentClipboardTest |
| 同一文書限定と文書交換時の破棄 | ComponentClipboard.hasContents / clear、yamada.swapDocument | ComponentClipboardTest、EditorClipboardTest、既存EditorLifecycleTestの文書交換・取消・失敗の契約 |
| 共通のEdit・キー・Hierarchy右クリック | clipboardCommand / clipboardAvailability、HierarchyContextMenu | EditorClipboardTestの三入口、HierarchyContextMenuTest |
| 右クリック対象と選択の独立、空白・再構築・対象失効 | HierarchyContextMenuのdocument/ID照合とreset | HierarchyContextMenuTest、EditorClipboardTest、EditorReparentTest |
| 入力中・Tab移動後のショートカット保護 | hierarchyOwnsKeyboard、inline renameのキー所有 | EditorClipboardTest、EditorInteractionTest |
| 選択先、Inspector、Preview、診断、ソースの更新 | yamadaの成功後refresh | EditorClipboardTest、EditorReparentTest、EditorReparentDragTest、既存EditorInteractionTest |
| Hierarchyの移動先選択、不可理由、再検証とCancel | ParentSelectionDialog / reparentStates / reparentAction | ParentSelectionDialogTest、EditorReparentTest |
| Previewでの親変更、ガイド、同一親操作との区別 | ReparentOverlayDataBuilder、EditorInteractionOverlay.html | reparentGesture.test.cjs、既存overlayテスト、EditorReparentDragTest |
| Grid間のHTML実行経路、モデルまでの接続 | uihtml内DOM pointer → Reparent event → model | EditorReparentDragTest.embeddedBrowserDragTransfersBetweenGrids |
| 無効・占有・範囲外・古いdropとキャンセル | targetCell検証、モデル版番号、draft破棄 | SubtreePlacementPlannerTest、reparentGesture.test.cjs、EditorReparentDragTest |
| スクロール・入れ子の座標系 | surfaceBoundsとcanvas-local geometry、既存Grid controls | overlayCursor / nestedGridPlacement / nestedGridInteractionの各Nodeテスト、既存Grid/Preview UIテスト |
| 保存・再読込、UTF-8 BOMなし、CRLF/LF | SourceWriter / AppSourceParser | 既存SourceWriter/round-trip系、追加の実ファイル検証（下記） |
| 全体回帰と規約 | runYamadaTests("full") / ProjectConventionsTest | full: Passed=341 / Failed=0 / Incomplete=0 / Duration=699.024秒 |

## 追加の実ファイル検証

新規モデルから既存ソースを作り、解析後に Copy → Paste → 親変更 → Cut → Undo を実施した。
生成結果を一時 `.m` ファイルへ SourceWriter で書き、AppSourceParser.parseFile で再読込した。
CRLF / LF の両方で、コンポーネント数、コピー先の親、末尾の未知コードsentinel、改行規約の一致を確認した。
入力クラスはインスタンス化していない。検証用の一時ファイルは終了時に削除した。

## HTMLポインター検証の範囲

R2024aのFigure向けuitest.dragでは、この構成のuihtml内部へのpointerイベント到達を確認できなかった。
恒久テストは元HTMLの一時コピーへテスト専用リスナーを追加し、sendEventToHTMLSourceから
実iframe内DOMにpointerdown/move/upをdispatchする。実HTMLの要素ヒット判定・drag handler・
MATLABへのイベント送信・モデル変更・指定セル・一つの履歴までを確認する。
OSマウス自体の自動操作を検証したという主張はしない。
ガイドの座標・占有・キャンセル・版番号と既存overlay動作はNodeテストでも検証する。

## 対応表と境界

| 対象 | 現在の扱い |
| --- | --- |
| カタログで親適合性と生成が証明できるeditableな部分木 | 対応。construction styleと全子孫を検証 |
| UIFigure root | Copy / Cut / Delete / 親変更の対象外 |
| programmatic-only / FigureTools | Copy / 親変更の対象外。native hierarchyの全面対応は別項目 |
| literal property | encoderが対応する値を保持 |
| static SelectedTab | 直接の子Tabに限定。内部コピー先へ再対応 |
| static ContextMenu | 同じ文書root配下のContextMenu。外部対象のIDを保持 |
| その他の式・参照、未知のhandle payload | Copyを拒否。未対応の内部依存がある親変更も拒否 |
| executable callback binding | Copy / Cutを拒否。既存の所有が明確なcallbackは親変更で保持 |
| parsed移動対象への保留中callback編集 | 同時relocationは拒否。Save + Reload SourceまたはUndoが必要 |
| 外部から削除対象への参照 | 削除を拒否。親変更で書換予定のconstructor親トークンのみ除外 |
| 複数選択・別文書・OS clipboard | 初版の対象外 |

## 最終ゲート

- [x] 関連モデル・生成・UIテスト
- [x] HTML overlay Nodeテスト7本
- [x] 文字コード・改行・GPLの規約テストと追加コードの静的解析
- [x] README / SPECIFICATION / ROADMAPへの対応範囲と制限の反映
- [x] fullプロファイル341件の最終集計（341/341合格、失敗0、未完了0、699.024秒）
- [x] 最終結果の反映とGit状態の確認（実装・文書の変更はコミット済み）

## 最終実行コマンド

```matlab
addpath(pwd, fullfile(pwd, 'tests'));
results = runYamadaTests('full');
```

HTML overlayは tests 配下の7本の .test.cjs をNodeで実行し、全て合格した。
仕様上の対応範囲・後続範囲は上の対応表とSPECIFICATION.mdに記載し、計画の全段階の実装と検証を完了した。
