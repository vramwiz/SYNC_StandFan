
unit StandFan_Mesh;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 頂点と法線を持つ部品メッシュを組み立てる。座標は X 右、Y 下、Z 奥。

interface

uses
  StandFan_Settings;

type
  TVec3 = record
    X, Y, Z: Single;
  end;

  TFanVertex = record
    Position, Normal: TVec3;
    Opacity: Single;
  end;

  TFanTriangle = record
    Vertices: array[0..2] of TFanVertex;
    Color: Cardinal;  // $RRGGBB
    Material: TFanMaterial;
  end;

  TFanPart = record
    Triangles: TArray<TFanTriangle>;
  end;

  TProfilePoint = record
    Radius, Depth: Single;
    Color: Cardinal;  // 次の断面までの色
  end;

  TLatheAxis = (axisY, axisZ);

  TFanMeshBuilder = record
  private
    FTriangles: TArray<TFanTriangle>;
    FCount: Integer;
  public
    Origin: TVec3;  // 追加する頂点に適用する部品内の平行移動。
    Material: TFanMaterial;
    // 法線に合わせて頂点順を揃える。断面中心の縮退面は省く。
    procedure Triangle(Color: Cardinal; const A, B, C: TFanVertex);
    procedure Quad(Color: Cardinal; const A, B, C, D: TFanVertex);
    procedure FlatQuad(Color: Cardinal; const A, B, C, D: TVec3);
    // 半径と軸方向位置で定義した断面を回転させ、指定軸の面を追加する。
    // Smooth では断面間の法線を補間。角を残す部品には既定の面法線を使う。
    procedure Lathe(const Center: TVec3; Axis: TLatheAxis; Segments: Integer;
      const Profile: array of TProfilePoint; Smooth: Boolean = False);
    // 完成メッシュの所有権を返し、頂点・原点・材質を次の部品に備えて初期化する。
    function Finish: TFanPart;
  end;

function Vec(X, Y, Z: Single): TVec3;
function Add(const A, B: TVec3): TVec3;
function Subtract(const A, B: TVec3): TVec3;
function Scale(const A: TVec3; Factor: Single): TVec3;
function Dot(const A, B: TVec3): Single;
function Cross(const A, B: TVec3): TVec3;
// 法線を単位長に揃える。縮退した入力はゼロベクトルのまま返す。
function Normalize(const A: TVec3): TVec3;
function Vertex(const Position, Normal: TVec3; Opacity: Single = 1): TFanVertex;
function ProfilePoint(Radius, Depth: Single; Color: Cardinal): TProfilePoint;

implementation

uses
  System.Math;

