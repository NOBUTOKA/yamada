# MatlabAppClassDesigner

`matlab.apps.AppBase` を継承したプログラム形式の MATLAB アプリクラス（`.m`）を新規作成するか、既存ファイルを読み込み、UI コンポーネントをGUI的に確認・配置・編集するためのアプリを開発するプロジェクトです。

このプロジェクト自体も、App Designerの`.mlapp`ではなく、`matlab.apps.AppBase`を継承したMATLABクラスとして実装します。

## 方針

- 空のキャンバスまたは標準テンプレートから、新しい `matlab.apps.AppBase` 継承クラスを作成できるようにする。
- 入力対象は、App Designer形式に近い `matlab.apps.AppBase` 継承クラスの `.m` ファイル。
- 入力クラスのソースコードを読み込み、UIコンポーネントとそのプロパティを解析する。
- 解析したコンポーネントを編集用のキャンバスに表示する。
- コンポーネントの追加、削除、移動、サイズ変更、主要プロパティ編集をGUIから行えるようにする。
- 編集結果は、入力クラスの構造を保ったレビュー可能な `.m` ソースコードとして出力する。
- `.mlapp`をプロジェクトの成果物や内部形式として前提にしない。

## 現時点の対象範囲

最初の対象は、次のような標準UIコンポーネントを想定します。

- `uifigure`
- `uipanel`
- `uigridlayout`
- `uilabel`
- `uibutton`
- `uieditfield`
- `uidropdown`
- `uiaxes`

ソート処理などのアプリ固有ロジックは、このプロジェクトでは扱わず、画面クラスの解析・編集・再出力を優先します。

## 関連プロジェクト

`SortVisualizer` は、ソート可視化アプリ本体のデータ構造と画面実装を検討する別プロジェクトです。本プロジェクトは、そこに限らず一般のAppBaseクラスを扱える編集基盤を目指します。

## 注意事項

MATLAB App Designerの`.mlapp`内部形式は非公開仕様です。本プロジェクトでは、特定の`.mlapp`内部構造を直接編集する方式ではなく、MATLABクラスのソースコードを入力・出力の正とします。

## ライセンス

本プロジェクトは GNU General Public License version 3 or later（`GPL-3.0-or-later`）で提供します。詳細は [LICENSE](LICENSE) を参照してください。

