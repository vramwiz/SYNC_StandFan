
program StandFan_RenderTests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番 AUF2 にホストのコールバックを渡し、区間の時間制御と送出頂点を検査する。

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  System.SysUtils, System.Classes, System.Math, System.Hash, System.Diagnostics,
  Winapi.Windows, AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  StandFan_Settings in '..\Source\Common\StandFan_Settings.pas',
  StandFan_Motion in '..\Source\Common\StandFan_Motion.pas';

type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  TUninitialize = procedure; cdecl;
  PVertex = ^TVertexColorNorm;
  PItem = ^Pointer;
  POption = ^TFILTER_ITEM_SELECT_ITEM;
  PHideRule = ^TFILTER_ITEM_HIDE_RULE;
  PItemHeader = ^TItemHeader;
  TItemHeader = record
    Kind, Name: LPCWSTR;
  end;

const
  TestFrameS = 900;
  SectionStarts: array[0..3] of Integer = (0,30,120,240);
  ColorNames: array[0..6] of string =
    ('羽','カバー','モーター収納部','首上','首下','土台','土台のアクセント');
  BladeTriangles = 4*(16*12 + 16 + 12);

var
  Dll: HMODULE;
  Required: TRequired;
  Initialize: TInitialize;
  Uninitialize: TUninitialize;
  GetTable: TGetTable;
  Table: PFILTER_PLUGIN_TABLE;
  Video: TFILTER_PROC_VIDEO;
  Obj: TOBJECT_INFO;
  Scene: TSCENE_INFO;
  Edit: TEDIT_SECTION;
  Output: TOBJECT_IMAGE_PARAM;
  Mesh: TMemoryStream;
  SectionSpeed: array[0..3] of Double;
  CameraMode, Calls, Count, CameraQueries, TrackQueries, ExpectedAnchor: Integer;
  AbortDraw, Culling, HasImage, HasAnchor, Capture: Boolean;
  Shine: Single;
  SnapshotDir: string;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

function Item(const Name: string): Pointer;
var
  Entry: PItem;
begin
  Entry := PItem(Table^.Items);
  while Entry^ <> nil do
  begin
    if string(PItemHeader(Entry^)^.Name) = Name then Exit(Entry^);
    Inc(Entry);
  end;
  raise Exception.Create('Missing item: '+Name);
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Buffer <> nil) and (Width = 1) and (Height = 1) and (Buffer^.A = 255),
    'Default media');
  HasImage := True;
end;

procedure SetAnchor(Width, Height: Integer); cdecl;
begin
  Check((Width = 336) and (Height = ExpectedAnchor),'Anchor size');
  HasAnchor := True;
end;

procedure SetCulling(Value: Boolean); cdecl;
begin
  Culling := Value;
end;

procedure SetShine(Value: Single); cdecl;
begin
  Shine := Value;
end;

function GetOutput(Handle: OBJECT_HANDLE; Time: Double;
  Value: POBJECT_IMAGE_PARAM; Size: Integer): Boolean; cdecl;
begin
  Check((Handle = nil) and (Time = 0) and (Size = SizeOf(Output)),'Output ABI');
  Value^ := Output;
  Result := True;
end;

function GetCameraMode: Integer; cdecl;
begin
  Inc(CameraQueries);
  Result := CameraMode;
end;

function GetSectionNum(Handle: OBJECT_HANDLE): Integer; cdecl;
begin
  Check(Handle = Obj.Handle,'Object handle');
  Result := Length(SectionStarts);
end;

function GetSectionFrame(Handle: OBJECT_HANDLE; Index: Integer): Integer; cdecl;
begin
  Check(Handle = Obj.Handle,'Object section handle');
  if (Index < 0) or (Index > High(SectionStarts)) then Exit(-1);
  Result := TestFrameS+SectionStarts[Index];
end;

function GetTrack(Effect: Pointer; Name: LPCWSTR; Frame: Double;
  Value: PDouble): Boolean; cdecl;
var
  I: Integer;
begin
  Check((Effect = Obj.EffectHandle) and (string(Name) = '運転状態（区間）'),'Track ABI');
  Inc(TrackQueries);
  for I := High(SectionStarts) downto 0 do
    if Frame = TestFrameS+SectionStarts[I] then
    begin
      Value^ := SectionSpeed[I];
      Exit(True);
    end;
  Result := False;
end;

function DrawPoly(VertexType: Integer; Buffer: Pointer; N: Integer;
  Resource: LPCWSTR): Boolean; cdecl;