function Vec(X, Y, Z: Single): TVec3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function Add(const A, B: TVec3): TVec3;
begin
  Result := Vec(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

function Subtract(const A, B: TVec3): TVec3;
begin
  Result := Vec(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function Scale(const A: TVec3; Factor: Single): TVec3;
begin
  Result := Vec(A.X * Factor, A.Y * Factor, A.Z * Factor);
end;

function Dot(const A, B: TVec3): Single;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Cross(const A, B: TVec3): TVec3;
begin
  Result := Vec(A.Y*B.Z - A.Z*B.Y, A.Z*B.X - A.X*B.Z, A.X*B.Y - A.Y*B.X);
end;

function Normalize(const A: TVec3): TVec3;
var
  LengthSquared: Single;
begin
  LengthSquared := Dot(A, A);
  if LengthSquared > 0 then
    Result := Scale(A, 1 / Sqrt(LengthSquared))
  else
    Result := A;
end;

function Vertex(const Position, Normal: TVec3; Opacity: Single): TFanVertex;
begin
  Result.Position := Position;
  Result.Normal := Normal;
  Result.Opacity := Opacity;
end;

function ProfilePoint(Radius, Depth: Single; Color: Cardinal): TProfilePoint;
begin
  Result.Radius := Radius;
  Result.Depth := Depth;
  Result.Color := Color;
end;

procedure TFanMeshBuilder.Triangle(Color: Cardinal; const A, B, C: TFanVertex);
var
  FaceNormal: TVec3;
  Face: ^TFanTriangle;
begin
  FaceNormal := Cross(Subtract(B.Position, A.Position), Subtract(C.Position, A.Position));
  if Dot(FaceNormal, FaceNormal) < 1E-10 then Exit;
  if FCount = Length(FTriangles) then
    SetLength(FTriangles, Max(256, FCount * 2));
  Face := @FTriangles[FCount];
  Face^.Color := Color;
  Face^.Material := Material;
  Face^.Vertices[0] := A;
  if Dot(FaceNormal, Add(Add(A.Normal, B.Normal), C.Normal)) > 0 then
  begin
    Face^.Vertices[1] := B;
    Face^.Vertices[2] := C;
  end else
  begin
    Face^.Vertices[1] := C;
    Face^.Vertices[2] := B;
  end;
  Face^.Vertices[0].Position := Add(A.Position, Origin);
  Face^.Vertices[1].Position := Add(Face^.Vertices[1].Position, Origin);
  Face^.Vertices[2].Position := Add(Face^.Vertices[2].Position, Origin);
  Inc(FCount);
end;

procedure TFanMeshBuilder.Quad(Color: Cardinal; const A, B, C, D: TFanVertex);
begin
  Triangle(Color, A, B, C);
  Triangle(Color, A, C, D);
end;

procedure TFanMeshBuilder.FlatQuad(Color: Cardinal; const A, B, C, D: TVec3);
var
  N: TVec3;
begin
  N := Normalize(Cross(Subtract(B, A), Subtract(C, A)));
  Triangle(Color, Vertex(A, N), Vertex(B, N), Vertex(C, N));
  N := Normalize(Cross(Subtract(C, A), Subtract(D, A)));
  Triangle(Color, Vertex(A, N), Vertex(C, N), Vertex(D, N));
end;

procedure TFanMeshBuilder.Lathe(const Center: TVec3; Axis: TLatheAxis;
  Segments: Integer; const Profile: array of TProfilePoint; Smooth: Boolean);
var
  Circle, ProfileNormals: TArray<TVec3>;
  I, J, Next: Integer;
  Radial, Along: Single;

  function SectionNormal(First, Last: Integer): TVec3;
  begin
    Result := Normalize(Vec(Profile[Last].Depth-Profile[First].Depth,0,
      Profile[First].Radius-Profile[Last].Radius));
  end;

  function RingVertex(Ring, Angle: Integer): TFanVertex;
  var
    P, N: TVec3;
  begin
    P := Scale(Circle[Angle], Profile[Ring].Radius);
    N := Scale(Circle[Angle], Radial);
    P.Z := Profile[Ring].Depth;
    N.Z := Along;
    if Smooth then
    begin
      N := Scale(Circle[Angle],ProfileNormals[Ring].X);
      N.Z := ProfileNormals[Ring].Z;
    end;
    if Axis = axisY then
    begin
      P := Vec(P.X, P.Z, P.Y);
      N := Vec(N.X, N.Z, N.Y);
    end;
    Result := Vertex(Add(Center, P), Normalize(N));
  end;

begin
  SetLength(Circle, Segments);
  for J := 0 to Segments - 1 do
    Circle[J] := Vec(Cos(2*Pi*J/Segments), Sin(2*Pi*J/Segments), 0);
  if Smooth then
  begin
    // 各断面の前後の面法線を平均し、曲面の帯状の陰影をなくす。
    SetLength(ProfileNormals,Length(Profile));
    for I := 0 to High(Profile) do
      ProfileNormals[I] := Add(SectionNormal(Max(0,I-1),I),
        SectionNormal(I,Min(I+1,High(Profile))));
  end;
  for I := 0 to High(Profile) - 1 do
  begin
    Radial := Profile[I+1].Depth - Profile[I].Depth;
    Along := Profile[I].Radius - Profile[I+1].Radius;
    for J := 0 to Segments - 1 do
    begin
      Next := (J + 1) mod Segments;
      Quad(Profile[I].Color, RingVertex(I,J), RingVertex(I,Next),
        RingVertex(I+1,Next), RingVertex(I+1,J));
    end;
  end;
end;

function TFanMeshBuilder.Finish: TFanPart;
begin
  SetLength(FTriangles, FCount);
  Result.Triangles := FTriangles;
  FTriangles := nil;
  FCount := 0;
  Origin := Vec(0, 0, 0);
  Material := fmFixed;
end;

end.
