
unit StandFan_Model;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 機種ごとの各部位、3～6枚のローター、および半透明の残像メッシュを生成する。

interface

uses
  StandFan_Mesh, StandFan_Settings;

const
  FanWidth = 336;
  FanHeight = 520;

type
  TFanPartKind = (partBase, partButtonOff, partButtonLow, partButtonMedium,
    partButtonHigh, partNeckLower, partNeckUpper, partCover, partMotor, partHub,
    partBlades, partBlur);
  // 台座・首はオブジェクト座標、カバー・モーターはヘッド支点、
  // ハブ・羽根・残像は回転軸を原点とする。支点の合成はレンダラーが担当する。
  TFanModel = record
    Parts: array[TFanPartKind] of TFanPart;
    BladeVariants: array[MinBlades..MaxBlades] of TFanPart;
    ActiveButtons: array[TFanSpeed] of TFanPart;  // 平面操作部の選択表示。空ならボタンを移動。
    HeadPivot, RotorPivot: TVec3;
    Colors: TFanColors;
    ButtonTravel: Single;
    AnchorHeight: Integer;
    SupportsSwing, SupportsExtension: Boolean;
  end;

// 指定機種の部品と羽根の枚数別メッシュを Model に構築する。
// 結果は DLL の初期化処理が所有し、解放まで読み取り専用とする。
procedure BuildFanModel(Preset: TFanPreset; out Model: TFanModel);

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
  ReiwaHeadPivot: TVec3 = (X:0; Y:-66; Z:37);
  ReiwaRotorPivot: TVec3 = (X:0; Y:-16; Z:-57);
  EarlyHeadPivot: TVec3 = (X:0; Y:-28; Z:42);
  EarlyRotorPivot: TVec3 = (X:0; Y:-16; Z:-62);

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

procedure BuildBase(var Mesh: TFanMeshBuilder);
begin
  Mesh.Material := fmBase;
  RoundedBody(Mesh,0,12,131,111,28,[
    ProfilePoint(12,232,Shell), ProfilePoint(5,234,Shell), ProfilePoint(1,238,Shell),
    ProfilePoint(0,244,Shell), ProfilePoint(0,249,Steel), ProfilePoint(0,251,ChromeEdge),
    ProfilePoint(1,254,ShellEdge), ProfilePoint(4,258,Rubber)]);
  Mesh.Material := fmFixed;
  RoundedBody(Mesh,0,-47,111,39,10,[
    ProfilePoint(1,230,Steel), ProfilePoint(0,232,ChromeEdge),
    ProfilePoint(0,233,ChromeEdge)]);
  Mesh.Material := fmAccent;
  RoundedBody(Mesh,0,-47,107,35.5,8,[
    ProfilePoint(1,229,PanelGreen), ProfilePoint(0,230.2,PanelGreen),
    ProfilePoint(0,231,PanelGreen)]);

  // つまみの金属台と握り部は台座に固定する。
  Mesh.Material := fmFixed;
  Mesh.Lathe(Vec(-67,0,-47),axisY,32,[
    ProfilePoint(0,221,Steel), ProfilePoint(15,221,Steel),
    ProfilePoint(19,224,ChromeEdge), ProfilePoint(21,228,Steel),
    ProfilePoint(21,230,ChromeEdge), ProfilePoint(0,230,ChromeEdge)]);
  RoundedBody(Mesh,-67,-47,6.5,14,5,[
    ProfilePoint(2,207,Steel), ProfilePoint(0,210,Steel), ProfilePoint(0,222,ChromeEdge)]);
end;

procedure BuildButton(var Mesh: TFanMeshBuilder; Button: Integer);
var
  Color: Cardinal;
begin
  Color := Shell;
  Mesh.Material := fmBase;
  if Button = Ord(fsOff) then
  begin
    Color := ButtonGreen;
    Mesh.Material := fmAccent;
  end;
  RoundedBody(Mesh,-9+29*Button,-48,13.5,20,4.5,[
    ProfilePoint(2,218,Color), ProfilePoint(0,220,Color), ProfilePoint(0,230,Seam)]);
end;

procedure BuildLowerNeck(var Mesh: TFanMeshBuilder);
begin
  Mesh.Material := fmNeckLower;
  RoundedBody(Mesh,0,43,30,24,6.5,[
    ProfilePoint(0,76,Shell), ProfilePoint(0,227,Shell), ProfilePoint(2,235,ShellEdge)]);
end;

procedure BuildUpperNeck(var Mesh: TFanMeshBuilder);
begin
  Mesh.Material := fmNeckUpper;
  // 内筒は最大伸長でも下側へ残る。未伸長時は元の角柱の中に隠れる。
  RoundedBody(Mesh,0,43,24,18,6.0,[
    ProfilePoint(0,70,Steel), ProfilePoint(0,76+MaxExtension+20,Steel)]);
  RoundedBody(Mesh,0,43,30,24,6.5,[
    ProfilePoint(4,-40,Shell), ProfilePoint(0,-31,Shell), ProfilePoint(0,76,Shell)]);
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
  Front: Boolean; Color: Cardinal; TwistScale: Single = 1);
var
  Centers: array[0..GuardSteps] of TVec3;
  Rings: array[0..GuardSteps,0..WireSides-1] of TFanVertex;
  I, J, Next: Integer;
  T, R, A, Twist: Single;
  Tangent, Across, Along, Normal: TVec3;