begin
  Check(HasImage and HasAnchor and Culling,'Draw state');
  Check((VertexType = 2) and (Buffer <> nil) and (Resource = nil) and
    (N > 0) and (N <= 12288) and (N mod 3 = 0),'Draw ABI');
  Inc(Calls);
  Inc(Count,N);
  if Capture then Mesh.WriteBuffer(Buffer^,N*SizeOf(TVertexColorNorm));
  Result := not AbortDraw;
end;

procedure Draw(Frame: Integer);
begin
  Obj.Frame := Frame;
  Obj.Time := Frame*Scene.Scale/Scene.Rate;
  Calls := 0;
  Count := 0;
  CameraQueries := 0;
  TrackQueries := 0;
  HasImage := False;
  HasAnchor := False;
  if Capture then Mesh.Size := 0;
  Check(Table^.Func_Proc_Video(@Video) = 0,'Regular image suppressed');
  Check(HasImage and HasAnchor,'Draw callback completed');
  Check(not Culling and (Shine = 0),'Host draw state restored');
end;

function V(Index: Integer): PVertex;
begin
  Result := PVertex(Mesh.Memory)+Index;
end;

function MeshHash: string;
begin
  Mesh.Position := 0;
  Result := THashSHA2.GetHashString(Mesh);
end;

procedure SaveMesh(const Name: string);
begin
  if SnapshotDir <> '' then Mesh.SaveToFile(
    IncludeTrailingPathDelimiter(SnapshotDir)+Name+'.bin');
end;

procedure ConfigureHost(Version: Cardinal);
begin
  Check(Initialize(Version) = 1,'InitializePlugin');
  Table := GetTable;
  Check((Table <> nil) and (string(Table^.Name) = '扇風機') and
    (string(Table^.Label_) = 'SYNC') and
    (string(Table^.Information) = '扇風機 / SYNC_StandFan v1.0.0') and
    (Table^.Flag = (FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA)) and
    not Assigned(Table^.Func_Proc_Audio),'Media registration');
  Check(Assigned(Table^.Func_Create) and Assigned(Table^.Func_Destroy),'Userdata lifetime');
  Video.UserData := Table^.Func_Create(100);
  Check(Video.UserData <> nil,'Create effect');
end;

procedure InitCallbacks;
begin
  Scene.Rate := 30;
  Scene.Scale := 1;
  Obj.Handle := @Obj;
  Obj.EffectHandle := @Video;
  Obj.FrameS := TestFrameS;
  Obj.FrameE := TestFrameS+360;
  Obj.FrameTotal := 361;
  Video.Scene := @Scene;
  Video.Object_ := @Obj;
  Video.Edit := @Edit;
  Video.SetImageData := SetImage;
  Video.SetDefaultAnchor := SetAnchor;
  Video.GetOutputImageParam := GetOutput;
  Video.GetCameraMode := GetCameraMode;
  Video.SetCullingState := SetCulling;
  Video.SetMaterialShine := SetShine;
  Video.DrawPoly := DrawPoly;
  Edit.GetObjectSectionNum := GetSectionNum;
  Edit.GetObjectSectionFrame := GetSectionFrame;
  Edit.GetEffectTrackValue := GetTrack;
  Output.SX := 1;
  Output.SY := 1;
  Output.SZ := 1;
  Output.Alpha := 1;
  ExpectedAnchor := 520;
  CameraMode := 1;
  Capture := True;
  FillChar(SectionSpeed,SizeOf(SectionSpeed),0);
end;

procedure CheckMotion;
var
  Drive: TFanDrive;
  A, B: TFanDriveSample;
begin
  Drive := Default(TFanDrive);
  Drive.SetCommand(fsLow,1);
  Check(Drive.Sample(1).RPM = 0,'Start begins stopped');
  Check(InRange(Drive.Sample(1.15).RPM,1,519),'Starting ramp');
  Check(Drive.Sample(2).RPM = 520,'Weak target');
  A := Drive.Sample(2);
  Drive.SetCommand(fsMedium,2);
  B := Drive.Sample(2);
  Check((A.RPM = B.RPM) and SameValue(A.Angle,B.Angle,1E-10),'Phase and speed at switch');
  Check(InRange(Drive.Sample(2.13).RPM,521,819),'Changing ramp');
  Check(Drive.Sample(3).RPM = 820,'Medium target');
  Drive.SetCommand(fsHigh,3);
  Check(Drive.Sample(4).RPM = 1100,'Strong target');
  A := Drive.Sample(4.2);
  Drive.SetCommand(fsOff,4.2);
  B := Drive.Sample(4.2);
  Check((A.RPM = B.RPM) and SameValue(A.Angle,B.Angle,1E-10),'No jump at power off');
  Check(InRange(Drive.Sample(4.6).RPM,1,1099),'Coast-down ramp');
  A := Drive.Sample(6);
  B := Drive.Sample(9);
  Check((A.RPM = 0) and (B.RPM = 0) and SameValue(A.Angle,B.Angle,1E-10),'Stopped remains still');
