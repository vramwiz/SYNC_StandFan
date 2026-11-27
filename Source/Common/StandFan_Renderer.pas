
unit StandFan_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 部品の姿勢を組み立て、法線と色を持つ頂点を AviUtl2 の DrawPoly へ送る。
// 標準描画とカメラはホストが適用する。

interface

uses
  AviUtl2FilterTypes, StandFan_Settings, StandFan_Motion, StandFan_Model, StandFan_Mesh;

type
  TFanTransform = record
    Offset, X, Y, Z: TVec3;
    function Vector(const V: TVec3): TVec3;
    function Point(const P: TVec3): TVec3;
  end;

  PFanPart = ^TFanPart;
  TFanDrawPart = record
    Source: PFanPart;  // DLL の共有メッシュを参照。エフェクト終了まで有効。
    Transform: TFanTransform;
    Colors: TFanColors;
    Strength, TrailOpacity: Single;
    TrailCount: Integer;
    Used: Integer;
    Vertices: TArray<TVertexColorNorm>;
  end;

  TFanDepthItem = record
    Part: TFanPartKind;
    Offset: Integer;
    Depth: Single;
  end;

  TFanRenderer = class
  private
    FParts: array[TFanPartKind] of TFanDrawPart;
    FStream, FSortedVertices: TArray<TVertexColorNorm>;
    FDepthItems: TArray<TFanDepthItem>;
    FSortedAxis: TVec3;
    FSortedValid: Boolean;
    procedure UpdatePart(Kind: TFanPartKind; Source: PFanPart;
      const Transform: TFanTransform; const Palette, Colors: TFanColors; Strength: Single;
      TrailOpacity: Single = 0; TrailCount: Integer = 0);
    procedure Assemble(const Settings: TFanSettings; const Pose: TFanPose; Extension: Single);
    function MergeCamera(Translucent: Boolean): Integer;
    procedure SortForOutput(const Axis: TVec3);
  public
    // 各エフェクトがこの描画バッファを所有する。Video は呼び出し中だけ借用し、
    // 描画面へのポリゴン送出と選択アンカーの更新に使う。
    procedure Draw(Video: PFILTER_PROC_VIDEO; const Settings: TFanSettings;
      const Pose: TFanPose; CameraAPIAvailable: Boolean);
  end;

// DLL の初期化時に各プリセットの読み取り専用メッシュを構築する。
procedure PrepareFanRenderer;
procedure ReleaseFanRenderer;

implementation

uses
  System.Math, System.SysUtils, System.Generics.Collections, System.Generics.Defaults;

const
  WhitePixel: TPIXEL_RGBA = (R:255; G:255; B:255; A:255);
  KeyLight: TVec3 = (X:-0.36; Y:-0.49; Z:-0.794);
  ObjectFlagCameraTarget = 4; // OBJECT_INFO::FLAG_CAMERA_TARGET
  MaxDrawVertices = 12288;

type
  PFanModel = ^TFanModel;

var
  Models: array[TFanPreset] of TFanModel;
  DepthComparer: IComparer<TFanDepthItem>;

function CompareDepth(const A, B: TFanDepthItem): Integer;
begin
  if A.Depth > B.Depth then Exit(-1);
  if A.Depth < B.Depth then Exit(1);
  Result := Ord(A.Part)-Ord(B.Part);
  if Result = 0 then Result := A.Offset-B.Offset;
end;

procedure PrepareFanRenderer;
var
  Preset: TFanPreset;
begin
  if Assigned(DepthComparer) then Exit;
  for Preset := Low(Models) to High(Models) do BuildFanModel(Preset,Models[Preset]);
  DepthComparer := TComparer<TFanDepthItem>.Construct(CompareDepth);
end;

procedure ReleaseFanRenderer;
var
  Preset: TFanPreset;
begin
  for Preset := Low(Models) to High(Models) do Models[Preset] := Default(TFanModel);
  DepthComparer := nil;
end;

function TFanTransform.Vector(const V: TVec3): TVec3;
begin
  Result := Vec(X.X*V.X+Y.X*V.Y+Z.X*V.Z,
    X.Y*V.X+Y.Y*V.Y+Z.Y*V.Z,X.Z*V.X+Y.Z*V.Y+Z.Z*V.Z);
end;

function TFanTransform.Point(const P: TVec3): TVec3;
begin
  Result := Add(Vector(P),Offset);
end;

function Translation(X, Y, Z: Single): TFanTransform;
begin
  Result.Offset := Vec(X,Y,Z);
  Result.X := Vec(1,0,0);
  Result.Y := Vec(0,1,0);
  Result.Z := Vec(0,0,1);
end;

function HeadTransform(const Pivot: TVec3; Yaw, Pitch: Double): TFanTransform;
var
  SX, CX, SY, CY: Double;
