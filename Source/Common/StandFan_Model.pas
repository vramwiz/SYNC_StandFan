
unit StandFan_Model;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 台座・支柱、ヘッド、ローターを別部品として生成する。各部品の原点は回転支点。

interface

uses
  StandFan_Mesh;

const
  FanWidth = 336;
  FanHeight = 520;

type
  TFanPartKind = (partStand, partHead, partRotor);
  TFanModel = array[TFanPartKind] of TFanPart;

// 静止姿勢のメッシュを生成する。ヘッドは支柱、ローターはヘッドを親に持つ。
procedure BuildFanModel(out Model: TFanModel);

implementation

uses
  System.Math;

const
  Shell = $F6F1DC;
  ShellEdge = $DDDECF;
  Seam = $A0ADB0;
  Rubber = $4D585B;
  Steel = $C2D0D7;
  ChromeEdge = $778D99;
  PanelGreen = $159173;
  ButtonGreen = $52A78C;
  GuardFront = $C6D4D7;
  GuardBack = $ADBFC4;
  RotorBlue = $37A4AD;
  RotorEdge = $2D858E;
  RotorHub = $2D8996;

  HeadPivot: TVec3 = (X:0; Y:-66; Z:43);
  RotorPivot: TVec3 = (X:0; Y:-16; Z:-63);

  RimSegments = 72;
  WireRingSegments = 48;
  GuardSteps = 6;
  WireSides = 5;

procedure RoundedBody(var Mesh: TFanMeshBuilder; X, Z, HalfWidth, HalfLength,
  CornerRadius: Single; const Profile: array of TProfilePoint);
const
  CornerSteps = 5;
  EdgePoints = 4*(CornerSteps + 1);
  SignsX: array[0..3] of Integer = (1,-1,-1,1);
  SignsZ: array[0..3] of Integer = (1,1,-1,-1);
var
  Directions: array[0..EdgePoints-1] of TVec3;
  I, J, Corner, Next: Integer;
  Angle, Shrink, Height: Single;
  TopNormal, BottomNormal: TVec3;

  function Position(Section, PointIndex: Integer): TVec3;
  var
    CornerIndex: Integer;
    Offset, Radius: Single;
  begin
    CornerIndex := PointIndex div (CornerSteps+1);
    Offset := Profile[Section].Radius;
    Radius := CornerRadius - Offset;
    Result := Vec(X + SignsX[CornerIndex]*(HalfWidth-CornerRadius) +
      Radius*Directions[PointIndex].X, Profile[Section].Depth,
      Z + SignsZ[CornerIndex]*(HalfLength-CornerRadius) +
      Radius*Directions[PointIndex].Z);
  end;

  function SideVertex(Section, PointIndex: Integer): TFanVertex;
  var
    D: TVec3;
  begin
    D := Directions[PointIndex];
    Result := Vertex(Position(Section,PointIndex),
      Normalize(Vec(D.X*Height,Shrink,D.Z*Height)));
  end;

begin
  for I := 0 to High(Directions) do
  begin
    Corner := I div (CornerSteps+1);
    Angle := (Corner + (I mod (CornerSteps+1))/CornerSteps)*Pi/2;
    Directions[I] := Vec(Cos(Angle),0,Sin(Angle));
  end;
  TopNormal := Vec(0,-1,0);
  BottomNormal := Vec(0,1,0);
  for I := 0 to High(Directions) do
  begin
    Next := (I+1) mod EdgePoints;
    Mesh.Triangle(Profile[0].Color,
      Vertex(Vec(X,Profile[0].Depth,Z),TopNormal),
      Vertex(Position(0,I),TopNormal), Vertex(Position(0,Next),TopNormal));
    Mesh.Triangle(Profile[High(Profile)].Color,
      Vertex(Vec(X,Profile[High(Profile)].Depth,Z),BottomNormal),
      Vertex(Position(High(Profile),I),BottomNormal),
      Vertex(Position(High(Profile),Next),BottomNormal));
    for J := 0 to High(Profile)-1 do
    begin
      Shrink := Profile[J+1].Radius-Profile[J].Radius;
      Height := Profile[J+1].Depth-Profile[J].Depth;
      Mesh.Quad(Profile[J].Color,SideVertex(J,I),SideVertex(J+1,I),
        SideVertex(J+1,Next),SideVertex(J,Next));
    end;
  end;
