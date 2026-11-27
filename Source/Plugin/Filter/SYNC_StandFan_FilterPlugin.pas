
unit SYNC_StandFan_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 「扇風機」をメディアオブジェクトとして登録する。オブジェクト専用設定は持たない。

interface

uses
  AviUtl2FilterTypes;

const
  STANDFAN_REQUIRED_VERSION = 2011600;

// ホストのバージョンを保持する。DLL の初期化中だけ呼ぶ。
procedure SetFanHostVersion(Version: Cardinal);
// DLL 所有の登録テーブルを返す。ホストからは解放しない。
function GetFanFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils, Winapi.Windows, StandFan_Renderer, PluginFilterTable;

var
  TableRegistered: Boolean;
  CameraAPIAvailable: Boolean;

procedure SetFanHostVersion(Version: Cardinal);
begin
  CameraAPIAvailable := Version >= 2011700;
end;

function FanProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0;
  if (Video = nil) or (Video^.Object_ = nil) then Exit;
  try
    DrawFan(Video, CameraAPIAvailable);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_StandFan render: '+E.Message));
  end;
end;

function GetFanFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableRegistered then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT,
      '扇風機','SYNC','扇風機 / SYNC_StandFan 第1弾 試作',FanProcVideo,nil);
    TableRegistered := True;
  end;
  Result := GetPluginTable;
end;

end.
