
unit SYNC_StandFan_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// メディアオブジェクト「扇風機」の登録と、各インスタンスの描画資源の管理。

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
  System.SysUtils, System.SyncObjs, Winapi.Windows,
  StandFan_Renderer, StandFan_Settings, StandFan_Motion, StandFan_Parameters,
  PluginFilterTable;

type
  TFanSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TFanRenderer;
  public
    constructor Create;
    destructor Destroy; override;
    // ホストの描画情報を一時利用し、エフェクトの描画バッファを排他更新する。
    procedure Draw(Video: PFILTER_PROC_VIDEO);
  end;

var
  TableRegistered: Boolean;
  CameraAPIAvailable: Boolean;

procedure SetFanHostVersion(Version: Cardinal);
begin
  CameraAPIAvailable := Version >= 2011700;
end;

constructor TFanSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
  FRenderer := TFanRenderer.Create;
end;

destructor TFanSession.Destroy;
begin
  FRenderer.Free;
  FLock.Free;
  inherited;
end;

procedure TFanSession.Draw(Video: PFILTER_PROC_VIDEO);
var
  Settings: TFanSettings;
  Pose: TFanPose;
begin
  FLock.Acquire;
  try
    ReadFanFrame(Video,Settings,Pose);
    FRenderer.Draw(Video,Settings,Pose,CameraAPIAvailable);
  finally
    FLock.Release;
  end;
end;

function FanCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TFanSession.Create;
  except
    // 生成に失敗した場合は userdata を設定しない。
  end;
end;

procedure FanDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TFanSession(UserData).Free;
  except
    // DLL 境界の外へ Delphi 例外を伝播させない。
  end;
end;

function FanProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0; // DrawPoly で描画するため標準画像の二重出力を止める。
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
  try
    TFanSession(Video^.UserData).Draw(Video);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_StandFan render: '+E.Message));
  end;
end;

function GetFanFilterTable: PFILTER_PLUGIN_TABLE;
var
  Table: PFILTER_PLUGIN_TABLE;
begin
  Table := GetPluginTable;
  if not TableRegistered then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      '扇風機','SYNC','扇風機 / SYNC_StandFan v1.0.0',FanProcVideo,nil);
    RegisterFanParameters;
    Table^.Func_Create := FanCreate;
    Table^.Func_Destroy := FanDestroy;
    TableRegistered := True;
  end;
  Result := Table;
end;

end.