end;

procedure BuildStand(var Mesh: TFanMeshBuilder);
var
  I: Integer;
  Color: Cardinal;
begin
  RoundedBody(Mesh,0,12,131,111,28,[
    ProfilePoint(12,232,Shell), ProfilePoint(5,234,Shell), ProfilePoint(1,238,Shell),
    ProfilePoint(0,244,Shell), ProfilePoint(0,249,Steel), ProfilePoint(0,251,ChromeEdge),
    ProfilePoint(1,254,ShellEdge), ProfilePoint(4,258,Rubber)]);
  RoundedBody(Mesh,0,-47,111,39,10,[
    ProfilePoint(1,230,Steel), ProfilePoint(0,232,ChromeEdge),
    ProfilePoint(0,233,ChromeEdge)]);
  RoundedBody(Mesh,0,-47,107,35.5,8,[
    ProfilePoint(1,229,PanelGreen), ProfilePoint(0,230.2,PanelGreen),
    ProfilePoint(0,231,PanelGreen)]);
  for I := 0 to 3 do
  begin
    Color := Shell;
    if I = 3 then Color := ButtonGreen;
    RoundedBody(Mesh,-9+29*I,-48,13.5,20,4.5,[
      ProfilePoint(2,218,Color), ProfilePoint(0,220,Color), ProfilePoint(0,230,Seam)]);
  end;

  // つまみの金属台と握り部は台座のメッシュに含める。
  Mesh.Lathe(Vec(-67,0,-47),axisY,32,[
    ProfilePoint(0,221,Steel), ProfilePoint(15,221,Steel),
    ProfilePoint(19,224,ChromeEdge), ProfilePoint(21,228,Steel),
    ProfilePoint(21,230,ChromeEdge), ProfilePoint(0,230,ChromeEdge)]);
  RoundedBody(Mesh,-67,-47,6.5,14,5,[
    ProfilePoint(2,207,Steel), ProfilePoint(0,210,Steel), ProfilePoint(0,222,ChromeEdge)]);

  // 緩やかに面取りされた白い角柱で、下端を台座の裏まで通す。
  RoundedBody(Mesh,0,43,30,24,6.5,[
    ProfilePoint(4,-40,Shell), ProfilePoint(0,-31,Shell),
    ProfilePoint(0,227,Shell), ProfilePoint(2,235,ShellEdge)]);
  Mesh.Lathe(HeadPivot,axisY,32,[
    ProfilePoint(0,-3,Shell), ProfilePoint(21,-3,Shell),
    ProfilePoint(23,2,ShellEdge), ProfilePoint(21,10,Shell),
    ProfilePoint(21,26,Shell), ProfilePoint(19,33,ShellEdge),
    ProfilePoint(0,33,ShellEdge)]);
end;

function GuardDepth(Radius: Single; Front: Boolean): Single;
begin
  if Front then Result := -51 + 35*Sqr(Radius/162)
  else Result := 49 - 34*Sqr(Radius/162);
end;

procedure GuardWire(var Mesh: TFanMeshBuilder; Angle, StartRadius, WireRadius: Single;
  Front: Boolean; Color: Cardinal);
var
  Centers: array[0..GuardSteps] of TVec3;
  Rings: array[0..GuardSteps,0..WireSides-1] of TFanVertex;
  I, J, Next: Integer;
  T, R, A, Twist: Single;
  Tangent, Across, Along, Normal: TVec3;
