
unit StandFan_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 扇風機の法線付き頂点を AviUtl2 の DrawPoly に送る。標準の描画変換とカメラは
// ホストが適用する。ホストのポインターや D3D リソースは保持しない。

interface

uses
  AviUtl2FilterTypes;

// DLL の初期化・終了時に共通の静止頂点を確保・解放する。
procedure PrepareFanRenderer;
procedure ReleaseFanRenderer;
// ホストのフレームバッファへ直接描画する。呼び出し側は通常画像の出力を抑止する。
procedure DrawFan(Video: PFILTER_PROC_VIDEO; CameraAPIAvailable: Boolean);

implementation

uses
  System.Math, System.Generics.Collections, System.Generics.Defaults,
  StandFan_Mesh, StandFan_Model;

const
  WhitePixel: TPIXEL_RGBA = (R:255; G:255; B:255; A:255);
  KeyLight: TVec3 = (X:-0.36; Y:-0.49; Z:-0.794);
  ObjectFlagCameraTarget = 4; // OBJECT_INFO::FLAG_CAMERA_TARGET
  MaxDrawVertices = 12288;   // 4096 三角形ずつ送る。

type
  TDepthItem = record
    Index: Integer;
    Depth: Single;
  end;

var
  CameraVertices, DefaultVertices: TArray<TVertexColorNorm>;
  TriangleCenters: TArray<TVec3>;
  DepthComparer: IComparer<TDepthItem>;

function CompareDepth(const A, B: TDepthItem): Integer;
begin
  if A.Depth > B.Depth then Exit(-1);
  if A.Depth < B.Depth then Exit(1);
  Result := A.Index - B.Index;
end;

function SortedVertices(const Axis: TVec3): TArray<TVertexColorNorm>;
var
  Order: TArray<TDepthItem>;
  I, Src, Dst: Integer;
begin
  SetLength(Order, Length(TriangleCenters));
  for I := 0 to High(Order) do
  begin
    Order[I].Index := I;
    Order[I].Depth := Dot(TriangleCenters[I], Axis);
  end;
  TArray.Sort<TDepthItem>(Order, DepthComparer);
  SetLength(Result, Length(CameraVertices));
  for I := 0 to High(Order) do
  begin
    Src := Order[I].Index*3;
    Dst := I*3;
    Move(CameraVertices[Src], Result[Dst], 3*SizeOf(TVertexColorNorm));
  end;
end;

function PackVertex(const Point: TFanVertex; const Pivot: TVec3;
  Color: Cardinal): TVertexColorNorm;
var
  P: TVec3;
  Light: Single;
begin
  P := Add(Point.Position, Pivot);
  Light := (0.71 + 0.29*Max(0,Dot(Point.Normal,KeyLight))) / 255;
  Result.X := P.X;
  Result.Y := P.Y;
  Result.Z := P.Z;
  Result.R := ((Color shr 16) and 255)*Light;
  Result.G := ((Color shr 8) and 255)*Light;
  Result.B := (Color and 255)*Light;
  Result.A := 1;
  Result.NX := Point.Normal.X;
  Result.NY := Point.Normal.Y;
  Result.NZ := Point.Normal.Z;
end;

procedure PrepareFanRenderer;
const
  // SDK の表面は画面座標で時計回り。法線はメッシュの外向きを保つ。
  HostOrder: array[0..2] of Integer = (0,2,1);
var
  Model: TFanModel;
  Kind: TFanPartKind;
  Triangle: ^TFanTriangle;
  Pivots: array[TFanPartKind] of TVec3;
  Center: TVec3;
  VertexData: TVertexColorNorm;
  Count, Offset, I, J: Integer;