end;

procedure CheckBlades;
var
  N, Blade, I, Start, BaseCount: Integer;
  X, Y, R, Offset, A, Least, Most, PriorMost: Double;
begin
  Check(string(PItemHeader(Table^.Items^)^.Name) = 'プリセット','Preset is first');
  Check(string(PFILTER_ITEM_SELECT(Item('プリセット'))^.List^.Name) = '昭和後期','Default model');
  Check(PFILTER_ITEM_SELECT(Item('運転状態'))^.Value = 0,'Default stopped');
  Check(PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value = 3,'Default three blades');
  Draw(0);
  BaseCount := Count-3*BladeTriangles*3;
  SaveMesh('Phase2Stopped');
  Writeln('Default camera vertex hash: ',MeshHash);
  for N := 3 to 6 do
  begin
    PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := N;
    Draw(0);
    Check(Count = BaseCount+N*BladeTriangles*3,'Blade triangle count');
    Check(CameraQueries = 1,'Camera mode callback');
    PriorMost := -2*Pi;
    for Blade := 0 to N-1 do
    begin
      Start := BaseCount+Blade*BladeTriangles*3;
      Offset := -Pi/2+2*Pi*Blade/N;
      Least := Pi;
      Most := -Pi;
      for I := Start to Start+BladeTriangles*3-1 do
      begin
        X := V(I)^.X;
        Y := V(I)^.Y+82;
        R := Sqrt(X*X+Y*Y);
        Check((R < 149) and (V(I)^.Z > -30) and (V(I)^.Z < -5),'Blade remains inside cage');
        A := ArcTan2(Y,X)-Offset;
        A := ArcTan2(Sin(A),Cos(A));
        Least := Min(Least,A);
        Most := Max(Most,A);
      end;
      Check((Most-Least < 2*Pi/N) and (Least+Offset > PriorMost),'Adjacent blade clearance');
      PriorMost := Most+Offset;
    end;
    if N = 6 then SaveMesh('Phase2SixBlades');
  end;
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 3;
end;

procedure CheckColors;
var
  Original: TBytes;
  Prior, Current: PVertex;
  Color: PFILTER_ITEM_COLOR;
  I, N, Changed: Integer;
  Saved: TFILTER_ITEM_COLOR;
begin
  Draw(0);
  SetLength(Original,Mesh.Size);
  Move(Mesh.Memory^,Original[0],Length(Original));
  for N := Low(ColorNames) to High(ColorNames) do
  begin
    Color := PFILTER_ITEM_COLOR(Item(ColorNames[N]));
    Saved := Color^;
    Color^.R := 174;
    Color^.G := 86;
    Color^.B := 107;
    Draw(0);
    Check(Mesh.Size = Length(Original),'Color change preserves triangle count');
    Changed := 0;
    for I := 0 to Count-1 do
    begin
      Prior := PVertex(@Original[0])+I;
      Current := V(I);
      Check(CompareMem(Prior,Current,SizeOf(Single)*3) and
        CompareMem(@Prior^.A,@Current^.A,SizeOf(Single)*4),'Color preserves position and normals');
      if not CompareMem(@Prior^.R,@Current^.R,SizeOf(Single)*3) then Inc(Changed);
    end;
    Check(Changed > 0,'Color has visible effect: '+ColorNames[N]);
    Color^ := Saved;
  end;
end;

function ButtonTop(Index: Integer): Single;
var
  I: Integer;
begin
  Result := 230;
  for I := 0 to Count-1 do
    if (Abs(V(I)^.X-(-9+Index*29)) <= 13.5) and
      (Abs(V(I)^.Z+48) <= 20) and (V(I)^.Y > 205) then
      Result := Min(Result,V(I)^.Y);
end;

procedure CheckButtonColors;
var
  Button, I: Integer;
  Top: Single;
  P: PVertex;
begin
  for Button := 0 to 3 do
  begin
    Top := ButtonTop(Button);
    P := nil;
    for I := 0 to Count-1 do
      if (V(I)^.X = -9+29*Button) and (V(I)^.Y = Top) and (V(I)^.Z = -48) then
      begin
        P := V(I);
        Break;
      end;
    Check(P <> nil,'Button top center is present');
    if Button = Ord(fsOff) then
      Check(P^.G > 1.5*P^.R,'Off button uses the green accent')
    else
      Check(P^.R > P^.G,'Running buttons use the ivory shell color');
  end;
end;