begin
  Twist := 0.255;
  if not Front then Twist := -0.14;
  for I := 0 to GuardSteps do
  begin
    T := I/GuardSteps;
    R := StartRadius + T*(162-StartRadius);
    A := Angle + Twist*Sqr(T);
    Centers[I] := Vec(R*Cos(A),R*Sin(A),GuardDepth(R,Front));
  end;
  for I := 0 to GuardSteps do
  begin
    Tangent := Normalize(Subtract(Centers[Min(I+1,GuardSteps)],Centers[Max(I-1,0)]));
    Across := Normalize(Cross(Vec(0,0,1),Tangent));
    Along := Cross(Tangent,Across);
    for J := 0 to WireSides-1 do
    begin
      A := 2*Pi*J/WireSides;
      Normal := Add(Scale(Across,Cos(A)),Scale(Along,Sin(A)));
      Rings[I,J] := Vertex(Add(Centers[I],Scale(Normal,WireRadius)),Normal);
    end;
  end;
  for I := 0 to GuardSteps-1 do
    for J := 0 to WireSides-1 do
    begin
      Next := (J+1) mod WireSides;
      Mesh.Quad(Color,Rings[I,J],Rings[I,Next],Rings[I+1,Next],Rings[I+1,J]);
    end;
end;

procedure GuardRing(var Mesh: TFanMeshBuilder; Radius, Thickness: Single;
  Front: Boolean; Color: Cardinal);
var
  Profile: array[0..WireSides] of TProfilePoint;
  I: Integer;
  Depth, Angle: Single;
begin
  Depth := GuardDepth(Radius,Front);
  if Front then Depth := Depth + 0.55 else Depth := Depth - 0.55;
  for I := 0 to WireSides-1 do
  begin
    Angle := -Pi/2 + 2*Pi*I/WireSides;
    Profile[I] := ProfilePoint(Radius + Thickness*Cos(Angle),
      Depth + Thickness*Sin(Angle),Color);
  end;
  Profile[WireSides] := Profile[0];
  Mesh.Lathe(Vec(0,0,0),axisZ,WireRingSegments,Profile);
end;

procedure BuildCage(var Mesh: TFanMeshBuilder);
const
  FrontWires = 72;
  BackWires = 64;
var
  I: Integer;
begin
  for I := 0 to FrontWires-1 do
    GuardWire(Mesh,2*Pi*I/FrontWires,37,0.82,True,GuardFront);
  for I := 0 to BackWires-1 do
    GuardWire(Mesh,2*Pi*(I+0.5)/BackWires,43,0.87,False,GuardBack);
  for I := 0 to 3 do
    GuardWire(Mesh,Pi*(I+0.5)/2,40,1.72,False,ShellEdge);
  GuardRing(Mesh,70,1.08,True,GuardFront);
  GuardRing(Mesh,113,1.12,True,GuardFront);
  GuardRing(Mesh,149,1.19,True,GuardFront);
  GuardRing(Mesh,63,1.14,False,GuardBack);
  GuardRing(Mesh,104,1.14,False,GuardBack);
  GuardRing(Mesh,145,1.21,False,GuardBack);

  // 光沢の違う縁と継ぎ目を入れ、前後の網を中空リングで固定する。
  Mesh.Lathe(Vec(0,0,0),axisZ,RimSegments,[
    ProfilePoint(159,-17,ChromeEdge), ProfilePoint(163,-18,Steel),
    ProfilePoint(167,-15,Steel), ProfilePoint(168,-11,ChromeEdge),
    ProfilePoint(168,-5,Steel), ProfilePoint(168,-2,ChromeEdge),
    ProfilePoint(168,0,Seam), ProfilePoint(168,12,Steel),
    ProfilePoint(166,15,Steel), ProfilePoint(162,17,ChromeEdge),
    ProfilePoint(159,15,ChromeEdge), ProfilePoint(159,-17,ChromeEdge)]);
  Mesh.Lathe(Vec(0,0,0),axisZ,56,[
    ProfilePoint(0,-60,Shell), ProfilePoint(21,-60,Shell),
    ProfilePoint(24,-58.6,Steel), ProfilePoint(25,-58.1,ChromeEdge),
    ProfilePoint(26,-57.5,ButtonGreen), ProfilePoint(34,-56.7,PanelGreen),
    ProfilePoint(37,-56.1,Steel), ProfilePoint(40,-55.8,Steel),
    ProfilePoint(43,-53.4,ChromeEdge), ProfilePoint(43,-49,Steel),
    ProfilePoint(39,-45,ShellEdge), ProfilePoint(0,-45,ShellEdge)]);
