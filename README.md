# Smart Chassis Vibration Analysis System — Hardware Design & Simulation

A single MATLAB script that walks through the **hardware design** of a chassis
vibration monitoring system — accelerometer selection, anti-alias filter
sizing, ADC resolution, LED/power budgeting, an FFT-based fault-detection
algorithm, and a persistence-based warning telltale — and validates each
design choice against **simulated** sensor data before anything is built.

No physical hardware is required to run this repo. Every sensor reading,
noise source, and vibration signature is generated numerically inside
MATLAB; the script uses the resulting synthetic data to prove out the
detection logic and print a bill of materials and pin map you could hand
to someone building the board.

## What the script does

The script runs top to bottom and produces console output plus 5 figures:

| Section | What it covers |
|---|---|
| 1. Design parameters | Accelerometer spec (ADXL335), supply voltage, ADC bit depth, sample rate/oversampling ratio, detection sensitivity (`kSigma`) and alarm persistence |
| 2. Component calculations | Anti-alias capacitor value (nearest E12), ADC resolution in g, sensor noise floor and dynamic range, LED current-limit resistors (nearest E24), 12 V→3.3 V power budget, estimated FFT execution time and RAM use on an STM32F4 |
| 3. **Figure 1** | Hardware block diagram: sensors → anti-alias filter → MCU → LED driver → telltale, plus power section |
| 4. **Figure 2** | Anti-alias filter frequency response (analog RC stage × oversample-averaging stage) with alias-rejection at the fold-back frequency |
| 5. **Figure 3** | Signal chain demo — true simulated vibration vs. what the MCU actually sees after sensor noise, filtering, and 12-bit quantization |
| 6. Baseline + thresholds | Learns per-sensor thresholds (RMS, kurtosis, high-frequency energy ratio) from simulated healthy-chassis data, `mean + kSigma·std` |
| 7. Drive simulation + **Figure 4** | A simulated drive with a pothole event (all sensors) and a developing crack (rear sensor only, from t = 19 s); shows the resulting green/amber/red telltale timeline |
| 8. **Figure 5** | Healthy vs. cracked vibration spectrum, showing the resonance frequency drop that signals a stiffness loss |
| 9. BOM + pin map | Printed bill of materials and an example STM32 pin assignment |

## Requirements

- MATLAB R2016b or later (the script uses local functions defined at the
  end of a script file, which requires R2016b+)
- **No toolboxes.** Only base MATLAB functions are used (`fft`, `filter`,
  `rectangle`, `quiver`, `lines`, etc.)

## Running it

```matlab
>> chassis_vibration_hw_sim
```

(Save the script under this name, or whatever you prefer — just update the
command above to match.) Running it prints the hardware design summary,
threshold table, telltale results, BOM, and pin map to the console, and
opens the 5 figures described above.

## Suggested repo structure

```
├── chassis_vibration_hw_sim.m   # the script in this document
├── README.md
└── figures/                     # optional: exported PNGs of the 5 figures
```

## Customizing

- **Sensor count/placement** — edit `hw.sensorNames`.
- **Sampling and filtering** — `hw.fs`, `hw.osr`, `hw.fmax` control sample
  rate, oversampling, and the anti-alias filter's target cutoff.
- **Detection sensitivity** — `hw.kSigma` (threshold width) and
  `hw.persist` (consecutive abnormal windows before RED).
- **Fault scenario** — Section 7 hard-codes the pothole at `k == 11` and
  the crack onset at `k >= 19, s == 3`; change these to test other timings
  or sensor locations.
- **Bill of materials** — the `BOM` cell array at the bottom; add or swap
  parts as your actual build changes.

## Limitations

- Component values (capacitor, resistors) are computed from datasheet-typical
  parameters and standard E12/E24 series values — no physical board has been
  built or bench-tested against these numbers.
- `chassisSignal()` generates synthetic vibration (resonant modes + road
  noise + engine harmonics); it is a model of expected behavior, not
  measured data from a real vehicle.
- Intended as a design-and-validation aid and coursework deliverable, not
  as a certified automotive safety system.

## License

Add a license of your choice here (MIT is a common default for coursework
repos) — e.g. `MIT License, Copyright (c) 2026 <your name>`.

## Author

<your name> — <course / project name>