function AlphaTriangles: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count div 3-1 do
    if (V(I*3)^.A < 1) or (V(I*3+1)^.A < 1) or (V(I*3+2)^.A < 1) then Inc(Result);
end;

procedure CheckDriveTimeline;
const
  Frames: array[0..6] of Integer = (0,30,33,60,120,247,310);
var
  Hashes: array[0..High(Frames)] of string;
  I: Integer;
  Flat: string;
begin
  SectionSpeed[0] := -1;
  SectionSpeed[1] := 1;
  SectionSpeed[2] := 3;
  SectionSpeed[3] := 0;
  for I := Low(Frames) to High(Frames) do
  begin
    Draw(Frames[I]);
    Hashes[I] := MeshHash;
    Check(TrackQueries >= 1,'Section history queried');
  end;
  for I := High(Frames) downto Low(Frames) do
  begin
    Draw(Frames[I]);
    Check(MeshHash = Hashes[I],'Reverse seek determinism at '+IntToStr(Frames[I]));
  end;
  Draw(0);
  Check((AlphaTriangles = 0) and (ButtonTop(0) = 223) and (ButtonTop(1) = 218),'Stopped blade and button');
  CheckButtonColors;
  Draw(30);
  Check((AlphaTriangles = 0) and (ButtonTop(0) = 218) and (ButtonTop(1) = 223),'Weak button at switch');
  Draw(34);
  Check(AlphaTriangles > 0,'Acceleration introduces translucent blur');
  Draw(60);
  Check(AlphaTriangles = 2160,'Steady rotation uses only the blur shell for moving blades');
  SaveMesh('Phase2Running');
  Draw(139);
  Check((AlphaTriangles = 2160) and (ButtonTop(3) = 223),'Strong button and blur');
  CheckButtonColors;
  Draw(247);
  Check(AlphaTriangles > 0,'Residual rotation after switch off');
  Draw(310);
  Check((AlphaTriangles = 0) and (ButtonTop(0) = 223),'Coasted to a complete stop');
  Flat := MeshHash;
  Draw(355);
  Check(MeshHash = Flat,'Stopped phase is stable');
  SectionSpeed[2] := 2;
  Draw(355);
  Check(MeshHash <> Flat,'New section edit invalidates the old phase');

  Video.Edit := nil;
  PFILTER_ITEM_TRACK(Item('運転状態（区間）'))^.Value := -1;
  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := 2;
  Draw(30);
  Check((AlphaTriangles = 2160) and (ButtonTop(2) = 223),'Whole-object selector fallback');
  Video.Edit := @Edit;
  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := 0;
  for I := Low(SectionSpeed) to High(SectionSpeed) do SectionSpeed[I] := -1;
end;

procedure CheckSpeedAppearance;
type
  TBlurStats = record
    Min, Max, Mean: Double;
  end;
const
  SnapshotNames: array[fsLow..fsHigh] of string = ('SpeedWeak','SpeedMedium','SpeedStrong');
var
  Stats: array[fsLow..fsHigh] of TBlurStats;
  Speed: TFanSpeed;
  Blades, I, Samples: Integer;
  R2, Alpha: Double;
  FirstHash: string;
begin
  for Blades in [3,6] do
  begin
    PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := Blades;
    for Speed := fsLow to fsHigh do
    begin
      PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(Speed);
      Draw(90);
      Check(AlphaTriangles = 2160,'Every speed fits the same blur mesh');
      FirstHash := MeshHash;
      if Blades = 3 then SaveMesh(SnapshotNames[Speed]);
      Stats[Speed].Min := 1;
      Stats[Speed].Max := 0;
      Stats[Speed].Mean := 0;
      Samples := 0;
      for I := Count-2160*3 to Count-1 do
      begin
        R2 := Sqr(V(I)^.X)+Sqr(V(I)^.Y+82);
        if Abs(R2-Sqr(114)) > 1 then Continue;
        Alpha := V(I)^.A;
        Stats[Speed].Min := Min(Stats[Speed].Min,Alpha);
        Stats[Speed].Max := Max(Stats[Speed].Max,Alpha);
        Stats[Speed].Mean := Stats[Speed].Mean+Alpha;
        Inc(Samples);
      end;
      Check(Samples > 0,'Sample the same ring across all speed settings');
      Stats[Speed].Mean := Stats[Speed].Mean/Samples;
      Draw(91);
      Check((MeshHash = FirstHash) = (Speed = fsHigh),'Weak and medium streaks move');
      Draw(90);
      Check(MeshHash = FirstHash,'Speed-specific streaks survive reverse seek');
    end;
    Check((Stats[fsLow].Max-Stats[fsLow].Min > 0.5) and
      (Stats[fsMedium].Max-Stats[fsMedium].Min > 0.15) and
      (Stats[fsMedium].Max-Stats[fsMedium].Min < 0.7*(Stats[fsLow].Max-Stats[fsLow].Min)) and
      (Stats[fsHigh].Max-Stats[fsHigh].Min < 0.0001),'Streak-to-disc contrast');
    Check((Stats[fsLow].Mean+0.07 < Stats[fsMedium].Mean) and
      (Stats[fsMedium].Mean+0.05 < Stats[fsHigh].Mean),'Increasing blur coverage');
    Writeln(Format('%d blades, weak / medium / strong alpha range: %.3f-%.3f / %.3f-%.3f / %.3f-%.3f',
      [Blades,Stats[fsLow].Min,Stats[fsLow].Max,Stats[fsMedium].Min,Stats[fsMedium].Max,
       Stats[fsHigh].Min,Stats[fsHigh].Max]));
  end;
  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := 0;
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 3;
end;