end;

procedure BuildMotor(var Mesh: TFanMeshBuilder);
var
  I: Integer;
  Angle: Single;

  function VentPoint(Radius, Offset: Single): TVec3;
  begin
    Result := Vec(Radius*Cos(Angle+Offset),Radius*Sin(Angle+Offset),105.15);
  end;

begin
  // 前側の固定フランジが背面ガードのワイヤーを受ける。
  Mesh.Lathe(Vec(0,0,0),axisZ,48,[
    ProfilePoint(0,28,ShellEdge), ProfilePoint(34,28,Shell),
    ProfilePoint(43,34,Shell), ProfilePoint(47,41,ShellEdge),
    ProfilePoint(48,48,Seam), ProfilePoint(48,51,Shell),
    ProfilePoint(46,56,Shell), ProfilePoint(47,75,Shell),
    ProfilePoint(46,91,Shell), ProfilePoint(41,102,ShellEdge),
    ProfilePoint(34,105,ShellEdge), ProfilePoint(0,105,ShellEdge)]);
  Mesh.Lathe(Vec(0,0,0),axisZ,32,[
    ProfilePoint(0,104,Shell), ProfilePoint(12,104,Shell),
    ProfilePoint(11,108,Shell), ProfilePoint(0,109,Shell)]);
  for I := 0 to 15 do
  begin
    Angle := 2*Pi*I/16;
    Mesh.FlatQuad(Rubber,VentPoint(20,-0.048),VentPoint(32,-0.039),
      VentPoint(32,0.039),VentPoint(20,0.048));
  end;
end;

function Bezier(A, B, C, D, T: Single): Single;
var
  S: Single;
begin
  S := 1-T;
  Result := S*S*(S*A + 3*T*B) + T*T*(3*S*C + T*D);
end;

function BladePoint(Angle, T, Across, Face: Single): TVec3;
const
  TipStartX = 119;
  TipStartY = -52;
  TipEndX = 91;
  TipEndY = 89;
var
  U, X, Y, LeadingX, LeadingY, TrailingX, TrailingY, TipX, TipY: Single;
  Camber, Thickness: Single;
begin
  U := (Across+1)/2;

  // 写真の正面輪郭を3本の曲線で表す。細い根元から外側に開き、
  // 幅広い先端の弧と内側へ切れ込む縁で、左右非対称の羽根を作る。
  LeadingX := Bezier(22,50,92,TipStartX,T);
  LeadingY := Bezier(-10,-35,-54,TipStartY,T);
  TrailingX := Bezier(22,55,107,TipEndX,T);
  TrailingY := Bezier(11,19,60,TipEndY,T);
  TipX := Bezier(TipStartX,156,165,TipEndX,U);
  TipY := Bezier(TipStartY,-43,43,TipEndY,U);

  // 両縁を補間した面に先端の弧を足す。根元では補正を0にし、ハブ内に収める。
  X := LeadingX + U*(TrailingX-LeadingX) + T*(TipX-(TipStartX + U*(TipEndX-TipStartX)));
  Y := LeadingY + U*(TrailingY-LeadingY) + T*(TipY-(TipStartY + U*(TipEndY-TipStartY)));
  Camber := 3 - 4*T + Across*(10 - 5*T) + 3*(1-Sqr(Across));
  Thickness := 1.15 + 1.15*(1-T)*(1-Sqr(Across));
  Result := Vec(X*Cos(Angle)-Y*Sin(Angle),X*Sin(Angle)+Y*Cos(Angle),
    Camber + Face*Thickness);