begin
  Twist := 0.255;
  if not Front then Twist := -0.14;
  Twist := Twist*TwistScale;
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
  Mesh.Material := fmCover;
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
  Mesh.Material := fmFixed;
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
  Mesh.Material := fmMotor;
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
  Mesh.Material := fmFixed;
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

type
  TBladeShape = (bladeSweep, bladeBroad);
  TBladeAxis = array[0..3] of Single;
  TBladeCurve = record
    X, Y: TBladeAxis;
  end;
  TBladeOutline = record
    Leading, Trailing, Tip: TBladeCurve;
  end;

const
  BladeOutlines: array[TBladeShape] of TBladeOutline = (
    (Leading:(X:(22,50,92,119); Y:(-10,-35,-54,-52));
     Trailing:(X:(22,55,107,91); Y:(11,19,60,89));
     Tip:(X:(119,156,165,91); Y:(-52,-43,43,89))),
    (Leading:(X:(20,48,83,106); Y:(-9,-43,-88,-91));
     Trailing:(X:(20,48,64,96); Y:(9,35,86,108));
     Tip:(X:(106,163,184,96); Y:(-91,-82,75,108))));

function CurveValue(const Axis: TBladeAxis; T: Single): Single;
begin
  Result := Bezier(Axis[0],Axis[1],Axis[2],Axis[3],T);
end;

function BladePoint(Shape: TBladeShape; Angle, WidthScale, T, Across, Face: Single): TVec3;
var
  Outline: ^TBladeOutline;
  U, X, Y, LeadingX, LeadingY, TrailingX, TrailingY, TipX, TipY: Single;
  Camber, Thickness, Radius: Single;
begin
  Outline := @BladeOutlines[Shape];
  U := (Across+1)/2;
  LeadingX := CurveValue(Outline^.Leading.X,T);
  LeadingY := CurveValue(Outline^.Leading.Y,T);
  TrailingX := CurveValue(Outline^.Trailing.X,T);
  TrailingY := CurveValue(Outline^.Trailing.Y,T);
  TipX := CurveValue(Outline^.Tip.X,U);
  TipY := CurveValue(Outline^.Tip.Y,U);

  // 両縁の間に先端の弧を足す。根元では補正を0にし、ハブ内に収める。
  X := LeadingX + U*(TrailingX-LeadingX) + T*(TipX-
    (Outline^.Tip.X[0] + U*(Outline^.Tip.X[3]-Outline^.Tip.X[0])));
  Y := LeadingY + U*(TrailingY-LeadingY) + T*(TipY-
    (Outline^.Tip.Y[0] + U*(Outline^.Tip.Y[3]-Outline^.Tip.Y[0])));
  Camber := 3 - 4*T + Across*(10 - 5*T) + 3*(1-Sqr(Across));
  Thickness := 1.15 + 1.15*(1-T)*(1-Sqr(Across));
  if WidthScale = 1 then
    Result := Vec(X*Cos(Angle)-Y*Sin(Angle),X*Sin(Angle)+Y*Cos(Angle),
      Camber + Face*Thickness)
  else
  begin
    // 半径とピッチを保ったまま幅だけを縮め、5～6枚でも重なりを避ける。
    Radius := Sqrt(Sqr(X)+Sqr(Y));
    Angle := Angle+WidthScale*ArcTan2(Y,X);
    Result := Vec(Radius*Cos(Angle),Radius*Sin(Angle),Camber+Face*Thickness);
  end;
end;

procedure BuildBlade(var Mesh: TFanMeshBuilder; Shape: TBladeShape; Angle, WidthScale: Single;
  FaceColor, EdgeColor: Cardinal);
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
        Along := Subtract(BladePoint(Shape,Angle,WidthScale,Min(1,T+0.001),U,Side),
          BladePoint(Shape,Angle,WidthScale,Max(0,T-0.001),U,Side));
        Across := Subtract(BladePoint(Shape,Angle,WidthScale,T,Min(1,U+0.001),Side),
          BladePoint(Shape,Angle,WidthScale,T,Max(-1,U-0.001),Side));
        Normal := Scale(Normalize(Cross(Along,Across)),Side);
        Surface[Row,Col] := Vertex(BladePoint(Shape,Angle,WidthScale,T,U,Side),Normal);
      end;
  end;

  procedure JoinEdge(A, B, C, D: TFanVertex);
  begin
    Mesh.FlatQuad(EdgeColor,A.Position,B.Position,C.Position,D.Position);
  end;

begin
  MakeSurface(Front,-1);
  MakeSurface(Back,1);
  for I := 0 to LengthSteps-1 do
  begin
    for J := 0 to WidthSteps-1 do
    begin
      Mesh.Quad(FaceColor,Front[I,J],Front[I+1,J],Front[I+1,J+1],Front[I,J+1]);
      Mesh.Quad(FaceColor,Back[I,J],Back[I+1,J],Back[I+1,J+1],Back[I,J+1]);
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