procedure CheckShapeMotion;
var
  I: Integer;
  Top, Bottom, MarkX: Single;
  Centered, Horizontal: string;
begin
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 96;
  ExpectedAnchor := 712;
  Draw(0);
  Top := 0;
  Bottom := 0;
  for I := 0 to Count-1 do
  begin
    Top := Min(Top,V(I)^.Y);
    Bottom := Max(Bottom,V(I)^.Y);
  end;
  Check((Top = -346) and (Bottom = 258),'Only upper assembly moves when extended');
  Centered := MeshHash;
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := 1;
  Draw(60);
  MarkX := 0;
  for I := 0 to Count-1 do
    if (Abs(V(I)^.Y+178) < 1E-4) and (V(I)^.X < -80) then
      MarkX := Min(MarkX,V(I)^.X);
  Check(MarkX < -160,'Head moves around its support at lateral peak');
  SaveMesh('Phase2ExtendedSwing');
  Horizontal := MeshHash;
  PFILTER_ITEM_TRACK(Item('縦可動範囲'))^.Value := 0;
  Draw(60);
  Check(MeshHash = Horizontal,'Reserved vertical extent does not tilt horizontal swing');
  Draw(0);
  Check(MeshHash = Centered,'Swing starts centered');
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := 0;
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 0;
  ExpectedAnchor := 520;
end;

procedure CheckHeisei;
var
  Preset: PFILTER_ITEM_SELECT;
  Options: POption;
  I, Button, FixedVertices: Integer;
  BaseWidth, NeckWidth, Top, Center, Height: Single;
  DialFound, WarmBase, CoolBlade, ButtonRound: Boolean;
  ShowaHash, HeiseiHash: string;
begin
  Preset := PFILTER_ITEM_SELECT(Item('プリセット'));
  Options := POption(Preset^.List);
  Check((string(Options[2].Name) = '平成') and (Options[2].Value = Ord(fpHeisei)),'Heisei is listed');
  Draw(0);
  ShowaHash := MeshHash;
  Preset^.Value := Ord(fpHeisei);
  Draw(0);
  HeiseiHash := MeshHash;
  Check(HeiseiHash <> ShowaHash,'Heisei has its own geometry');
  SaveMesh('HeiseiStopped');

  BaseWidth := 0;
  NeckWidth := 0;
  DialFound := False;
  WarmBase := False;
  CoolBlade := False;
  FixedVertices := Count-3*3*BladeTriangles;
  for I := 0 to Count-1 do
  begin
    if V(I)^.Y >= 232 then BaseWidth := Max(BaseWidth,Abs(V(I)^.X));
    if V(I)^.Y = 198 then NeckWidth := Max(NeckWidth,Abs(V(I)^.X));
    if (V(I)^.Y > 190) and (V(I)^.Y < 217) and (V(I)^.Z < -10) then
      DialFound := True;
    if (V(I)^.Y = 226) and (V(I)^.X = 0) and (V(I)^.Z = 13) then
      WarmBase := (V(I)^.R > V(I)^.B) and (V(I)^.B > 0.55);
    if (I >= FixedVertices) and (V(I)^.B > V(I)^.R) and (V(I)^.R > 0.55) then
      CoolBlade := True;
  end;
  Check((BaseWidth = 119) and SameValue(NeckWidth,21.7,0.001) and not DialFound,
    'Heisei round base, slim neck and no rotary dial');
  Check(WarmBase and CoolBlade,'Distinct warm-white base and cool-white blades');

  for Button := 0 to 3 do
  begin
    Center := 8+(Button-1.5)*27;
    Height := 217;
    if Button = Ord(fsOff) then Height := Height+5;
    ButtonRound := False;
    for I := 0 to Count-1 do
      if SameValue(V(I)^.X,Center,0.001) and (V(I)^.Y = Height) and
        SameValue(V(I)^.Z,-45+7.8,0.001) then ButtonRound := True;
    Check(ButtonRound,'Round button cap and pressed height');
  end;

  CheckColors;
  Draw(0);
  Check(MeshHash = HeiseiHash,'Heisei palette restores by returning shared color fields to defaults');
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 6;
  Draw(0);
  Check(Count = FixedVertices+6*3*BladeTriangles,'Heisei six-blade rotor');
  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsLow);
  Draw(60);
  Check(AlphaTriangles = 2160,'Heisei running blur');
  SaveMesh('HeiseiRunning');

  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swHorizontal);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 96;
  ExpectedAnchor := 712;
  Draw(60);
  Top := 0;
  for I := 0 to Count-1 do Top := Min(Top,V(I)^.Y);
  Check(Top = -346,'Heisei stretches and swings with the head');
  SaveMesh('HeiseiExtended');

  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsOff);
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swNone);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 0;
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 3;
  ExpectedAnchor := 520;
  Preset^.Value := Ord(fpShowaLate);
  Draw(0);
  Check(MeshHash = ShowaHash,'Switching back restores the Showa model exactly');
