
unit StandFan_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2 の設定項目と、区間に保存された運転指示の読み取り。

interface

uses
  AviUtl2FilterTypes, StandFan_Settings, StandFan_Motion;

// DLL が所有する項目を登録順に並べ、ホストが更新する値の既定値を設定する。
procedure RegisterFanParameters;
// 現在の設定と指定時刻の姿勢を取得する。ホストの参照は保持しない。
procedure ReadFanFrame(Video: PFILTER_PROC_VIDEO; out Settings: TFanSettings;
  out Pose: TFanPose);

implementation

uses
  System.Math, PluginFilterTable;

const
  SectionSpeedItem = '運転状態（区間）';
  PresetOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM = (
    (Name:'昭和後期'; Value:Ord(fpShowaLate)), (Name:'昭和前期'; Value:Ord(fpShowaEarly)),
    (Name:'平成'; Value:Ord(fpHeisei)), (Name:'令和'; Value:Ord(fpReiwa)),
    (Name:nil; Value:0));
  SpeedOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM = (
    (Name:'切'; Value:Ord(fsOff)), (Name:'弱'; Value:Ord(fsLow)),
    (Name:'中'; Value:Ord(fsMedium)), (Name:'強'; Value:Ord(fsHigh)),
    (Name:nil; Value:0));
  SwingOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM = (
    (Name:'なし'; Value:Ord(swNone)), (Name:'横'; Value:Ord(swHorizontal)),
    (Name:nil; Value:0));
  EarlyShowaHiddenItems: array[0..4] of PWideChar = (
    '首振り方式','首振り速度','横可動範囲','縦可動範囲','首上の長さ');
  ColorNames: array[fmBlade..fmAccent] of PWideChar = (
    '羽', 'カバー', 'モーター収納部', '首上', '首下', '土台', '土台のアクセント');

var
  PresetItem, SpeedItem, SwingItem: TFILTER_ITEM_SELECT;
  BladeTrack, SectionSpeedTrack, SwingTrack, HorizontalTrack, VerticalTrack,
    ExtensionTrack: TFILTER_ITEM_TRACK;
  ColorGroup: TFILTER_ITEM_GROUP;
  EarlyShowaHideRules: array[Low(EarlyShowaHiddenItems)..High(EarlyShowaHiddenItems)] of TFILTER_ITEM_HIDE_RULE;
  ColorItems: array[fmBlade..fmAccent] of TFILTER_ITEM_COLOR;

procedure RegisterFanParameters;
var
  I: Integer;
  Material: TFanMaterial;
  Color: Cardinal;
begin
  AddSelect(PresetItem,'プリセット',Ord(fpShowaLate),@PresetOptions[0]);
  AddTrack(BladeTrack,'羽の枚数',3,MinBlades,MaxBlades,1);
  AddSelect(SpeedItem,'運転状態',Ord(fsOff),@SpeedOptions[0]);
  // セレクタはオブジェクト全体の既定値。区間ごとの指示は履歴を取得できる
  // トラックに記録し、停止と再開の位相をシーク時にも再現する。
  AddTrack(SectionSpeedTrack,SectionSpeedItem,-1,-1,3,1);
  AddSelect(SwingItem,'首振り方式',Ord(swNone),@SwingOptions[0]);
  AddTrack(SwingTrack,'首振り速度',100,10,300,1);
  AddTrack(HorizontalTrack,'横可動範囲',45,0,80,1);
  AddTrack(VerticalTrack,'縦可動範囲',15,0,45,1);
  AddTrack(ExtensionTrack,'首上の長さ',0,0,MaxExtension,1);
  for I := Low(EarlyShowaHideRules) to High(EarlyShowaHideRules) do
    AddHideRule(EarlyShowaHideRules[I],EarlyShowaHiddenItems[I],'プリセット',0,Ord(fpShowaEarly));
  AddGroup(ColorGroup,'色設定',0);
  for Material := Low(ColorItems) to High(ColorItems) do
  begin
    Color := DefaultColors[Material];
    AddColor(ColorItems[Material],ColorNames[Material],
      Byte(Color and 255),Byte((Color shr 8) and 255),Byte((Color shr 16) and 255));
  end;
end;