begin
  SinCos(Pitch,SX,CX);
  SinCos(Yaw,SY,CY);
  Result.Offset := Pivot;
  Result.X := Vec(CY,0,-SY);
  Result.Y := Vec(SY*SX,CX,CY*SX);
  Result.Z := Vec(SY*CX,-SX,CY*CX);
end;

function RotorTransform(const Rotor: TFanTransform; Angle: Double): TFanTransform;
var
  S, C: Double;
begin
  SinCos(Angle,S,C);
  Result := Rotor;
  Result.X := Add(Scale(Rotor.X,C),Scale(Rotor.Y,S));
  Result.Y := Add(Scale(Rotor.X,-S),Scale(Rotor.Y,C));
end;

function TintColor(Color: Cardinal; Material: TFanMaterial; const Palette, Colors: TFanColors): Cardinal;
var
  Reference, Selected, Masked: Cardinal;
  Shift, Index: Integer;
begin
  Reference := Palette[Material];
  Selected := Colors[Material];
  if (Material = fmFixed) or (Selected = Reference) then Exit(Color);
  Result := 0;
  for Index := 0 to 2 do
  begin
    Shift := Index*8;
    Masked := (Reference shr Shift) and 255;
    Masked := Cardinal(Min(255,Round(((Color shr Shift) and 255)*
      ((Selected shr Shift) and 255)/Masked)));
    Result := Result or (Masked shl Shift);
  end;
end;

function TrailWeight(const P: TVec3; Count: Integer): Single;
var
  A, RadiusSquared: Double;
begin
  RadiusSquared := Sqr(P.X)+Sqr(P.Y);
  // 外側ほど曲げ、羽根に沿った扇状の濃淡にする。
  A := ArcTan2(P.Y,P.X)+Pi/2-0.33*RadiusSquared/Sqr(148);
  Result := Sqr(0.5+0.5*Cos(Count*A));
end;

procedure TFanRenderer.UpdatePart(Kind: TFanPartKind; Source: PFanPart;
  const Transform: TFanTransform; const Palette, Colors: TFanColors; Strength, TrailOpacity: Single;
  TrailCount: Integer);
const
  // SDK の表面は画面上で時計回り。法線は外向きを保つ。
  HostOrder: array[0..2] of Integer = (0,2,1);
var
  Slot: ^TFanDrawPart;
  Tri: ^TFanTriangle;
  Corner: ^TFanVertex;
  V: ^TVertexColorNorm;
  P, N: TVec3;
  Light, Alpha, LocalStrength: Single;
  I, J: Integer;
  Color: Cardinal;
begin
  Slot := @FParts[Kind];
  if (Strength <= 0) or (Length(Source^.Triangles) = 0) then
  begin
    if Slot^.Used <> 0 then FSortedValid := False;
    Slot^.Used := 0;
    Exit;
  end;
  if (Slot^.Used <> 0) and (Slot^.Source = Source) and (Slot^.Strength = Strength) and
    (Slot^.TrailOpacity = TrailOpacity) and (Slot^.TrailCount = TrailCount) and
    CompareMem(@Slot^.Transform,@Transform,SizeOf(Transform)) and
    CompareMem(@Slot^.Colors,@Colors,SizeOf(Colors)) then Exit;

  FSortedValid := False;
  Slot^.Source := Source;
  Slot^.Transform := Transform;
  Slot^.Colors := Colors;
  Slot^.Strength := Strength;
  Slot^.TrailOpacity := TrailOpacity;
  Slot^.TrailCount := TrailCount;
  Slot^.Used := Length(Source^.Triangles)*3;
  if Length(Slot^.Vertices) < Slot^.Used then
    SetLength(Slot^.Vertices,Slot^.Used);
  for I := 0 to High(Source^.Triangles) do
  begin
    Tri := @Source^.Triangles[I];
    Color := TintColor(Tri^.Color,Tri^.Material,Palette,Colors);
    for J := 0 to 2 do
    begin
      Corner := @Tri^.Vertices[HostOrder[J]];
      V := @Slot^.Vertices[3*I+J];
      P := Transform.Point(Corner^.Position);
      N := Transform.Vector(Corner^.Normal);
      LocalStrength := Strength;
      if TrailOpacity > 0 then
        LocalStrength := LocalStrength+TrailOpacity*TrailWeight(Corner^.Position,TrailCount);
      Alpha := Min(1.0,LocalStrength*Corner^.Opacity);
      Light := Alpha*(0.71+0.29*Max(0,Dot(N,KeyLight)))/255;
      V^.X := P.X;
      V^.Y := P.Y;
      V^.Z := P.Z;
      V^.NX := N.X;
      V^.NY := N.Y;
      V^.NZ := N.Z;
      V^.R := ((Color shr 16) and 255)*Light;
      V^.G := ((Color shr 8) and 255)*Light;
      V^.B := (Color and 255)*Light;
      V^.A := Alpha;
    end;
  end;