end;

procedure CheckReiwa;
var
  Preset: PFILTER_ITEM_SELECT;
  Options: POption;
  I, BeforeCount, Dimmed, Lit: Integer;
  BaseRadius, Bottom, NeckRadius, FrontTop, SpanTop: Single;
  BaseIsDark, BladeIsDark: Boolean;
  Prior: PVertex;
  Before: TBytes;
begin
  Preset := PFILTER_ITEM_SELECT(Item('プリセット'));
  Options := POption(Preset^.List);
  Check((string(Options[3].Name) = '令和') and (Options[3].Value = Ord(fpReiwa)) and
    (Options[4].Name = nil),'Reiwa and the end of the preset list');
  Preset^.Value := Ord(fpReiwa);
  Draw(0);
  BeforeCount := Count;
  SaveMesh('ReiwaStopped');
  BaseRadius := 0;
  Bottom := 0;
  NeckRadius := 0;
  FrontTop := 240;
  BaseIsDark := False;
  BladeIsDark := False;
  for I := 0 to Count-1 do
  begin
    Bottom := Max(Bottom,V(I)^.Y);
    if V(I)^.Y >= 245 then BaseRadius := Max(BaseRadius,Abs(V(I)^.X));
    if V(I)^.Y = 207 then NeckRadius := Max(NeckRadius,Abs(V(I)^.X));
    if (V(I)^.Y > 190) and (V(I)^.Z < -45) then FrontTop := Min(FrontTop,V(I)^.Y);
    if (V(I)^.Y = 240) and (V(I)^.X = 0) and (V(I)^.Z = 12) then
      BaseIsDark := (V(I)^.R < 0.17) and (V(I)^.R < V(I)^.B);
    if (I >= Count-3*3*BladeTriangles) and (V(I)^.B < 0.43) and
      (V(I)^.R < V(I)^.B) then BladeIsDark := True;
  end;
  Check((BaseRadius = 123) and (Bottom = 257) and SameValue(FrontTop,239.68,0.001),
    'Reiwa thin round base and flush controls');
  Check(SameValue(NeckRadius,13.8,0.001),'Reiwa is slimmer than the Heisei neck');
  Check(BaseIsDark and BladeIsDark,'Graphite base and dark blades');
  SetLength(Before,Mesh.Size);
  Move(Mesh.Memory^,Before[0],Length(Before));

  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsLow);
  Draw(0);
  Check(Count = BeforeCount,'Touch indicator preserves vertex count');
  Dimmed := 0;
  Lit := 0;
  for I := 0 to Count-1 do
  begin
    Prior := PVertex(@Before[0])+I;
    Check(CompareMem(Prior,V(I),3*SizeOf(Single)),'Touch buttons remain flat in all states');
    if not CompareMem(@Prior^.R,@V(I)^.R,3*SizeOf(Single)) then
    begin
      Check(SameValue(Prior^.Y,239.68,0.001),'Only the flat markings change brightness');
      if V(I)^.R < Prior^.R then Inc(Dimmed)
      else Inc(Lit);
    end;
  end;
  Check((Dimmed > 0) and (Lit > 0),'Off marking dims and weak marking lights');
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 6;
  Draw(60);
  Check(AlphaTriangles = 2160,'Reiwa six-blade blur');
  SaveMesh('ReiwaRunning');
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swHorizontal);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 96;
  ExpectedAnchor := 712;
  Draw(60);
  SpanTop := 0;
  for I := 0 to Count-1 do SpanTop := Min(SpanTop,V(I)^.Y);
  Check(SpanTop = -346,'Reiwa head follows the slim neck and swing');
  SaveMesh('ReiwaExtended');

  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsOff);
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swNone);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 0;
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 3;
  ExpectedAnchor := 520;
  CheckColors;
  Preset^.Value := Ord(fpShowaLate);