procedure BuildHub(var Mesh: TFanMeshBuilder; FaceColor, HubColor: Cardinal);
begin
  Mesh.Material := fmBlade;
  Mesh.Lathe(Vec(0,0,0),axisZ,40,[
    ProfilePoint(0,-21,HubColor), ProfilePoint(21,-20,FaceColor),
    ProfilePoint(28,-12,FaceColor), ProfilePoint(31,-4,HubColor),
    ProfilePoint(31,11,HubColor), ProfilePoint(22,21,HubColor),
    ProfilePoint(11,29,Steel), ProfilePoint(11,34,Steel), ProfilePoint(0,34,Steel)]);
end;

procedure BuildBlades(var Mesh: TFanMeshBuilder; Shape: TBladeShape; Count: Integer;
  FaceColor, EdgeColor: Cardinal);
var
  I: Integer;
  WidthScale: Single;
begin
  Mesh.Material := fmBlade;
  WidthScale := Min(1.0,4.3/Count);
  if Shape = bladeBroad then WidthScale := Min(1.0,3.4/Count);
  for I := 0 to Count-1 do
    BuildBlade(Mesh,Shape,-Pi/2 + 2*Pi*I/Count,WidthScale,FaceColor,EdgeColor);
end;

procedure BuildBlur(var Mesh: TFanMeshBuilder; FaceColor: Cardinal; RadialScale: Single);
const
  Segments = 72;
  Radius: array[0..7] of Single = (30,42,76,114,132,140,145,148);
  HalfDepth: array[0..7] of Single = (8,9,9,8,7,6,4,2);
  Coverage: array[0..7] of Single = (0,0.43,0.51,0.56,0.55,0.36,0.19,0.035);
var
  I, J, K: Integer;

  function Point(Ring, Section, Side: Integer; Edge: Boolean): TFanVertex;
  var
    Angle: Double;
    C, S: Double;
    Normal: TVec3;
  begin
    Angle := 2*Pi*Section/Segments;
    SinCos(Angle,S,C);
    if Edge then Normal := Vec(C,S,0)
    else Normal := Vec(0,0,Side);
    Result := Vertex(Vec(Radius[Ring]*RadialScale*C,Radius[Ring]*RadialScale*S,HalfDepth[Ring]*Side),
      Normal,Coverage[Ring]);
  end;

begin
  // 羽根が回転中に通る範囲を、周方向の被覆率を持つ薄い立体として描く。
  // 手前と奥の両面を作り、横からは厚さが見える。
  Mesh.Material := fmBlade;
  K := High(Radius);
  for I := 0 to Segments-1 do
  begin
    for J := 0 to K-1 do
    begin
      Mesh.Quad(FaceColor,Point(J,I,-1,False),Point(J,I+1,-1,False),
        Point(J+1,I+1,-1,False),Point(J+1,I,-1,False));
      Mesh.Quad(FaceColor,Point(J,I,1,False),Point(J,I+1,1,False),
        Point(J+1,I+1,1,False),Point(J+1,I,1,False));
    end;
    Mesh.Quad(FaceColor,Point(K,I,-1,True),Point(K,I+1,-1,True),
      Point(K,I+1,1,True),Point(K,I,1,True));
  end;
end;

procedure BuildRotorParts(var Mesh: TFanMeshBuilder; var Model: TFanModel;
  FaceColor, EdgeColor, HubColor: Cardinal; Shape: TBladeShape = bladeSweep);
var
  I: Integer;
  RadialScale: Single;
begin
  BuildHub(Mesh,FaceColor,HubColor);
  Model.Parts[partHub] := Mesh.Finish;
  for I := MinBlades to MaxBlades do
  begin
    BuildBlades(Mesh,Shape,I,FaceColor,EdgeColor);
    Model.BladeVariants[I] := Mesh.Finish;
  end;
  RadialScale := 1;
  if Shape = bladeBroad then RadialScale := 1.06;
  BuildBlur(Mesh,FaceColor,RadialScale);
  Model.Parts[partBlur] := Mesh.Finish;
end;

procedure BuildLateShowa(out Model: TFanModel);
var
  Mesh: TFanMeshBuilder;
  I: Integer;
begin
  Mesh := Default(TFanMeshBuilder);
  Model.HeadPivot := HeadPivot;
  Model.RotorPivot := RotorPivot;
  Model.AnchorHeight := FanHeight;
  Model.SupportsSwing := True;
  Model.SupportsExtension := True;
  Model.Colors := DefaultColors;
  Model.ButtonTravel := 5;
  BuildBase(Mesh);
  Model.Parts[partBase] := Mesh.Finish;
  for I := 0 to 3 do
  begin
    BuildButton(Mesh,I);
    Model.Parts[TFanPartKind(Ord(partButtonOff)+I)] := Mesh.Finish;
  end;
  BuildLowerNeck(Mesh);
  Model.Parts[partNeckLower] := Mesh.Finish;
  BuildUpperNeck(Mesh);
  Model.Parts[partNeckUpper] := Mesh.Finish;
  Mesh.Origin := RotorPivot;
  BuildCage(Mesh);
  Model.Parts[partCover] := Mesh.Finish;
  Mesh.Origin := RotorPivot;
  BuildMotor(Mesh);
  Model.Parts[partMotor] := Mesh.Finish;
  BuildRotorParts(Mesh,Model,RotorBlue,RotorEdge,RotorHub);
end;