end;

procedure BuildBlade(var Mesh: TFanMeshBuilder; Angle: Single);
const
  LengthSteps = 16;
  WidthSteps = 12;
type
  TBladeSurface = array[0..LengthSteps,0..WidthSteps] of TFanVertex;
var
  Front, Back: TBladeSurface;
  I, J: Integer;

  procedure MakeSurface(var Surface: TBladeSurface; Side: Single);
  var
    Row, Col: Integer;
    T, U: Single;
    Along, Across, Normal: TVec3;
  begin
    for Row := 0 to LengthSteps do
      for Col := 0 to WidthSteps do
      begin
        T := Row/LengthSteps;
        U := 2*Col/WidthSteps-1;
        Along := Subtract(BladePoint(Angle,Min(1,T+0.001),U,Side),
          BladePoint(Angle,Max(0,T-0.001),U,Side));
        Across := Subtract(BladePoint(Angle,T,Min(1,U+0.001),Side),
          BladePoint(Angle,T,Max(-1,U-0.001),Side));
        Normal := Scale(Normalize(Cross(Along,Across)),Side);
        Surface[Row,Col] := Vertex(BladePoint(Angle,T,U,Side),Normal);
      end;
  end;

  procedure JoinEdge(A, B, C, D: TFanVertex);
  begin
    Mesh.FlatQuad(RotorEdge,A.Position,B.Position,C.Position,D.Position);
  end;

begin
  MakeSurface(Front,-1);
  MakeSurface(Back,1);
  for I := 0 to LengthSteps-1 do
  begin
    for J := 0 to WidthSteps-1 do
    begin
      Mesh.Quad(RotorBlue,Front[I,J],Front[I+1,J],Front[I+1,J+1],Front[I,J+1]);
      Mesh.Quad(RotorBlue,Back[I,J],Back[I+1,J],Back[I+1,J+1],Back[I,J+1]);
    end;
    JoinEdge(Front[I,0],Front[I+1,0],Back[I+1,0],Back[I,0]);
    JoinEdge(Front[I+1,WidthSteps],Front[I,WidthSteps],Back[I,WidthSteps],Back[I+1,WidthSteps]);
  end;
  for J := 0 to WidthSteps-1 do
  begin
    JoinEdge(Front[0,J+1],Front[0,J],Back[0,J],Back[0,J+1]);
    JoinEdge(Front[LengthSteps,J],Front[LengthSteps,J+1],Back[LengthSteps,J+1],Back[LengthSteps,J]);
  end;
end;

procedure BuildRotor(var Mesh: TFanMeshBuilder);
const
  BladeCount = 3;
var
  I: Integer;
begin
  Mesh.Lathe(Vec(0,0,0),axisZ,40,[
    ProfilePoint(0,-21,RotorHub), ProfilePoint(21,-20,RotorBlue),
    ProfilePoint(28,-12,RotorBlue), ProfilePoint(31,-4,RotorHub),
    ProfilePoint(31,11,RotorHub), ProfilePoint(22,21,RotorHub),
    ProfilePoint(11,29,Steel), ProfilePoint(11,34,Steel), ProfilePoint(0,34,Steel)]);
  for I := 0 to BladeCount-1 do BuildBlade(Mesh,-Pi/2 + 2*Pi*I/BladeCount);
end;

procedure BuildFanModel(out Model: TFanModel);
var
  Mesh: TFanMeshBuilder;
begin
  Mesh := Default(TFanMeshBuilder);
  BuildStand(Mesh);
  Model[partStand] := Mesh.Finish(Vec(0,0,0));
  Mesh.Origin := RotorPivot;
  BuildCage(Mesh);
  BuildMotor(Mesh);
  Model[partHead] := Mesh.Finish(HeadPivot);
  BuildRotor(Mesh);
  Model[partRotor] := Mesh.Finish(RotorPivot);
end;

end.
