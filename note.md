
# SYNC_StandFan 作業ノート

## プロジェクト

- Delphi のプロジェクト名は SYNC_StandFan、登録名は「扇風機」、グループは「SYNC」。本番は Win64 の SYNC_StandFan.auf2 1本。
- プロジェクト構成、ビルド、フィルターテーブルの登録処理は SYNC_WeatherFX を継承する。法線付きポリゴンの送出、カメラと標準描画の取り扱い、SDK 宣言は SYNC_Book を参考にした。
- 第1弾は昭和レトロ調の静止モデル。位置・拡大率・回転は AviUtl2 標準の「描画」を使う。プラグイン独自の項目は登録しない。

## ビルド

Delphi 37.0 / Win64。IDE では SYNC_StandFan.dproj を開く。プロジェクトルートで Debug、Release の順にビルドし、警告・エラーと AUF2 の更新を確認する。

~~~powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_StandFan.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_StandFan.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
~~~

- Debug / Release 共通の出力先は C:\ProgramData\aviutl2\Plugin\SYNC_StandFan。ビルド後イベントで DLL を AUF2 にコピーし、成功後に DLL を削除する。Release では RSM も削除する。
- DCU は Win64\Debug\DCU / Win64\Release\DCU。デバッガーホストは両構成とも D:\aviutl2_v2.1.16\aviutl2.exe。
- ユニット追加時は .dpr の in と .dproj の DCCReference を揃える。外部から参照を更新した場合は IDE でプロジェクトを開き直す。
- 通常のビルドと検査はコマンドラインで実施する。本番 AUF2 を検査用 EXE から読み込み、アプリ内の表示確認と区別して記録する。IDE と AviUtl2 の画面操作はユーザーが依頼した場合に行う。

## ソース構成と共通の作業規則

- SYNC_StandFan.dpr は DLL の公開関数。Source/Plugin/Filter はオブジェクト登録と描画コールバックを担当する。
- StandFan_Model.pas は台座・支柱、首振り支点を持つヘッド、回転軸を持つ羽根の3部品を生成する。StandFan_Mesh.pas はメッシュの組み立て、StandFan_Renderer.pas は DrawPoly への送出を担当する。
- 日本語を含む .pas・.dpr・Windows PowerShell 用 .ps1 は UTF-8 BOM 付きの CRLF。ユニット先頭に目的と責務を記し、公開処理には入出力、必要に応じて副作用と所有権を記す。1ユニットは約1,500行を目安に責務で分ける。
- SDK の型の順序・サイズ・配置は公式定義と照合する。ホスト所有ポインターをコールバックの外へ保持せず、DLL 境界で Delphi 例外を処理する。
- コピー元プロジェクト、既存の AUP2、他のプラグインは作業対象外とする。

## Setup

Setup は SYNC_WeatherFX のフォルダーをそのままコピーした。収録されているスクリプト、カタログ、ZIP は WeatherFX 用。

AviUtl2 カタログの共通ルールとして、概要は表示文字列で35文字以内。タグは既存表記を優先する。配布物は製品専用フォルダーにまとめ、導入と削除はそのフォルダーを単位とする。

## 2026-11-27 第1弾の検査

- Delphi 37.0 で Win64 Debug / Release を Rebuild し、両構成とも警告0・エラー0。最終配置は Release の SYNC_StandFan.auf2（1,666,048 バイト）。配置先の SHA-256 は 6570977AAC482A005F62B6CB907D8B51C42691758F3258BA43BEF9B1F318D1E4。
- Win64/Verification の検査 EXE が両構成の本番 AUF2 をロード。メディアオブジェクト登録、2.1.16 と 2.1.17 以降のカメラ判定、標準回転時の奥行き順、法線と表裏の向き、頂点データの一致を確認した。
- 本体は 19,216 三角形を DrawPoly 5回で送る。カメラ対象外で毎フレーム回転させたときの Release の CPU 処理は模擬ホストで約3.4 ms/回。実際の GPU 描画と再生時間は計測対象外。
- [6方向の外観プレビュー](Win64/Verification/StandFan_Views.png) は本番 AUF2 の送出頂点を別途描画したもの。AviUtl2 内の表示と再生負荷は未確認。
- Setup の5ファイルは ZIP を含めてコピー元と SHA-256 が一致した。

## 2026-11-27 羽根の輪郭調整

- 追加写真を参照し、細い根元、幅広い先端の弧、内側へ切れ込む縁を持つ非対称形状に調整した。羽根は3枚。羽根の枚数はモデル内部の定数で、設定項目の追加は次段階。
- Win64 Debug / Release とも警告0・エラー0。実際の AUF2 を読み込む検査で両構成の頂点が一致し、羽根以外の頂点は前版と一致した。羽根とガードの間隔も確認した。全体で20,464三角形、DrawPoly 5回。
- 起動中の AviUtl2 を維持したまま配置先のファイルを更新した。次回起動時に新しい AUF2 が読み込まれる。更新版の AviUtl2 内の描画は未確認。
- 配置済み AUF2 は 1,660,416 バイト。SHA-256 は 09CF4135434EE9E1BB4535B98284EF516F462D26902335B89891CF3EE24F3DC5。