end;

procedure TFanRenderer.Assemble(const Settings: TFanSettings; const Pose: TFanPose;
  Extension: Single);
var
  Model: PFanModel;
  Base, Press, Lift, Head, Rotor, Blades, Blur: TFanTransform;
  Kind, PressedButton: TFanPartKind;
  Material: TFanMaterial;
  Colors: TFanColors;
  Coverage: Single;
begin
  Model := @Models[Settings.Preset];
  Colors := Settings.Colors;
  // 登録時の色は機種の標準色として扱う。編集された色は機種を切り替えても使う。
  for Material := fmBlade to High(TFanMaterial) do
    if Colors[Material] = DefaultColors[Material] then
      Colors[Material] := Model^.Colors[Material];
  Base := Translation(0,0,0);
  Press := Translation(0,Model^.ButtonTravel,0);
  Lift := Translation(0,-Extension,0);
  if Model^.SupportsSwing then
    Head := HeadTransform(Add(Model^.HeadPivot,Lift.Offset),Pose.Yaw,Pose.Pitch)
  else
    Head := HeadTransform(Add(Model^.HeadPivot,Lift.Offset),0,0);
  Rotor := Head;
  Rotor.Offset := Head.Point(Model^.RotorPivot);
  Blades := RotorTransform(Rotor,Pose.Spin);
  PressedButton := TFanPartKind(Ord(partButtonOff)+Ord(Pose.Pressed));

  UpdatePart(partBase,@Model^.Parts[partBase],Base,Model^.Colors,Colors,1);
  for Kind := partButtonOff to partButtonHigh do
    if Kind <> PressedButton then
      UpdatePart(Kind,@Model^.Parts[Kind],Base,Model^.Colors,Colors,1)
    else if Length(Model^.ActiveButtons[Pose.Pressed].Triangles) <> 0 then
      UpdatePart(Kind,@Model^.ActiveButtons[Pose.Pressed],Base,Model^.Colors,Colors,1)
    else
      UpdatePart(Kind,@Model^.Parts[Kind],Press,Model^.Colors,Colors,1);

  UpdatePart(partNeckLower,@Model^.Parts[partNeckLower],Base,Model^.Colors,Colors,1);
  UpdatePart(partNeckUpper,@Model^.Parts[partNeckUpper],Lift,Model^.Colors,Colors,1);
  UpdatePart(partCover,@Model^.Parts[partCover],Head,Model^.Colors,Colors,1);
  UpdatePart(partMotor,@Model^.Parts[partMotor],Head,Model^.Colors,Colors,1);
  // ハブは回転対称。強の均一な残像も姿勢が変わらない間は頂点を再利用できる。
  UpdatePart(partHub,@Model^.Parts[partHub],Rotor,Model^.Colors,Colors,1);
  UpdatePart(partBlades,@Model^.BladeVariants[Settings.BladeCount],Blades,
    Model^.Colors,Colors,Pose.BladeOpacity);
  Coverage := Min(Settings.BladeCount,4.3)/3;
  Blur := Rotor;
  if Pose.TrailOpacity > 0 then Blur := RotorTransform(Rotor,Pose.TrailSpin);
  UpdatePart(partBlur,@Model^.Parts[partBlur],Blur,Model^.Colors,Colors,Pose.BlurOpacity*Coverage,
    Pose.TrailOpacity*Coverage,Settings.BladeCount);
end;

function TFanRenderer.MergeCamera(Translucent: Boolean): Integer;
var
  Kind: TFanPartKind;
  Part: ^TFanDrawPart;
  Match: Boolean;
begin
  Result := 0;
  for Kind := Low(FParts) to High(FParts) do
  begin
    Part := @FParts[Kind];
    Match := (Part^.Strength < 1) or (Kind = partBlur);
    if (Part^.Used = 0) or (Match <> Translucent) then Continue;
    if Length(FStream) < Result+Part^.Used then
      SetLength(FStream,Max(Length(FStream)*2,Result+Part^.Used));
    Move(Part^.Vertices[0],FStream[Result],Part^.Used*SizeOf(TVertexColorNorm));
    Inc(Result,Part^.Used);
  end;
end;

procedure TFanRenderer.SortForOutput(const Axis: TVec3);
var
  Kind: TFanPartKind;
  Part: ^TFanDrawPart;
  A, B, C: ^TVertexColorNorm;
  I, Index, Count: Integer;
  Item: TFanDepthItem;
