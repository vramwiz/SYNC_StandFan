
unit StandFan_Motion;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// オブジェクト時刻から駆動の角度・速度と首振り姿勢を評価する。

interface

uses
  StandFan_Settings;

type
  TFanDriveSample = record
    Command: TFanSpeed;
    RPM, Angle, Turns: Double;
  end;

  TFanDrive = record
  private
    FCommand: TFanSpeed;
    FSince, FStartRPM, FTargetRPM, FDuration, FStartTurns: Double;
    function SpeedAt(Elapsed: Double): Double;
    function TurnsAt(Elapsed: Double): Double;
  public
    // 初期値は停止。開始時刻の昇順に運転指示を渡し、その時点の速度・位相を引き継ぐ。
    procedure SetCommand(Command: TFanSpeed; Time: Double);
    // 指定したオブジェクト時刻（秒）の速度（RPM）・回転角・累積回転数を返す。
    function Sample(Time: Double): TFanDriveSample;
  end;

  TFanPose = record
    Yaw, Pitch, Spin, TrailSpin: Double;
    BladeOpacity, BlurOpacity, TrailOpacity: Single;
    Pressed: TFanSpeed;
  end;

// 角度はラジアン。FPS と羽根枚数を使い、コマ間で逆回転して見える前に残像へ移す。
function FanPose(const Settings: TFanSettings; const Drive: TFanDriveSample;
  Time, FPS: Double): TFanPose;

implementation

uses
  System.Math;

const
  TargetRPM: array[TFanSpeed] of Double = (0,520,820,1100);
  FullRampUp = 0.82;
  FullRampDown = 1.4;
  SwingPeriod = 8.0;

function SmoothStep(T: Double): Double;
begin
  T := EnsureRange(T,0.0,1.0);
  Result := T*T*(3-2*T);
end;

function TFanDrive.SpeedAt(Elapsed: Double): Double;
begin
  if Elapsed >= FDuration then Exit(FTargetRPM);
  Result := FStartRPM + (FTargetRPM-FStartRPM)*SmoothStep(Elapsed/FDuration);
end;

function TFanDrive.TurnsAt(Elapsed: Double): Double;
var
  RampTime, U, Integral: Double;
begin
  if FDuration <= 0 then Exit(FStartTurns + Elapsed*FTargetRPM/60);
  RampTime := Min(Elapsed,FDuration);
  U := RampTime/FDuration;
  // smoothstep の積分。加減速中も定速区間との境界も位相が連続する。
  Integral := U*U*U*(1-0.5*U);
  Result := FStartTurns + (RampTime*FStartRPM +
    FDuration*(FTargetRPM-FStartRPM)*Integral +
    (Elapsed-RampTime)*FTargetRPM)/60;
end;

procedure TFanDrive.SetCommand(Command: TFanSpeed; Time: Double);
var
  Elapsed, Seconds: Double;
begin
  if Command = FCommand then Exit;
  Elapsed := Max(0.0,Time-FSince);
  FStartTurns := TurnsAt(Elapsed);
  FStartRPM := SpeedAt(Elapsed);
  FTargetRPM := TargetRPM[Command];
  Seconds := FullRampUp;
  if FTargetRPM < FStartRPM then Seconds := FullRampDown;
  FDuration := Max(0.16,Seconds*Abs(FTargetRPM-FStartRPM)/TargetRPM[fsHigh]);
  FSince := Time;
  FCommand := Command;
end;

function TFanDrive.Sample(Time: Double): TFanDriveSample;
var
  Elapsed: Double;
begin
  Elapsed := Max(0.0,Time-FSince);
  Result.Command := FCommand;
  Result.RPM := SpeedAt(Elapsed);
  Result.Turns := TurnsAt(Elapsed);
  Result.Angle := Frac(Result.Turns)*2*Pi;
end;

function FanPose(const Settings: TFanSettings; const Drive: TFanDriveSample;
  Time, FPS: Double): TFanPose;
var
  SafeFPS, Passes, Blend, Diffusion, TrailRate: Double;
begin
  Result := Default(TFanPose);
  case Settings.Swing of
    swHorizontal: Result.Yaw := DegToRad(Settings.HorizontalRange) *
      Sin(2*Pi*Time*Settings.SwingSpeed/(100*SwingPeriod));
  end;

  SafeFPS := EnsureRange(FPS,1.0,240.0);
  Passes := Drive.RPM*Settings.BladeCount/(60*SafeFPS);
  Blend := SmoothStep((Passes-0.15)/0.28);
  Result.BladeOpacity := 1-Blend;

  // 低速では羽根の流れを残し、中速では隙間を埋め、高速では均一な円盤へ移る。
  // 指示値ではなく現在の回転数で変化させ、加減速でも連続させる。
  Diffusion := SmoothStep((Drive.RPM-460)/(TargetRPM[fsHigh]-460));
  Result.BlurOpacity := Blend*(0.12+0.88*Diffusion*(0.3+0.7*Diffusion));
  Result.TrailOpacity := Blend*1.12*(1-Diffusion*(0.45+0.55*Diffusion));

  // 残像の模様は1フレーム当たり0.32周期以下に抑え、コマ間の逆回転を防ぐ。
  // 位相には区間を通算した回転数を用いる。
  TrailRate := Min(1.0,0.32*60*SafeFPS/(Settings.BladeCount*TargetRPM[fsHigh]));
  Result.TrailSpin := Frac(Drive.Turns*TrailRate)*2*Pi;
  Result.Spin := Drive.Angle;
  Result.Pressed := Drive.Command;
end;

end.