begin
  if Length(CameraVertices) <> 0 then Exit;
  BuildFanModel(Model);
  Pivots[partStand] := Model[partStand].Pivot;
  Pivots[partHead] := Add(Pivots[partStand], Model[partHead].Pivot);
  Pivots[partRotor] := Add(Pivots[partHead], Model[partRotor].Pivot);

  Count := 0;
  for Kind := Low(TFanPartKind) to High(TFanPartKind) do
    Inc(Count, Length(Model[Kind].Triangles));
  SetLength(CameraVertices, Count*3);
  SetLength(TriangleCenters, Count);
  Offset := 0;
  for Kind := Low(TFanPartKind) to High(TFanPartKind) do
    for I := 0 to High(Model[Kind].Triangles) do
    begin
      Triangle := @Model[Kind].Triangles[I];
      Center := Vec(0,0,0);
      for J := 0 to 2 do
      begin
        VertexData := PackVertex(Triangle^.Vertices[HostOrder[J]], Pivots[Kind], Triangle^.Color);
        CameraVertices[Offset*3+J] := VertexData;
        Center := Add(Center, Vec(VertexData.X, VertexData.Y, VertexData.Z));
      end;
      TriangleCenters[Offset] := Scale(Center, 1/3);
      Inc(Offset);
    end;
  DepthComparer := TComparer<TDepthItem>.Construct(CompareDepth);
  DefaultVertices := SortedVertices(Vec(0,0,1));
end;

procedure ReleaseFanRenderer;
begin
  DefaultVertices := nil;
  CameraVertices := nil;
  TriangleCenters := nil;
  DepthComparer := nil;
end;

function DepthAxis(const Output: TOBJECT_IMAGE_PARAM): TVec3;
var
  SX, CX, SY, CY: Double;
begin
  // 通常描画に深度バッファがない場合のソートにだけ、標準回転と拡大率を使う。
  SinCos(DegToRad(Output.RX),SX,CX);
  SinCos(DegToRad(Output.RY),SY,CY);
  Result := Vec(-SY*Output.SX, SX*CY*Output.SY, CX*CY*Output.SZ);
end;

procedure DrawFan(Video: PFILTER_PROC_VIDEO; CameraAPIAvailable: Boolean);
var
  Output: TOBJECT_IMAGE_PARAM;
  Axis: TVec3;
  HasOutput, CameraDepth: Boolean;
  Vertices: TArray<TVertexColorNorm>;
  Offset, Count: Integer;
begin
  if not Assigned(Video^.DrawPoly) or not Assigned(Video^.SetImageData) or
    (Length(CameraVertices) = 0) then Exit;

  // 標準描画が参照する初期メディア。通常画像としては合成しない。
  Video^.SetImageData(@WhitePixel,1,1);
  if Assigned(Video^.SetDefaultAnchor) then
    Video^.SetDefaultAnchor(FanWidth,FanHeight);

  Output := Default(TOBJECT_IMAGE_PARAM);
  HasOutput := Assigned(Video^.GetOutputImageParam) and
    Video^.GetOutputImageParam(nil,0,@Output,SizeOf(Output));
  if HasOutput and (Output.Alpha <= 0) then Exit;

  CameraDepth := (Video^.Object_^.Flag and ObjectFlagCameraTarget) <> 0;
  if CameraAPIAvailable and Assigned(Video^.GetCameraMode) then
    CameraDepth := Video^.GetCameraMode() <> 0;
  if CameraDepth and (not HasOutput or (Output.Alpha >= 1)) then
    Vertices := CameraVertices
  else
  begin
    // 既定正面では DLL 所有のソート済み頂点を共有する。
    Axis := Vec(0,0,1);
    if HasOutput then Axis := DepthAxis(Output);
    if (Axis.X = 0) and (Axis.Y = 0) and (Axis.Z > 0) then
      Vertices := DefaultVertices
    else
      Vertices := SortedVertices(Axis);
  end;

  try
    if Assigned(Video^.SetCullingState) then Video^.SetCullingState(True);
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0.23);
    Offset := 0;
    while Offset < Length(Vertices) do
    begin
      Count := Min(MaxDrawVertices, Length(Vertices)-Offset);
      if not Video^.DrawPoly(VERTEX_TRIANGLE_COLOR_NORM, @Vertices[Offset], Count, nil) then
        Break;
      Inc(Offset,Count);
    end;
  finally
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0);
    if Assigned(Video^.SetCullingState) then Video^.SetCullingState(False);
  end;
end;

end.
