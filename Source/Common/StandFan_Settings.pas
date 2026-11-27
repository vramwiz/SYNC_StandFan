
unit StandFan_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 扇風機の共通設定、部位の標準色、および調整可能な範囲。

interface

type
  // 保存済みの設定と互換性を保つため、既存の識別値を維持する。
  TFanPreset = (fpShowaLate, fpHeisei, fpReiwa, fpShowaEarly);
  TFanSpeed = (fsOff, fsLow, fsMedium, fsHigh);
  TFanSwing = (swNone, swHorizontal);
  TFanMaterial = (fmFixed, fmBlade, fmCover, fmMotor, fmNeckUpper, fmNeckLower,
    fmBase, fmAccent);
  TFanColors = array[TFanMaterial] of Cardinal;

  TFanSettings = record
    Preset: TFanPreset;
    Speed: TFanSpeed;
    Swing: TFanSwing;
    BladeCount: Integer;
    // 速度は基準周期に対する百分率、可動範囲は度、伸長はローカル座標の長さ。
    SwingSpeed, HorizontalRange, VerticalRange, Extension: Single;
    Colors: TFanColors;
  end;

const
  MinBlades = 3;
  MaxBlades = 6;
  MaxExtension = 96;
  DefaultColors: TFanColors = (
    0, $37A4AD, $C6D4D7, $F6F1DC, $F6F1DC, $F6F1DC, $F6F1DC, $159173);
  HeiseiColors: TFanColors = (
    0, $DBE7ED, $E8ECEC, $EDF0EC, $F1F2EE, $E5EAE8, $F0EEE5, $D8E5E9);
  ReiwaColors: TFanColors = (
    0, $545C66, $3B4149, $292E35, $3B424A, $30363D, $25292F, $424A54);
  EarlyShowaColors: TFanColors = (
    0, $A4C4B6, $86A694, $769487, $8CA89A, $92B4A4, $A3C2B1, $89AA9A);

implementation

end.