begin
  // カメラ対象外では標準描画の視線に合わせて面を奥から並べる。
  // 部品の描画内容と視線が同じフレームは並べ替えを再利用する。
  if FSortedValid and CompareMem(@FSortedAxis,@Axis,SizeOf(Axis)) then Exit;
  Count := 0;
  for Kind := Low(FParts) to High(FParts) do Inc(Count,FParts[Kind].Used div 3);
  SetLength(FDepthItems,Count);
  SetLength(FSortedVertices,Count*3);
  Index := 0;
  for Kind := Low(FParts) to High(FParts) do
  begin
    Part := @FParts[Kind];
    for I := 0 to Part^.Used div 3-1 do
    begin
      A := @Part^.Vertices[I*3];
      B := @Part^.Vertices[I*3+1];
      C := @Part^.Vertices[I*3+2];
      FDepthItems[Index].Part := Kind;
      FDepthItems[Index].Offset := I*3;
      FDepthItems[Index].Depth := (A^.X+B^.X+C^.X)*Axis.X +
        (A^.Y+B^.Y+C^.Y)*Axis.Y + (A^.Z+B^.Z+C^.Z)*Axis.Z;
      Inc(Index);
    end;
  end;
  TArray.Sort<TFanDepthItem>(FDepthItems,DepthComparer);
  for I := 0 to High(FDepthItems) do
  begin
    Item := FDepthItems[I];
    Move(FParts[Item.Part].Vertices[Item.Offset],FSortedVertices[I*3],
      3*SizeOf(TVertexColorNorm));
  end;
  FSortedAxis := Axis;
  FSortedValid := True;
end;

function DepthAxis(const Output: TOBJECT_IMAGE_PARAM): TVec3;
var
  SX, CX, SY, CY, Z: Double;
begin
  SinCos(DegToRad(Output.RX),SX,CX);
  SinCos(DegToRad(Output.RY),SY,CY);
  Z := CX*CY*Output.SZ;
  if (Output.RX = 0) and (Output.RY = 0) and (Z > 0) then Exit(Vec(0,0,1));
  Result := Vec(-SY*Output.SX,SX*CY*Output.SY,Z);
end;

function Submit(Video: PFILTER_PROC_VIDEO; const Vertices: TArray<TVertexColorNorm>;
  VertexCount: Integer): Boolean;
var
  Offset, Count: Integer;
begin
  Offset := 0;
  while Offset < VertexCount do
  begin
    Count := Min(MaxDrawVertices,VertexCount-Offset);
    if not Video^.DrawPoly(VERTEX_TRIANGLE_COLOR_NORM,@Vertices[Offset],Count,nil) then
      Exit(False);
    Inc(Offset,Count);
  end;
  Result := True;
end;

procedure TFanRenderer.Draw(Video: PFILTER_PROC_VIDEO; const Settings: TFanSettings;
  const Pose: TFanPose; CameraAPIAvailable: Boolean);
var
  Output: TOBJECT_IMAGE_PARAM;
  Axis: TVec3;
  HasOutput, CameraDepth: Boolean;
  Extension: Single;
  Count: Integer;
begin
  if not Assigned(Video^.DrawPoly) or not Assigned(Video^.SetImageData) then Exit;
  Video^.SetImageData(@WhitePixel,1,1);
  Extension := 0;
  if Models[Settings.Preset].SupportsExtension then Extension := Settings.Extension;
  if Assigned(Video^.SetDefaultAnchor) then
    Video^.SetDefaultAnchor(FanWidth,Models[Settings.Preset].AnchorHeight+Round(2*Extension));

  Output := Default(TOBJECT_IMAGE_PARAM);
  HasOutput := Assigned(Video^.GetOutputImageParam) and
    Video^.GetOutputImageParam(nil,0,@Output,SizeOf(Output));
  if HasOutput and (Output.Alpha <= 0) then Exit;
  CameraDepth := (Video^.Object_^.Flag and ObjectFlagCameraTarget) <> 0;
  if CameraAPIAvailable and Assigned(Video^.GetCameraMode) then
    CameraDepth := Video^.GetCameraMode() <> 0;
  CameraDepth := CameraDepth and (not HasOutput or (Output.Alpha >= 1));
  Assemble(Settings,Pose,Extension);

  try
    if Assigned(Video^.SetCullingState) then Video^.SetCullingState(True);
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0.23);
    if CameraDepth then
    begin
      // 不透明なガードとケースを先に深度へ書き、残像が手前の部品を透過しないようにする。
      Count := MergeCamera(False);
      if Submit(Video,FStream,Count) then
      begin
        if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0);
        Count := MergeCamera(True);
        Submit(Video,FStream,Count);
      end;
    end else
    begin
      Axis := Vec(0,0,1);
      if HasOutput then Axis := DepthAxis(Output);
      SortForOutput(Axis);
      Submit(Video,FSortedVertices,Length(FSortedVertices));
    end;
  finally
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0);
    if Assigned(Video^.SetCullingState) then Video^.SetCullingState(False);
  end;
end;

end.