function Limited(Value, Low, High, DefaultValue: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Exit(DefaultValue);
  Result := EnsureRange(Value,Low,High);
end;

function SectionCommand(Value: Double; DefaultSpeed: TFanSpeed): TFanSpeed;
var
  Selection: Integer;
begin
  Selection := Floor(Limited(Value,-1,Ord(High(TFanSpeed)),-1)+0.5);
  if Selection = -1 then Exit(DefaultSpeed);
  Result := TFanSpeed(Selection);
end;

procedure ReadSettings(out Settings: TFanSettings);
var
  Material: TFanMaterial;
begin
  if InRange(PresetItem.Value,Ord(Low(TFanPreset)),Ord(High(TFanPreset))) then
    Settings.Preset := TFanPreset(PresetItem.Value)
  else
    Settings.Preset := fpShowaLate;
  Settings.BladeCount := Floor(Limited(BladeTrack.Value,MinBlades,MaxBlades,3)+0.5);
  Settings.Speed := TFanSpeed(EnsureRange(SpeedItem.Value,
    Ord(Low(TFanSpeed)),Ord(High(TFanSpeed))));
  Settings.Swing := TFanSwing(EnsureRange(SwingItem.Value,
    Ord(Low(TFanSwing)),Ord(High(TFanSwing))));
  Settings.SwingSpeed := Limited(SwingTrack.Value,10,300,100);
  Settings.HorizontalRange := Limited(HorizontalTrack.Value,0,80,45);
  Settings.VerticalRange := Limited(VerticalTrack.Value,0,45,15);
  Settings.Extension := Limited(ExtensionTrack.Value,0,MaxExtension,0);
  Settings.Colors[fmFixed] := 0;
  for Material := Low(ColorItems) to High(ColorItems) do
    with ColorItems[Material] do
      Settings.Colors[Material] := Cardinal(R) shl 16 or Cardinal(G) shl 8 or B;
end;

function ReadSectionDrive(Video: PFILTER_PROC_VIDEO; DefaultSpeed: TFanSpeed;
  Time, FPS: Double; out Drive: TFanDrive): Boolean;
var
  Edit: PEDIT_SECTION;
  Obj: POBJECT_INFO;
  Section, Sections, Frame, LastFrame: Integer;
  Since, Value: Double;
begin
  Result := False;
  Edit := Video^.Edit;
  Obj := Video^.Object_;
  if (Edit = nil) or (Obj^.Handle = nil) or (Obj^.EffectHandle = nil) or
    not Assigned(Edit^.GetEffectTrackValue) then Exit;
  Sections := 1;
  if Assigned(Edit^.GetObjectSectionNum) and Assigned(Edit^.GetObjectSectionFrame) then
    Sections := Max(1,Edit^.GetObjectSectionNum(Obj^.Handle));

  // 各区間の先頭フレームで「瞬間移動」の設定を読む。区間を順に積分するため、
  // 長い定速区間のフレームを走査せず、再生順や設定編集前のキャッシュにも依存しない。
  Drive := Default(TFanDrive);
  LastFrame := Obj^.FrameS;
  for Section := 0 to Sections-1 do
  begin
    Frame := Obj^.FrameS;
    if Section <> 0 then
    begin
      Frame := Edit^.GetObjectSectionFrame(Obj^.Handle,Section);
      if Frame <= LastFrame then Exit;
      if Frame > Obj^.FrameE then Break;
    end;
    Since := (Int64(Frame)-Obj^.FrameS)/FPS;
    if Since > Time+1E-9 then Break;
    if not Edit^.GetEffectTrackValue(Obj^.EffectHandle,SectionSpeedItem,Frame,@Value) then Exit;
    Drive.SetCommand(SectionCommand(Value,DefaultSpeed),Since);
    LastFrame := Frame;
  end;
  Result := True;
end;

procedure ReadFanFrame(Video: PFILTER_PROC_VIDEO; out Settings: TFanSettings;
  out Pose: TFanPose);
var
  Drive: TFanDrive;
  Time, FPS: Double;
begin
  ReadSettings(Settings);
  Time := Limited(Video^.Object_^.Time,0,1E9,0);
  FPS := 30;
  if (Video^.Scene <> nil) and (Video^.Scene^.Rate > 0) and
    (Video^.Scene^.Scale > 0) then FPS := Video^.Scene^.Rate/Video^.Scene^.Scale;
  // 履歴を利用できる場合は区間を再評価し、取得できない呼び出しでは現在値を使う。
  if not ReadSectionDrive(Video,Settings.Speed,Time,FPS,Drive) then
  begin
    Drive := Default(TFanDrive);
    Drive.SetCommand(SectionCommand(SectionSpeedTrack.Value,Settings.Speed),0);
  end;
  Pose := FanPose(Settings,Drive.Sample(Time),Time,FPS);
end;

end.
