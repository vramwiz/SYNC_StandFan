
# SYNC_StandFan の配布 ZIP

make_release_zip.bat は、指定した SYNC_StandFan.auf2 を同梱する SYNC_StandFan.zip を作成します。同じ AUF2 の XXH3-128 を SYNC_StandFan.catalog.json に記録します。

標準の AUF2 参照先は C:\ProgramData\aviutl2\Plugin\SYNC_StandFan です。別の場所を使う場合は -ReleaseDirectory でフォルダーを指定します。xxhsum.exe は PATH、Win64\Dependencies\xxHash-0.8.4\xxhsum.exe、または -XxhsumPath で指定します。[xxHash v0.8.4](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)

~~~bat
Setup\make_release_zip.bat
Setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_StandFan" -XxhsumPath "D:\Tools\xxhsum.exe"
~~~

ZIP の最上位は SYNC_StandFan フォルダーです。AUF2、利用者向け README、4機種の一覧画像、ライセンスを収録します。カタログは SYNC_StandFan フォルダーを単位に導入・削除します。

GitHub Releases には SYNC_StandFan.zip と SYNC_StandFan.catalog.json を添付します。