end;

procedure CheckEarlyShowa;
var
  Preset: PFILTER_ITEM_SELECT;
  Options: POption;
  Entry: PItem;
  Rule: PHideRule;
  I, Blade, Blades, FixedVertices, Rules, LateCount: Integer;
  MinY, MaxY, FootRadius: Single;
  X, Y, Offset, A, Least, Most, MaxRadius: Double;
  FixedHash, LateHash: string;
begin
  Preset := PFILTER_ITEM_SELECT(Item('プリセット'));
  Options := POption(Preset^.List);
  Check((Preset^.Value = Ord(fpShowaLate)) and (Ord(fpShowaLate) = 0) and
    (string(Options[0].Name) = '昭和後期'),'Former model retains its default ID');
  Check((string(Options[1].Name) = '昭和前期') and
    (Options[1].Value = Ord(fpShowaEarly)),'Early Showa is listed');
  Rules := 0;
  Entry := PItem(Table^.Items);
  while Entry^ <> nil do
  begin
    if string(PItemHeader(Entry^)^.Kind) = 'hiderule' then
    begin
      Rule := PHideRule(Entry^);
      Check((string(Rule^.ConditionName) = 'プリセット') and
        (Rule^.ConditionOperator = 0) and (Rule^.ConditionValue = Ord(fpShowaEarly)),
        'Only Early Showa hides the oscillation and height controls');
      Inc(Rules);
    end;
    Inc(Entry);
  end;
  Check(Rules = 5,'Five unsupported controls have a hide rule');

  Draw(0);
  LateCount := Count;
  LateHash := MeshHash;
  Preset^.Value := -1;
  Draw(0);
  Check(MeshHash = LateHash,'Unknown preset falls back to the former default');
  Preset^.Value := Ord(fpShowaEarly);
  ExpectedAnchor := 432;
  Draw(0);
  FixedHash := MeshHash;
  SaveMesh('EarlyShowaStopped');
  FixedVertices := Count-3*3*BladeTriangles;
  Check(Count < LateCount,'Sparse guard uses fewer triangles than the late Showa model');
  MinY := 0;
  MaxY := 0;
  FootRadius := 0;
  for I := 0 to Count-1 do
  begin
    MinY := Min(MinY,V(I)^.Y);
    MaxY := Max(MaxY,V(I)^.Y);
    if V(I)^.Y >= 199 then FootRadius := Max(FootRadius,Abs(V(I)^.X));
  end;
  Check((MinY = -212) and (MaxY = 212) and (FootRadius = 91),'Compact table fan and round foot');

  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swHorizontal);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 96;
  Draw(60);
  Check(MeshHash = FixedHash,'Early Showa ignores oscillation and extension settings');
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := Ord(swNone);
  PFILTER_ITEM_TRACK(Item('首上の長さ'))^.Value := 0;

  for Blades := 3 to 6 do
  begin
    PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := Blades;
    Draw(0);
    Check(Count = FixedVertices+Blades*3*BladeTriangles,'Broad blades retain each supported count');
    MaxRadius := 0;
    for Blade := 0 to Blades-1 do
    begin
      Least := Pi;
      Most := -Pi;
      Offset := -Pi/2+2*Pi*Blade/Blades;
      for I := FixedVertices+Blade*3*BladeTriangles to FixedVertices+(Blade+1)*3*BladeTriangles-1 do
      begin
        X := V(I)^.X;
        Y := V(I)^.Y+44;
        MaxRadius := Max(MaxRadius,Sqrt(X*X+Y*Y));
        A := ArcTan2(Y,X)-Offset;
        A := ArcTan2(Sin(A),Cos(A));
        Least := Min(Least,A);
        Most := Max(Most,A);
      end;
      Check(Most-Least < 2*Pi/Blades,'Broad blades fit without overlapping');
      if Blades = 3 then Check(Most-Least > DegToRad(85),'Original broad outline');
    end;
    Check(InRange(MaxRadius,154,158),'Blade tips remain inside the cage');
  end;
  PFILTER_ITEM_TRACK(Item('羽の枚数'))^.Value := 3;
  CheckColors;
  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsLow);
  Draw(60);
  Check(AlphaTriangles = 2160,'Early Showa retains rotation through the timeline');
  SaveMesh('EarlyShowaRunning');

  PFILTER_ITEM_SELECT(Item('運転状態'))^.Value := Ord(fsOff);
  Preset^.Value := Ord(fpShowaLate);
  ExpectedAnchor := 520;
