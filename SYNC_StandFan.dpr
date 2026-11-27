
library SYNC_StandFan;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2 の DLL 境界。初期化、終了、最低対応バージョン、登録テーブルを公開する。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  StandFan_Mesh in 'Source\Common\StandFan_Mesh.pas',
  StandFan_Model in 'Source\Common\StandFan_Model.pas',
  StandFan_Renderer in 'Source\Common\StandFan_Renderer.pas',
  SYNC_StandFan_FilterPlugin in 'Source\Plugin\Filter\SYNC_StandFan_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  if Version < STANDFAN_REQUIRED_VERSION then Exit;
  try
    SetFanHostVersion(Version);
    GetFanFilterTable;
    PrepareFanRenderer;
    Result := 1;
  except
    ReleaseFanRenderer;
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  ReleaseFanRenderer;
end;

function RequiredVersion: Cardinal; cdecl;
begin
  Result := STANDFAN_REQUIRED_VERSION;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetFanFilterTable;
  except
    // DLL 境界の外へ Delphi 例外を伝播させない。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
