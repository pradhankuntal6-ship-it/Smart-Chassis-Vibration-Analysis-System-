# Smart Chassis Vibration Analysis System — Simulation, ML Detection & Prediction

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/pradhankuntal6-ship-it/Smart-Chassis-Vibration-Analysis-System-/blob/main/Copy_of_Welcome_To_Colab.ipynb)

A single Python/Colab notebook that simulates chassis vibration data for
three conditions (**Healthy**, **Crack**, **Loose joint**) at three sensor
locations, then builds and evaluates a full detection stack on top of it:
a hand-tuned threshold detector, an unsupervised anomaly detector
(Isolation Forest), a supervised fault classifier (Random Forest), fault
localization, a persistence-based green/amber/red telltale, and a simple
damage-progression forecast. No physical sensors or hardware are used —
every signal is generated numerically inside the notebook.

## What's inside

| Step | What it does |
|---|---|
| Signal simulation | `simulate()` generates 3-sensor acceleration data (g) from four resonant chassis modes plus road noise and 30/60 Hz engine harmonics. `Crack` lowers the resonance frequencies and raises damping/amplitude near the fault; `Loose joint` adds random high-frequency rattle impacts |
| Quick-look plots | Time-domain traces and Welch power spectra comparing Healthy vs. Crack vs. Loose joint at the front sensor |
| Feature extraction | `features()` computes 11 features per sensor (RMS, peak, crest factor, kurtosis, dominant frequency, spectral centroid, 5 band-energy ratios) → 33 features per 1-second window across 3 sensors |
| Threshold detector | Learns per-feature limits from healthy-only data (`mean + 4·std`) and flags any window that exceeds them |
| Anomaly detection | An `IsolationForest` trained only on healthy windows scores new windows as normal/abnormal without ever seeing a labeled fault |
| Fault classification | A `RandomForestClassifier` trained on all three labeled classes, evaluated with a classification report, confusion matrix, and a feature-importance chart |
| Fault localization | Flags whichever sensor's RMS deviates most (in σ) from its healthy baseline |
| Telltale simulation | Runs a simulated drive (healthy → pothole → healthy → developing loose joint) through the anomaly detector with a 3-window persistence rule before escalating to RED |
| Damage-progression forecast | Simulates a crack growing over 60 days, fits a quadratic trend to the early resonance-shift data, and extrapolates the day the shift crosses a −5% danger limit |
| Interactive demo | `ipywidgets` controls (condition / severity / fault location / pothole toggle) that re-run the full pipeline and plot signals + spectra for whatever scenario you pick |
| Manual check tool | `manual_check()` lets you type in real RMS/kurtosis readings and see the threshold verdict directly, without running the simulator |

## Requirements

```
numpy
scipy
matplotlib
scikit-learn
ipywidgets      # only needed for the interactive demo cell
```

Colab has all of these preinstalled, including `ipywidgets` — just open the
badge above. To run locally:

```bash
pip install numpy scipy matplotlib scikit-learn ipywidgets notebook
jupyter notebook
```

The interactive demo cell needs a live Jupyter/Colab front end to render
its widgets; it won't render on GitHub's static notebook preview, but the
notebook still runs top to bottom either way.

## Sample output

With the notebook's fixed random seeds, one run of the non-interactive
cells produced:

```
Dataset: (600, 33) | classes: [200 200 200]
Threshold detector  : Crack 100% | Loose 96% | False alarm 1%
Isolation Forest    : Crack 88%  | Loose 100% | False alarm 8%
Fault classifier    : accuracy 100.0%
Localisation        : 97%
First RED at t = 53 s (loose joint began at t = 51 s)
Predicted to cross the danger limit around day 40
```

Exact numbers can shift slightly with different library versions since
`RandomForest`/`IsolationForest` internals aren't guaranteed bit-identical
across scikit-learn releases, but they should land close to this.

## An honest caveat worth keeping in the report

The Random Forest classifier scores 100% accuracy here because it is
trained and tested on windows drawn from the **same synthetic generator**
— train and test data share the exact same fault model, just different
random draws. That's a fair way to validate that the feature set and
pipeline logic work end-to-end, but it is not evidence the system would
hit 100% on a real vehicle with real sensor noise, mounting variation, and
fault types the simulator didn't model. Say this explicitly in your
write-up; it's a much stronger project than one that lets the number speak
for itself.

## Suggested repo structure

```
├── chassis_vibration_analysis.ipynb   # rename from Copy_of_Welcome_To_Colab.ipynb
└── README.md
```

The Colab badge above points at the filename `Copy_of_Welcome_To_Colab.ipynb`
in your repo. If you rename the notebook file, update the badge URL to
match, or the "Open in Colab" link will 404.

## Limitations

- All vibration data is synthetic (`simulate()`), built from an assumed
  set of resonant modes, noise levels, and fault signatures — not measured
  from a physical chassis.
- Thresholds, severities, and fault models are illustrative choices, not
  calibrated against a real vehicle or a validated finite-element model.
- The Isolation Forest and Random Forest results describe how well the
  pipeline distinguishes the simulator's own fault classes, not real-world
  detection performance (see caveat above).

## License

Add a license of your choice here (MIT is a common default for coursework
repos) — e.g. `MIT License, Copyright (c) 2026 <your name>`.

## Author

<your name> — <course / project name>

