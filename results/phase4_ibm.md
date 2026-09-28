# Phase 4 IBM run (measured)

Backend ibm_kingston, 2026-09-27.
Model durations from the backend target (ns): {'t1q': 32.0, 't2q': 68.0, 'tmeas': 1380.0, 'treset': 2212.0}, t_ff 600.
1000 shots per job, 3 jobs per circuit. Measured time per shot is the
execution-span total over the shots, so it includes the repetition delay,
which is the same for every circuit.

## Branch-cost probe

| if_else blocks | per shot (us), mean +- sd |
|---|---|
| 0 | 1100.28 +- 7.70 |
| 1 | 1106.98 +- 16.31 |
| 2 | 1098.07 +- 4.30 |
| 4 | 1119.98 +- 11.85 |
| 8 | 1126.18 +- 30.89 |

Least-squares slope: 3.45 us per if_else block.

## Benchmark variants

| benchmark | variant | model ideal (ns) | model block (ns) | measured per shot (us) | note |
|---|---|---|---|---|---|
| benchmarks/jeff/teleportation.qlin | source | 3105 | 3608 | 1121.26 +- 27.67 |  |
| benchmarks/jeff/teleportation.qlin | best_defer | 1716 | 1716 | 1292.65 +- 306.68 |  |
| benchmarks/jeff/teleportation.qlin | sink_only | 3081 | 3576 | 1143.91 +- 22.56 |  |
| benchmarks/jeff/teleportation.qlin | fast_t1 | 3624 | 3624 | - | measure inside a conditional |
| benchmarks/jeff/teleportation.qlin | sink_fast_t1 | 3592 | 3592 | - | measure inside a conditional |
| benchmarks/dynamarq/five_qubit_code.qlin | source | 5764 | 6854 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/five_qubit_code.qlin | best_defer | 4688 | 4922 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/five_qubit_code.qlin | sink_only | 5369 | 6212 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/five_qubit_code.qlin | fast_t1 | 6458 | 6886 | - | measure inside a conditional |
| benchmarks/dynamarq/five_qubit_code.qlin | sink_fast_t1 | 5912 | 6212 | - | measure inside a conditional |
| benchmarks/dynamarq/repetition5_0.qlin | source | 2024 | 4004 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/repetition5_0.qlin | best_defer | 2024 | 4004 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/repetition5_0.qlin | sink_only | 2024 | 4004 | - | "Unable to retrieve job result. Error code 1500; Failed to execute program: 'Internal error. -- Try again or contact support. -- https://ibm.biz/error_codes#1500" |
| benchmarks/dynamarq/repetition5_0.qlin | fast_t1 | 4004 | 4004 | - | measure inside a conditional |
| benchmarks/dynamarq/repetition5_0.qlin | sink_fast_t1 | 4004 | 4004 | - | measure inside a conditional |

## Rank correlation (Spearman, per benchmark, measured means)

- benchmarks/dynamarq/five_qubit_code.qlin: 0 variants measured, too few for a rank correlation
- benchmarks/dynamarq/repetition5_0.qlin: 0 variants measured, too few for a rank correlation
- benchmarks/jeff/teleportation.qlin: ideal -1.00, block -1.00 (n = 3)

## Interpretation (2026-09-27)

- Timing resolution: identical jobs differ by 7.7 us per shot (sd, k = 0
  probe), and one best_defer job took 1646 us against about 1100 us for
  the others. Every modeled teleportation variant takes 2 to 7 us, so the
  three teleportation variants are not separable with this method. Their
  Spearman -1.00 is noise, not a finding.
- Branch cost: the probe slope is 3.45 us per if_else block, 95% CI
  0.32 to 6.58 us (n = 15 jobs, least squares). Each probe If reads the
  same bit, so t_ff is paid once, and the slope is t_branch plus one x
  gate (32 ns). This is the first measured value for t_branch, which
  the sensitivity analysis swept only to 1 us.
- Error 1500 (IBM "Internal error") on every five_qubit_code and
  repetition5 variant. These are the programs whose conditions read
  multi-bit registers. The bridge builds those registers by aliasing bits
  of `c`. Aliased registers are the likely cause. Not verified.
- The fast path cannot run on IBM in any form: IBM rejects a measure
  inside a conditional, and a fast-path case holds the rest of the
  program. The six fast-path variants were skipped for that reason.
- Model at the measured t_branch (HERON_KINGSTON, live measure_2 of
  1380 ns, Block model): five_qubit_code source about 75 us, best defer
  about 56 us. repetition5_0_noisy source about 56 us, fast path about
  7 us. Gaps of 20 us or more are larger than the job noise. The five_qubit
  source-against-defer gap is testable once error 1500 is fixed.
- Live calibration: measure_2 median is 1380 ns (snapshot 1760 ns) and
  reset is 2212 ns (snapshot 2312 ns).
- Device time used by this run: 60 s of the 600 s Open Plan.