procedure BuildHeiseiBase(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := HeiseiColors[fmBase];
  Mesh.Material := fmBase;
  // 中央は低く平らに保ち、周囲を曲面の多い一体成形の輪郭にする。
  Mesh.Lathe(Vec(0,0,13),axisY,80,[
    ProfilePoint(0,226,Color), ProfilePoint(76,226,Color),
    ProfilePoint(96,228,Color), ProfilePoint(107,232,Color),
    ProfilePoint(115,238,Color), ProfilePoint(119,245,Color),
    ProfilePoint(118,250,$E4E3DA), ProfilePoint(115,254,$D8DCD7),
    ProfilePoint(107,257,$CDD3CF), ProfilePoint(0,257,$CDD3CF)],True);
  Mesh.Material := fmAccent;
  Color := HeiseiColors[fmAccent];
  RoundedBody(Mesh,8,-45,60,20,16,[
    ProfilePoint(2,224,Color), ProfilePoint(0,226,Color),
    ProfilePoint(0,231,$C6D7DD)]);
end;

procedure BuildHeiseiButton(var Mesh: TFanMeshBuilder; Button: Integer);
var
  Color: Cardinal;
begin
  Color := $FAFBF8;
  Mesh.Material := fmBase;
  if Button = Ord(fsOff) then
  begin
    Color := $E7F0F1;
    Mesh.Material := fmAccent;
  end;
  Mesh.Lathe(Vec(8+(Button-1.5)*27,0,-45),axisY,32,[
    ProfilePoint(0,217,Color), ProfilePoint(7.8,217,Color),
    ProfilePoint(9.8,218,Color), ProfilePoint(10.5,219.5,Color),
    ProfilePoint(10.5,228,Color), ProfilePoint(0,228,Color)]);
end;

procedure BuildHeiseiLowerNeck(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := HeiseiColors[fmNeckLower];
  Mesh.Material := fmNeckLower;
  Mesh.Lathe(Vec(0,0,43),axisY,48,[
    ProfilePoint(0,76,Color), ProfilePoint(19.5,76,Color),
    ProfilePoint(20.2,78,Color), ProfilePoint(21.7,198,Color),
    ProfilePoint(22.5,212,Color), ProfilePoint(26,220,Color),
    ProfilePoint(31,225,Color), ProfilePoint(33,228,Color),
    ProfilePoint(0,228,Color)],True);
end;

procedure BuildHeiseiUpperNeck(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := HeiseiColors[fmNeckUpper];
  Mesh.Material := fmNeckUpper;
  Mesh.Lathe(Vec(0,0,43),axisY,48,[
    ProfilePoint(0,70,$D4DFE0), ProfilePoint(15,70,$D4DFE0),
    ProfilePoint(15,76+MaxExtension+20,$D4DFE0), ProfilePoint(0,76+MaxExtension+20,$D4DFE0)]);
  Mesh.Lathe(Vec(0,0,43),axisY,48,[
    ProfilePoint(0,-41,Color), ProfilePoint(15.2,-41,Color),
    ProfilePoint(17,-37,Color), ProfilePoint(18.3,15,Color),
    ProfilePoint(19.5,76,Color), ProfilePoint(0,76,Color)]);
  Mesh.Lathe(HeadPivot,axisY,36,[
    ProfilePoint(0,-3,Color), ProfilePoint(19,-3,Color),
    ProfilePoint(20.5,2,$E2E7E5), ProfilePoint(19,9,Color),
    ProfilePoint(16.9,29,Color), ProfilePoint(0,31,Color)]);
end;

procedure BuildHeiseiCage(var Mesh: TFanMeshBuilder);
const
  FrontWires = 80;
  BackWires = 72;
  BackWhite = $D6DFE0;
var
  I: Integer;
  Color: Cardinal;
begin
  Color := HeiseiColors[fmCover];
  Mesh.Material := fmCover;
  for I := 0 to FrontWires-1 do
    GuardWire(Mesh,2*Pi*I/FrontWires,45,0.75,True,Color,0.45);
  for I := 0 to BackWires-1 do
    GuardWire(Mesh,2*Pi*(I+0.6)/BackWires,43,0.81,False,BackWhite,0.65);
  for I := 0 to 3 do
    GuardWire(Mesh,Pi*(I+0.5)/2,40,1.49,False,BackWhite,0.65);
  GuardRing(Mesh,111,0.85,True,Color);
  GuardRing(Mesh,150,1.02,True,Color);
  GuardRing(Mesh,64,1.00,False,BackWhite);
  GuardRing(Mesh,108,1.03,False,BackWhite);
  GuardRing(Mesh,147,1.08,False,BackWhite);

  Mesh.Lathe(Vec(0,0,0),axisZ,RimSegments,[
    ProfilePoint(159,-16,Color), ProfilePoint(163,-18,Color),
    ProfilePoint(166,-17,Color), ProfilePoint(168,-13,Color),
    ProfilePoint(168,-8,$D8E0DF), ProfilePoint(165,-4,Color),
    ProfilePoint(165,11,$D2DBDB), ProfilePoint(167,13,Color),
    ProfilePoint(165,16,BackWhite), ProfilePoint(160,17,BackWhite),
    ProfilePoint(159,15,BackWhite), ProfilePoint(159,-16,BackWhite)]);
  // 大きな単色のセンターキャップを前面の枠に取り付ける。
  Mesh.Lathe(Vec(0,0,0),axisZ,64,[
    ProfilePoint(0,-61,$F5F3E9), ProfilePoint(36,-61,$F5F3E9),
    ProfilePoint(45,-59,$F0EFE6), ProfilePoint(49,-55,$E9EBE4),
    ProfilePoint(50,-50,$D5DEDE), ProfilePoint(49,-46,Color),
    ProfilePoint(45,-44,Color), ProfilePoint(0,-44,Color)],True);
end;

procedure BuildHeiseiMotor(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
  I: Integer;
  Angle: Single;

  function Vent(Radius, Offset: Single): TVec3;
  begin
    Result := Vec(Radius*Cos(Angle+Offset),Radius*Sin(Angle+Offset),101.1);
  end;

begin
  Color := HeiseiColors[fmMotor];
  Mesh.Material := fmMotor;
  Mesh.Lathe(Vec(0,0,0),axisZ,56,[
    ProfilePoint(0,28,$E0E5E1), ProfilePoint(35,28,Color),
    ProfilePoint(45,34,Color), ProfilePoint(48,44,$D5DDDB),
    ProfilePoint(48,46,Color), ProfilePoint(50,55,Color),
    ProfilePoint(50,69,Color), ProfilePoint(47,83,Color),
    ProfilePoint(42,94,$E4E9E7), ProfilePoint(33,101,$E5EAE8),
    ProfilePoint(0,101,$E5EAE8)],True);
  for I := 0 to 15 do
  begin
    Angle := 2*Pi*I/16;
    Mesh.FlatQuad($A3AEAD,Vent(20,-0.042),Vent(31,-0.034),
      Vent(31,0.034),Vent(20,0.042));
  end;
end;

procedure BuildHeisei(out Model: TFanModel);
var
  Mesh: TFanMeshBuilder;
  I: Integer;
begin
  Mesh := Default(TFanMeshBuilder);
  Model.HeadPivot := HeadPivot;
  Model.RotorPivot := RotorPivot;
  Model.AnchorHeight := FanHeight;
  Model.SupportsSwing := True;
  Model.SupportsExtension := True;
  Model.Colors := HeiseiColors;
  Model.ButtonTravel := 5;
  BuildHeiseiBase(Mesh);
  Model.Parts[partBase] := Mesh.Finish;
  for I := 0 to 3 do
  begin
    BuildHeiseiButton(Mesh,I);
    Model.Parts[TFanPartKind(Ord(partButtonOff)+I)] := Mesh.Finish;
  end;
  BuildHeiseiLowerNeck(Mesh);
  Model.Parts[partNeckLower] := Mesh.Finish;
  BuildHeiseiUpperNeck(Mesh);
  Model.Parts[partNeckUpper] := Mesh.Finish;
  Mesh.Origin := RotorPivot;
  BuildHeiseiCage(Mesh);
  Model.Parts[partCover] := Mesh.Finish;
  Mesh.Origin := RotorPivot;
  BuildHeiseiMotor(Mesh);
  Model.Parts[partMotor] := Mesh.Finish;
  BuildRotorParts(Mesh,Model,HeiseiColors[fmBlade],$BFCED4,$CEDBDD);
end;

procedure BuildReiwaBase(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := ReiwaColors[fmBase];
  Mesh.Material := fmBase;
  Mesh.Lathe(Vec(0,0,12),axisY,96,[
    ProfilePoint(0,240,Color), ProfilePoint(109,240,Color),
    ProfilePoint(117,240.7,Color), ProfilePoint(121.3,242.5,Color),
    ProfilePoint(123,246,Color), ProfilePoint(123,250,$23272C),
    ProfilePoint(121.5,253.5,$1F2227), ProfilePoint(117,256,$1C2024),
    ProfilePoint(114,257,$1A1D21), ProfilePoint(0,257,$1A1D21)],True);
end;

procedure BuildReiwaButton(var Mesh: TFanMeshBuilder; Button: TFanSpeed; Active: Boolean);
const
  PanelY = 239.84;
  MarkY = 239.68;
  ButtonZ = -62;
  ArcSteps = 20;
var
  X, MarkX: Single;
  Mark: Cardinal;
  I: Integer;

  function RingPoint(Section: Integer; Radius: Single): TVec3;
  var
    Angle: Double;
  begin
    Angle := DegToRad(120+300*Section/ArcSteps);
    Result := Vec(X+Radius*Cos(Angle),MarkY,ButtonZ+Radius*Sin(Angle));
  end;

  procedure Bar(CenterX, HalfWidth, NearZ, FarZ: Single);
  begin
    Mesh.FlatQuad(Mark,Vec(CenterX-HalfWidth,MarkY,ButtonZ+NearZ),
      Vec(CenterX+HalfWidth,MarkY,ButtonZ+NearZ),
      Vec(CenterX+HalfWidth,MarkY,ButtonZ+FarZ),
      Vec(CenterX-HalfWidth,MarkY,ButtonZ+FarZ));
  end;

begin
  X := (Ord(Button)-1.5)*25;
  Mesh.Material := fmAccent;
  // 土台からほぼ面一にし、選択中は面の位置を保ったままマークを明るくする。
  Mesh.Lathe(Vec(X,0,ButtonZ),axisY,36,[
    ProfilePoint(0,PanelY,ReiwaColors[fmAccent]),
    ProfilePoint(8.8,PanelY,ReiwaColors[fmAccent]),
    ProfilePoint(8.8,240.4,$353D45), ProfilePoint(0,240.4,$353D45)]);
  Mesh.Material := fmFixed;
  Mark := $7D8994;
  if Active then Mark := $D4E2E7;
  if Button = fsOff then
  begin
    for I := 0 to ArcSteps-1 do
      Mesh.FlatQuad(Mark,RingPoint(I,4.1),RingPoint(I+1,4.1),
        RingPoint(I+1,3.12),RingPoint(I,3.12));
    Bar(X,0.56,0.65,4.48);
  end else
    for I := 0 to Ord(Button)-1 do
    begin
      MarkX := X+(I-(Ord(Button)-1)*0.5)*2.7;
      Bar(MarkX,0.63,-2.9,2.9);
    end;
end;

procedure BuildReiwaLowerNeck(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := ReiwaColors[fmNeckLower];
  Mesh.Material := fmNeckLower;
  Mesh.Lathe(Vec(0,0,ReiwaHeadPivot.Z),axisY,48,[
    ProfilePoint(0,76,Color), ProfilePoint(12.2,76,Color),
    ProfilePoint(13.1,78,Color), ProfilePoint(13.8,207,Color),
    ProfilePoint(14.4,231,Color), ProfilePoint(16.0,237,Color),
    ProfilePoint(19.5,240,Color), ProfilePoint(20.5,242,Color),
    ProfilePoint(0,242,Color)],True);
end;

procedure BuildReiwaUpperNeck(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := ReiwaColors[fmNeckUpper];
  Mesh.Material := fmNeckUpper;
  Mesh.Lathe(Vec(0,0,ReiwaHeadPivot.Z),axisY,40,[
    ProfilePoint(0,70,$424C55), ProfilePoint(9.5,70,$424C55),
    ProfilePoint(9.5,76+MaxExtension+20,$424C55), ProfilePoint(0,76+MaxExtension+20,$424C55)]);
  Mesh.Lathe(Vec(0,0,ReiwaHeadPivot.Z),axisY,48,[
    ProfilePoint(0,-42,Color), ProfilePoint(10.8,-42,Color),
    ProfilePoint(11.5,-38,Color), ProfilePoint(12.2,76,Color),
    ProfilePoint(0,76,Color)]);
  Mesh.Lathe(ReiwaHeadPivot,axisY,44,[
    ProfilePoint(0,-4,Color), ProfilePoint(16,-4,Color),
    ProfilePoint(17.5,1,$373E46), ProfilePoint(16.2,11,Color),
    ProfilePoint(11.5,29,Color), ProfilePoint(0,30,Color)],True);
end;

procedure BuildReiwaCage(var Mesh: TFanMeshBuilder);
const
  FrontWires = 72;
  BackWires = 64;
  RearColor = $41474F;
var
  I: Integer;
  Color: Cardinal;
begin
  Color := ReiwaColors[fmCover];
  Mesh.Material := fmCover;
  for I := 0 to FrontWires-1 do
    GuardWire(Mesh,2*Pi*I/FrontWires,36,0.78,True,Color,0.6);
  for I := 0 to BackWires-1 do
    GuardWire(Mesh,2*Pi*(I+0.5)/BackWires,43,0.84,False,RearColor,0.7);
  for I := 0 to 3 do
    GuardWire(Mesh,Pi*(I+0.5)/2,40,1.42,False,RearColor,0.7);
  GuardRing(Mesh,80,0.85,True,Color);
  GuardRing(Mesh,122,0.91,True,Color);
  GuardRing(Mesh,153,1.0,True,Color);
  GuardRing(Mesh,63,1.03,False,RearColor);
  GuardRing(Mesh,108,1.08,False,RearColor);
  GuardRing(Mesh,148,1.15,False,RearColor);

  Mesh.Lathe(Vec(0,0,0),axisZ,RimSegments,[
    ProfilePoint(160,-17,Color), ProfilePoint(164,-18,Color),
    ProfilePoint(167,-16,Color), ProfilePoint(168,-12,Color),
    ProfilePoint(168,10,$2F343B), ProfilePoint(166,14,Color),
    ProfilePoint(163,17,RearColor), ProfilePoint(160,17,RearColor),
    ProfilePoint(159,15,RearColor), ProfilePoint(159,-15,Color),
    ProfilePoint(160,-17,Color)],True);
  Mesh.Lathe(Vec(0,0,0),axisZ,56,[
    ProfilePoint(0,-57,$353A42), ProfilePoint(35,-57,$353A42),
    ProfilePoint(40,-55,Color), ProfilePoint(42,-51,$2D3239),
    ProfilePoint(41,-46,Color), ProfilePoint(37,-44,Color),
    ProfilePoint(0,-44,Color)],True);
end;

procedure BuildReiwaMotor(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
  Angle: Double;
  I: Integer;

  function Vent(Radius, Offset: Single): TVec3;
  begin
    Result := Vec(Radius*Cos(Angle+Offset),Radius*Sin(Angle+Offset),98.1);
  end;

begin
  Color := ReiwaColors[fmMotor];
  Mesh.Material := fmMotor;
  Mesh.Lathe(Vec(0,0,0),axisZ,56,[
    ProfilePoint(0,29,Color), ProfilePoint(34,29,Color),
    ProfilePoint(44,33,Color), ProfilePoint(47,40,Color),
    ProfilePoint(48,49,$272C32), ProfilePoint(48,65,Color),
    ProfilePoint(46,81,Color), ProfilePoint(42,92,Color),
    ProfilePoint(37,97,Color), ProfilePoint(32,98,Color),
    ProfilePoint(0,98,Color)],True);
  for I := 0 to 17 do
  begin
    Angle := 2*Pi*I/18;
    Mesh.FlatQuad($171B1F,Vent(20,-0.043),Vent(30,-0.035),
      Vent(30,0.035),Vent(20,0.043));
  end;
end;

procedure BuildReiwa(out Model: TFanModel);
var
  Mesh: TFanMeshBuilder;
  Button: TFanSpeed;
begin
  Mesh := Default(TFanMeshBuilder);
  Model.HeadPivot := ReiwaHeadPivot;
  Model.RotorPivot := ReiwaRotorPivot;
  Model.AnchorHeight := FanHeight;
  Model.SupportsSwing := True;
  Model.SupportsExtension := True;
  Model.Colors := ReiwaColors;
  Model.ButtonTravel := 0;
  BuildReiwaBase(Mesh);
  Model.Parts[partBase] := Mesh.Finish;
  for Button := Low(TFanSpeed) to High(TFanSpeed) do
  begin
    BuildReiwaButton(Mesh,Button,False);
    Model.Parts[TFanPartKind(Ord(partButtonOff)+Ord(Button))] := Mesh.Finish;
    BuildReiwaButton(Mesh,Button,True);
    Model.ActiveButtons[Button] := Mesh.Finish;
  end;
  BuildReiwaLowerNeck(Mesh);
  Model.Parts[partNeckLower] := Mesh.Finish;
  BuildReiwaUpperNeck(Mesh);
  Model.Parts[partNeckUpper] := Mesh.Finish;
  Mesh.Origin := Model.RotorPivot;
  BuildReiwaCage(Mesh);
  Model.Parts[partCover] := Mesh.Finish;
  Mesh.Origin := Model.RotorPivot;
  BuildReiwaMotor(Mesh);
  Model.Parts[partMotor] := Mesh.Finish;
  BuildRotorParts(Mesh,Model,ReiwaColors[fmBlade],$3D454E,$343C44);
end;

procedure BuildEarlyShowaBase(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
begin
  Color := EarlyShowaColors[fmBase];
  Mesh.Material := fmBase;
  // 固定支柱から裾に向かって広がる、塗装金属の円錐形台座。
  Mesh.Lathe(Vec(0,0,EarlyHeadPivot.Z),axisY,72,[
    ProfilePoint(0,107,Color), ProfilePoint(14,107,Color),
    ProfilePoint(16,120,Color), ProfilePoint(21,139,Color),
    ProfilePoint(32,159,Color), ProfilePoint(47,177,Color),
    ProfilePoint(63,189,Color), ProfilePoint(76,198,Color),
    ProfilePoint(78,201,$88AB9A), ProfilePoint(0,201,$88AB9A)],True);
  Mesh.Material := fmAccent;
  Mesh.Lathe(Vec(0,0,EarlyHeadPivot.Z),axisY,72,[
    ProfilePoint(0,199,EarlyShowaColors[fmAccent]),
    ProfilePoint(79,199,EarlyShowaColors[fmAccent]),
    ProfilePoint(86,200,$9CB7A8), ProfilePoint(91,203,$96B1A1),
    ProfilePoint(91,207,$779586), ProfilePoint(88,211,$677F73),
    ProfilePoint(84,212,$567164), ProfilePoint(0,212,$567164)],True);
end;

procedure BuildEarlyShowaSupport(var Mesh: TFanMeshBuilder; var Model: TFanModel);
var
  Color: Cardinal;
begin
  Color := EarlyShowaColors[fmNeckLower];
  Mesh.Material := fmNeckLower;
  Mesh.Lathe(Vec(0,0,EarlyHeadPivot.Z),axisY,48,[
    ProfilePoint(0,38,Color), ProfilePoint(13.3,38,Color),
    ProfilePoint(13.3,82,Color), ProfilePoint(13.8,104,Color),
    ProfilePoint(14.5,116,Color), ProfilePoint(0,116,Color)],True);
  Model.Parts[partNeckLower] := Mesh.Finish;

  Color := EarlyShowaColors[fmNeckUpper];
  Mesh.Material := fmNeckUpper;
  Mesh.Lathe(EarlyHeadPivot,axisY,48,[
    ProfilePoint(0,-10,Color), ProfilePoint(16,-10,Color),
    ProfilePoint(19,-4,Color), ProfilePoint(19,6,Color),
    ProfilePoint(16,21,Color), ProfilePoint(13.3,38,Color),
    ProfilePoint(13.3,66,Color), ProfilePoint(0,66,Color)],True);
  Model.Parts[partNeckUpper] := Mesh.Finish;
end;

procedure BuildEarlyShowaCage(var Mesh: TFanMeshBuilder);
const
  Spokes = 6;
  FrontRings: array[0..5] of Single = (81,118,135,146,153,159);
  RearRings: array[0..3] of Single = (59,110,140,155);
  RearColor = $7F9988;
  Cream = $E8DDC5;
  Brass = $9D8468;
var
  I: Integer;
  R: Single;
  Color: Cardinal;
begin
  Color := EarlyShowaColors[fmCover];
  Mesh.Material := fmCover;
  for I := 0 to Spokes-1 do
  begin
    GuardWire(Mesh,2*Pi*I/Spokes,25,1.08,True,Color,0);
    GuardWire(Mesh,2*Pi*I/Spokes,45,1.08,False,RearColor,0);
  end;
  for R in FrontRings do GuardRing(Mesh,R,0.88,True,Color);
  for R in RearRings do GuardRing(Mesh,R,1.02,False,RearColor);
  Mesh.Lathe(Vec(0,0,0),axisZ,RimSegments,[
    ProfilePoint(159,-17,Color), ProfilePoint(163,-18,Color),
    ProfilePoint(167,-15,$9AB7A5), ProfilePoint(168,-11,Color),
    ProfilePoint(168,-6,$759785), ProfilePoint(166,-3,Color),
    ProfilePoint(166,10,Color), ProfilePoint(165,14,RearColor),
    ProfilePoint(162,17,RearColor), ProfilePoint(159,15,RearColor),
    ProfilePoint(159,-17,Color)]);
  // 小ぶりなクリーム色の中心キャップと、塗装枠の間の金属縁。
  Mesh.Material := fmFixed;
  Mesh.Lathe(Vec(0,0,0),axisZ,48,[
    ProfilePoint(0,-59,Cream), ProfilePoint(20,-59,Cream),
    ProfilePoint(24,-58,$C9B99A), ProfilePoint(26,-56,Brass),
    ProfilePoint(28,-54,$6C6E55), ProfilePoint(28,-50,Brass),
    ProfilePoint(25,-45,Color), ProfilePoint(0,-45,Color)],True);
  Mesh.Lathe(Vec(0,0,0),axisZ,48,[
    ProfilePoint(18.5,-59.15,Brass), ProfilePoint(19.2,-59.15,Brass),
    ProfilePoint(19.4,-59,Brass), ProfilePoint(18.5,-59,Brass),
    ProfilePoint(18.5,-59.15,Brass)]);
end;

procedure BuildEarlyShowaMotor(var Mesh: TFanMeshBuilder);
var
  Color: Cardinal;
  I: Integer;
  Angle: Double;

  function VentPoint(Radius, Offset, Depth: Single): TVec3;
  begin
    Result := Vec(Radius*Cos(Angle+Offset),Radius*Sin(Angle+Offset),Depth);
  end;

begin
  Color := EarlyShowaColors[fmMotor];
  Mesh.Material := fmMotor;
  Mesh.Lathe(Vec(0,0,0),axisZ,48,[
    ProfilePoint(0,26,Color), ProfilePoint(44,26,Color),
    ProfilePoint(48,30,Color), ProfilePoint(50,36,Color),
    ProfilePoint(49,58,Color), ProfilePoint(47,67,$6B887B),
    ProfilePoint(47,70,Color), ProfilePoint(44,86,Color),
    ProfilePoint(38,97,$6C897B), ProfilePoint(31,102,Color),
    ProfilePoint(0,102,Color)],True);
  Mesh.Material := fmFixed;
  for I := 0 to 7 do
  begin
    Angle := 2*Pi*I/8;
    Mesh.FlatQuad($323B34,VentPoint(24,-0.13,25.88),VentPoint(24,0.13,25.88),
      VentPoint(40,0.105,25.88),VentPoint(40,-0.105,25.88));
    Mesh.FlatQuad($43574C,VentPoint(18,-0.10,102.14),VentPoint(29,-0.081,102.14),
      VentPoint(29,0.081,102.14),VentPoint(18,0.10,102.14));
  end;
end;

procedure BuildEarlyShowa(out Model: TFanModel);
var
  Mesh: TFanMeshBuilder;
begin
  Model := Default(TFanModel);
  Mesh := Default(TFanMeshBuilder);
  Model.HeadPivot := EarlyHeadPivot;
  Model.RotorPivot := EarlyRotorPivot;
  Model.AnchorHeight := 432;
  Model.Colors := EarlyShowaColors;
  BuildEarlyShowaBase(Mesh);
  Model.Parts[partBase] := Mesh.Finish;
  BuildEarlyShowaSupport(Mesh,Model);
  Mesh.Origin := Model.RotorPivot;
  BuildEarlyShowaCage(Mesh);
  Model.Parts[partCover] := Mesh.Finish;
  Mesh.Origin := Model.RotorPivot;
  BuildEarlyShowaMotor(Mesh);
  Model.Parts[partMotor] := Mesh.Finish;
  BuildRotorParts(Mesh,Model,EarlyShowaColors[fmBlade],$789A89,$78968A,bladeBroad);
end;

procedure BuildFanModel(Preset: TFanPreset; out Model: TFanModel);
begin
  case Preset of
    fpShowaLate: BuildLateShowa(Model);
    fpHeisei: BuildHeisei(Model);
    fpReiwa: BuildReiwa(Model);
    fpShowaEarly: BuildEarlyShowa(Model);
  end;
end;

end.