end;

procedure CheckFallback;
var
  Before, Depth, X, Y, Z: Double;
  I: Integer;
begin
  CameraMode := 0;
  Output.RX := 21;
  Output.RY := 145;
  Draw(0);
  Before := MaxDouble;
  X := -Sin(DegToRad(Output.RY));
  Y := Sin(DegToRad(Output.RX))*Cos(DegToRad(Output.RY));
  Z := Cos(DegToRad(Output.RX))*Cos(DegToRad(Output.RY));
  for I := 0 to Count div 3-1 do
  begin
    Depth := X*(V(3*I)^.X+V(3*I+1)^.X+V(3*I+2)^.X) +
      Y*(V(3*I)^.Y+V(3*I+1)^.Y+V(3*I+2)^.Y) +
      Z*(V(3*I)^.Z+V(3*I+1)^.Z+V(3*I+2)^.Z);
    Check(Depth <= Before+0.001,'Back-to-front order');
    Before := Depth;
  end;
  AbortDraw := True;
  Draw(0);
  Check(Calls = 1,'DrawPoly failure stops submission');
  AbortDraw := False;
  Output.Alpha := 0;
  Draw(0);
  Check(Calls = 0,'Fully transparent output');
  Output.Alpha := 1;
  Output.RX := 0;
  Output.RY := 0;
end;

procedure Benchmark;
var
  Timer: TStopwatch;
  Frame: Integer;
begin
  Capture := False;
  SectionSpeed[0] := 3;
  SectionSpeed[1] := 3;
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := 1;
  CameraMode := 1;
  Timer := TStopwatch.StartNew;
  for Frame := 60 to 179 do Draw(Frame);
  Writeln(Format('Camera, running + swing, CPU mock %.3f ms/frame',
    [Timer.Elapsed.TotalMilliseconds/120]));
  CameraMode := 0;
  Timer := TStopwatch.StartNew;
  for Frame := 60 to 179 do Draw(Frame);
  Writeln(Format('No camera, running + swing, CPU mock %.3f ms/frame',
    [Timer.Elapsed.TotalMilliseconds/120]));
  Capture := True;
  PFILTER_ITEM_SELECT(Item('首振り方式'))^.Value := 0;
  SectionSpeed[0] := -1;
  SectionSpeed[1] := -1;
end;

procedure Run;
begin
  Check((NativeUInt(@@Edit.GetObjectSectionNum)-NativeUInt(@Edit) = 38*8) and
    (NativeUInt(@@Edit.GetObjectSectionFrame)-NativeUInt(@Edit) = 40*8) and
    (NativeUInt(@@Edit.GetEffectTrackValue)-NativeUInt(@Edit) = 59*8),'SDK structure offsets');
  Check(Required() = 2011600,'Required version');
  Check(Initialize(2011500) = 0,'Unsupported version gate');
  CheckMotion;
  InitCallbacks;
  ConfigureHost(2011700);
  try
    CheckBlades;
    CheckColors;
    CheckDriveTimeline;
    CheckSpeedAppearance;
    CheckShapeMotion;
    CheckHeisei;
    CheckReiwa;
    CheckEarlyShowa;
    CheckFallback;
    Benchmark;
  finally
    Table^.Func_Destroy(100,Video.UserData);
    Video.UserData := nil;
    Uninitialize();
  end;

  ConfigureHost(2011600);
  try
    Obj.Flag := 4;
    Draw(0);
    Check((CameraQueries = 0) and (Calls > 0),'2.1.16 camera fallback');
  finally
    Table^.Func_Destroy(100,Video.UserData);
    Video.UserData := nil;
    Uninitialize();
  end;
  Writeln('PASS');
end;

begin
  Mesh := TMemoryStream.Create;
  try
    try
      SnapshotDir := ParamStr(2);
      Dll := LoadLibrary(PChar(ParamStr(1)));
      Check(Dll <> 0,'LoadLibrary');
      try
        @Required := GetProcAddress(Dll,'RequiredVersion');
        @Initialize := GetProcAddress(Dll,'InitializePlugin');
        @GetTable := GetProcAddress(Dll,'GetFilterPluginTable');
        @Uninitialize := GetProcAddress(Dll,'UninitializePlugin');
        Check(Assigned(Required) and Assigned(Initialize) and Assigned(GetTable) and
          Assigned(Uninitialize),'Plugin exports');
        Run;
      finally
        FreeLibrary(Dll);
      end;
    except
      on E: Exception do
      begin
        Writeln('FAIL: ',E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Mesh.Free;
  end;
end.
