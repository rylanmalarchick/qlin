# Full-switch ablation of the Phase 8.1 sweep

full: the fast path with t = m, where m is the number of group bits of
that variant (the sink changes the groups, so the sink variant has its
own m). A full switch counts only if it covers every outcome: exit
probability <= 1e-12 and no generic group under the size limit
S = 4096. spec: the best variant of the same kind with t < m
(t <= 6), from results/phase8_switch.csv. Pairs: no sink with no
sink, sink with sink. margin = (full - spec) / full; positive means
the speculative budget beats the full switch of the same kind. Same
model as phase8_switch: block sync, HERON_LIKE (assumed values),
t_ff = 600 ns, exact outcome records. Rows with m = 0 are left out.

## Summary

Columns per kind: pairs (full covered and spec present), full gains >= 10%,
spec gains >= 10%, spec beats full by > 1%, largest margin.

| class | t_branch (ns) | switch | no sink: pairs | full >= 10% | spec >= 10% | spec > full + 1% | max margin | sink: pairs | full >= 10% | spec >= 10% | spec > full + 1% | max margin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| none | 0 | table | 42 | 0 | 0 | 0 | 0.3% (dynamarq/five_qubit_code_noisy) | 20 | 0 | 0 | 0 | 0.0% (dynamarq/five_qubit_code) |
| qubic | 14 | chain | 42 | 6 | 6 | 2 | 2.7% (dynamarq/fanout4) | 20 | 0 | 0 | 5 | 6.3% (dynamarq/ghz5) |
| qubic | 14 | table | 42 | 6 | 6 | 0 | 0.0% (dynamarq/five_qubit_code) | 20 | 0 | 0 | 0 | 0.0% (dynamarq/ipe3) |
| qubic | 14 | tree | 42 | 6 | 6 | 0 | 0.0% (hand/mbqc_chain4) | 20 | 0 | 0 | 1 | 1.9% (dynamarq/ghz5) |
| qick | 42 | chain | 42 | 9 | 9 | 7 | 7.4% (dynamarq/fanout4) | 20 | 0 | 0 | 8 | 16.4% (dynamarq/ghz5) |
| qick | 42 | table | 42 | 9 | 9 | 0 | 0.0% (dynamarq/five_qubit_code) | 20 | 0 | 0 | 0 | 0.0% (dynamarq/ipe3) |
| qick | 42 | tree | 42 | 9 | 9 | 0 | 0.0% (hand/mbqc_chain4) | 20 | 0 | 0 | 1 | 5.5% (dynamarq/ghz5) |
| ibm | 3450 | chain | 42 | 13 | 13 | 11 | 50.7% (dynamarq/fanout4) | 20 | 0 | 0 | 12 | 68.2% (dynamarq/ghz5) |
| ibm | 3450 | table | 42 | 13 | 13 | 0 | 0.0% (dynamarq/five_qubit_code) | 20 | 2 | 2 | 0 | 0.0% (dynamarq/ipe3) |
| ibm | 3450 | tree | 42 | 13 | 13 | 0 | 0.0% (dynamarq/five_qubit_code) | 20 | 2 | 2 | 2 | 34.5% (dynamarq/ghz5) |

## Pairs where a full or spec variant gains at least 1%

| benchmark | class | switch | best baseline | no sink: full | spec (t) | margin | sink: full | spec (t) | margin |
|---|---|---|---|---|---|---|---|---|---|
| dynamarq/five_qubit_code | ibm | table | 55236 | 12052 | 12052 (4) | 0.0% | 11374 | 22115 (5) | -94.4% |
| dynamarq/five_qubit_code | ibm | tree | 55236 | 22402 | 22402 (4) | 0.0% | 35524 | 46265 (5) | -30.2% |
| dynamarq/five_qubit_code | ibm | chain | 55236 | 39221 | 39221 (4) | 0.0% | 88136 | 73561 (0) | 16.5% |
| dynamarq/five_qubit_code_noisy | ibm | table | 55236 | 12052 | 12894 (4) | -7.0% | 11364 | 22124 (5) | -94.7% |
| dynamarq/five_qubit_code_noisy | ibm | tree | 55236 | 22402 | 23244 (4) | -3.8% | 35514 | 46274 (5) | -30.3% |
| dynamarq/five_qubit_code_noisy | ibm | chain | 55236 | 39397 | 40068 (4) | -1.7% | 88422 | 71520 (2) | 19.1% |
| dynamarq/repetition3_1_noisy | none | table | 2660 | 2743 | 2743 (0) | 0.0% | 2577 | 2577 (0) | 0.0% |
| dynamarq/repetition3_1_noisy | qubic | table | 2660 | 2757 | 2759 (1) | -0.1% | 2604 | 2605 (2) | -0.1% |
| dynamarq/repetition3_1_noisy | qubic | tree | 2660 | 2771 | 2773 (1) | -0.1% | 2631 | 2633 (0) | -0.1% |
| dynamarq/repetition3_1_noisy | qubic | chain | 2660 | 2761 | 2762 (0) | -0.0% | 2611 | 2607 (0) | 0.2% |
| dynamarq/repetition5_0_noisy | qubic | table | 2986 | 2865 | 2866 (3) | -0.0% |  | 2904 (4) |  |
| dynamarq/repetition5_0_noisy | qubic | tree | 2986 | 2907 | 2908 (3) | -0.0% |  | 3064 (2) |  |
| dynamarq/repetition5_0_noisy | qubic | chain | 2986 | 2884 | 2884 (3) | -0.0% |  | 2933 (2) |  |
| dynamarq/repetition5_0_noisy | qick | table | 3406 | 2893 | 2895 (3) | -0.0% |  | 3025 (4) |  |
| dynamarq/repetition5_0_noisy | qick | tree | 3406 | 3019 | 3021 (3) | -0.0% |  | 3503 (2) |  |
| dynamarq/repetition5_0_noisy | qick | chain | 3406 | 2948 | 2949 (3) | -0.0% |  | 3109 (2) |  |
| dynamarq/repetition5_0_noisy | ibm | table | 54526 | 6301 | 6418 (3) | -1.9% |  | 17690 (4) |  |
| dynamarq/repetition5_0_noisy | ibm | tree | 54526 | 16651 | 16768 (3) | -0.7% |  | 56974 (2) |  |
| dynamarq/repetition5_0_noisy | ibm | chain | 54526 | 10819 | 10928 (3) | -1.0% |  | 24627 (2) |  |
| dynamarq/repetition5_1_noisy | none | table | 3151 | 3151 | 3151 (0) | 0.0% |  | 2851 (0) |  |
| dynamarq/repetition5_1_noisy | qubic | table | 3358 | 3165 | 3166 (3) | -0.0% |  | 2904 (4) |  |
| dynamarq/repetition5_1_noisy | qubic | tree | 3358 | 3207 | 3208 (3) | -0.0% |  | 3064 (2) |  |
| dynamarq/repetition5_1_noisy | qubic | chain | 3358 | 3183 | 3184 (3) | -0.0% |  | 2933 (2) |  |
| dynamarq/repetition5_1_noisy | qick | table | 3778 | 3193 | 3194 (3) | -0.0% |  | 3025 (4) |  |
| dynamarq/repetition5_1_noisy | qick | tree | 3778 | 3319 | 3320 (3) | -0.0% |  | 3503 (2) |  |
| dynamarq/repetition5_1_noisy | qick | chain | 3778 | 3248 | 3249 (3) | -0.0% |  | 3109 (2) |  |
| dynamarq/repetition5_1_noisy | ibm | table | 54898 | 6601 | 6718 (3) | -1.8% |  | 17690 (4) |  |
| dynamarq/repetition5_1_noisy | ibm | tree | 54898 | 16951 | 17068 (3) | -0.7% |  | 56974 (2) |  |
| dynamarq/repetition5_1_noisy | ibm | chain | 54898 | 11119 | 11228 (3) | -1.0% |  | 24627 (2) |  |
| dynamarq/steane_noisy | none | table | 3789 | 3789 | 3789 (0) | 0.0% |  | 3248 (0) |  |
| dynamarq/steane_noisy | qubic | table | 3887 | 3803 | 3803 (3) | 0.0% |  | 3346 (0) |  |
| dynamarq/steane_noisy | qubic | tree | 3887 | 3873 | 3873 (3) | 0.0% |  | 3483 (0) |  |
| dynamarq/steane_noisy | qubic | chain | 3887 | 3871 | 3836 (0) | 0.9% |  | 3346 (0) |  |
| dynamarq/steane_noisy | qick | table | 4114 | 3831 | 3831 (3) | 0.0% |  | 3542 (3) |  |
| dynamarq/steane_noisy | qick | tree | 4114 | 4041 | 4041 (3) | 0.0% |  | 3953 (4) |  |
| dynamarq/steane_noisy | qick | chain | 4114 | 4035 | 3941 (0) | 2.3% |  | 3549 (3) |  |
| dynamarq/steane_noisy | ibm | table | 51444 | 7239 | 7239 (3) | 0.0% |  | 30612 (3) |  |
| dynamarq/steane_noisy | ibm | tree | 51444 | 24489 | 24489 (3) | 0.0% |  | 71278 (4) |  |
| dynamarq/steane_noisy | ibm | chain | 51444 | 23998 | 21258 (1) | 11.4% |  | 34765 (3) |  |
| qec/repetition11_0_noisy | qubic | table | 17914 | 3688 | 3692 (6) | -0.1% |  | 3712 (6) |  |
| qec/repetition11_0_noisy | qubic | tree | 17914 | 3814 | 3818 (6) | -0.1% |  | 3981 (6) |  |
| qec/repetition11_0_noisy | qubic | chain | 17914 | 4100 | 4103 (6) | -0.1% |  | 4124 (6) |  |
| qec/repetition11_0_noisy | qick | table | 46558 | 3716 | 3727 (6) | -0.3% |  | 3816 (6) |  |
| qec/repetition11_0_noisy | qick | tree | 46558 | 4094 | 4105 (6) | -0.3% |  | 4624 (6) |  |
| qec/repetition11_0_noisy | qick | chain | 46558 | 4952 | 4963 (6) | -0.2% |  | 5051 (6) |  |
| qec/repetition11_0_noisy | ibm | table | 3532942 | 7124 | 8074 (6) | -13.3% |  | 16445 (6) |  |
| qec/repetition11_0_noisy | ibm | tree | 3532942 | 38174 | 39124 (6) | -2.5% |  | 82818 (6) |  |
| qec/repetition11_0_noisy | ibm | chain | 3532942 | 108679 | 109550 (6) | -0.8% |  | 117921 (6) |  |
| qec/repetition11_1_noisy | none | table | 4375 | 4375 | 4375 (0) | 0.0% |  | 3674 (0) |  |
| qec/repetition11_1_noisy | qubic | table | 18694 | 4389 | 4393 (6) | -0.1% |  | 3700 (6) |  |
| qec/repetition11_1_noisy | qubic | tree | 18694 | 4515 | 4519 (6) | -0.1% |  | 3904 (6) |  |
| qec/repetition11_1_noisy | qubic | chain | 18694 | 4801 | 4805 (6) | -0.1% |  | 4117 (6) |  |
| qec/repetition11_1_noisy | qick | table | 47338 | 4417 | 4429 (6) | -0.3% |  | 3771 (6) |  |
| qec/repetition11_1_noisy | qick | tree | 47338 | 4795 | 4807 (6) | -0.2% |  | 4388 (6) |  |
| qec/repetition11_1_noisy | qick | chain | 47338 | 5653 | 5664 (6) | -0.2% |  | 5025 (6) |  |
| qec/repetition11_1_noisy | ibm | table | 3533722 | 7825 | 8776 (6) | -12.1% |  | 12790 (6) |  |
| qec/repetition11_1_noisy | ibm | tree | 3533722 | 38875 | 39826 (6) | -2.4% |  | 63466 (6) |  |
| qec/repetition11_1_noisy | ibm | chain | 3533722 | 109380 | 110251 (6) | -0.8% |  | 115822 (6) |  |
| qec/repetition7_0_noisy | qubic | table | 3930 | 3140 | 3140 (5) | -0.0% |  | 3162 (6) |  |
| qec/repetition7_0_noisy | qubic | tree | 3930 | 3210 | 3210 (5) | -0.0% |  | 3335 (6) |  |
| qec/repetition7_0_noisy | qubic | chain | 3930 | 3196 | 3196 (5) | -0.0% |  | 3219 (6) |  |
| qec/repetition7_0_noisy | qick | table | 5694 | 3168 | 3168 (5) | -0.0% |  | 3253 (6) |  |
| qec/repetition7_0_noisy | qick | tree | 5694 | 3378 | 3378 (5) | -0.0% |  | 3772 (6) |  |
| qec/repetition7_0_noisy | qick | chain | 5694 | 3336 | 3336 (5) | -0.0% |  | 3424 (6) |  |
| qec/repetition7_0_noisy | ibm | table | 220398 | 6576 | 6599 (5) | -0.4% |  | 14380 (6) |  |
| qec/repetition7_0_noisy | ibm | tree | 220398 | 23826 | 23849 (5) | -0.1% |  | 56991 (6) |  |
| qec/repetition7_0_noisy | ibm | chain | 220398 | 20378 | 20400 (5) | -0.1% |  | 28435 (6) |  |
| qec/repetition7_1_noisy | none | table | 3559 | 3559 | 3559 (0) | 0.0% |  | 3126 (0) |  |
| qec/repetition7_1_noisy | qubic | table | 4438 | 3573 | 3573 (5) | -0.0% |  | 3150 (6) |  |
| qec/repetition7_1_noisy | qubic | tree | 4438 | 3643 | 3643 (5) | -0.0% |  | 3284 (6) |  |
| qec/repetition7_1_noisy | qubic | chain | 4438 | 3629 | 3629 (5) | -0.0% |  | 3228 (2) |  |
| qec/repetition7_1_noisy | qick | table | 6202 | 3601 | 3601 (5) | -0.0% |  | 3201 (6) |  |
| qec/repetition7_1_noisy | qick | tree | 6202 | 3811 | 3811 (5) | -0.0% |  | 3621 (6) |  |
| qec/repetition7_1_noisy | qick | chain | 6202 | 3769 | 3769 (5) | -0.0% |  | 3450 (2) |  |
| qec/repetition7_1_noisy | ibm | table | 220906 | 7009 | 7032 (5) | -0.3% |  | 10108 (6) |  |
| qec/repetition7_1_noisy | ibm | tree | 220906 | 24259 | 24282 (5) | -0.1% |  | 44608 (6) |  |
| qec/repetition7_1_noisy | ibm | chain | 220906 | 20811 | 20834 (5) | -0.1% |  | 30587 (2) |  |
| qec/repetition9_0_noisy | qubic | table | 6890 | 3414 | 3414 (6) | -0.0% |  | 3435 (6) |  |
| qec/repetition9_0_noisy | qubic | tree | 6890 | 3512 | 3512 (6) | -0.0% |  | 3657 (6) |  |
| qec/repetition9_0_noisy | qubic | chain | 6890 | 3567 | 3568 (6) | -0.0% |  | 3589 (6) |  |
| qec/repetition9_0_noisy | qick | table | 14030 | 3442 | 3442 (6) | -0.0% |  | 3530 (6) |  |
| qec/repetition9_0_noisy | qick | tree | 14030 | 3736 | 3736 (6) | -0.0% |  | 4195 (6) |  |
| qec/repetition9_0_noisy | qick | chain | 14030 | 3903 | 3903 (6) | -0.0% |  | 3991 (6) |  |
| qec/repetition9_0_noisy | ibm | table | 883070 | 6850 | 6890 (6) | -0.6% |  | 15053 (6) |  |
| qec/repetition9_0_noisy | ibm | tree | 883070 | 31000 | 31040 (6) | -0.1% |  | 69645 (6) |  |
| qec/repetition9_0_noisy | ibm | chain | 883070 | 44701 | 44741 (6) | -0.1% |  | 52904 (6) |  |
| qec/repetition9_1_noisy | none | table | 3967 | 3967 | 3967 (0) | 0.0% |  | 3400 (0) |  |
| qec/repetition9_1_noisy | qubic | table | 7534 | 3981 | 3981 (6) | -0.0% |  | 3423 (6) |  |
| qec/repetition9_1_noisy | qubic | tree | 7534 | 4079 | 4079 (6) | -0.0% |  | 3599 (6) |  |
| qec/repetition9_1_noisy | qubic | chain | 7534 | 4135 | 4135 (6) | -0.0% |  | 3603 (6) |  |
| qec/repetition9_1_noisy | qick | table | 14674 | 4009 | 4010 (6) | -0.0% |  | 3479 (6) |  |
| qec/repetition9_1_noisy | qick | tree | 14674 | 4303 | 4304 (6) | -0.0% |  | 4020 (6) |  |
| qec/repetition9_1_noisy | qick | chain | 14674 | 4470 | 4470 (6) | -0.0% |  | 4032 (6) |  |
| qec/repetition9_1_noisy | ibm | table | 883714 | 7417 | 7457 (6) | -0.5% |  | 10892 (6) |  |
| qec/repetition9_1_noisy | ibm | tree | 883714 | 31567 | 31607 (6) | -0.1% |  | 55336 (6) |  |
| qec/repetition9_1_noisy | ibm | chain | 883714 | 45269 | 45308 (6) | -0.1% |  | 56251 (6) |  |
| qec/surface3_0_noisy | none | table | 3756 | 3758 | 3758 (0) | 0.0% |  | 3488 (0) |  |
| qec/surface3_0_noisy | qubic | table | 3924 | 3772 | 3772 (4) | 0.0% |  | 3549 (3) |  |
| qec/surface3_0_noisy | qubic | tree | 3924 | 3870 | 3870 (4) | 0.0% |  | 3710 (3) |  |
| qec/surface3_0_noisy | qubic | chain | 3924 | 3877 | 3858 (1) | 0.5% |  | 3563 (2) |  |
| qec/surface3_0_noisy | qick | table | 4748 | 3800 | 3800 (4) | 0.0% |  | 3670 (3) |  |
| qec/surface3_0_noisy | qick | tree | 4748 | 4094 | 4094 (4) | 0.0% |  | 4155 (3) |  |
| qec/surface3_0_noisy | qick | chain | 4748 | 4115 | 4082 (1) | 0.8% |  | 3750 (2) |  |
| qec/surface3_0_noisy | ibm | table | 106988 | 7208 | 7208 (4) | 0.0% |  | 21775 (3) |  |
| qec/surface3_0_noisy | ibm | tree | 106988 | 31358 | 31358 (4) | 0.0% |  | 71928 (3) |  |
| qec/surface3_0_noisy | ibm | chain | 106988 | 33132 | 31148 (2) | 6.0% |  | 31678 (2) |  |
| qec/surface3_1_noisy | qick | table | 4392 | 4070 | 4070 (4) | 0.0% |  | 3943 (3) |  |
| qec/surface3_1_noisy | qick | chain | 4392 | 4386 | 4331 (1) | 1.3% |  | 4226 (1) |  |
| qec/surface3_1_noisy | ibm | table | 106616 | 7478 | 7478 (4) | 0.0% |  | 18773 (3) |  |
| qec/surface3_1_noisy | ibm | tree | 106616 | 31628 | 31628 (4) | 0.0% |  | 65194 (5) |  |
| qec/surface3_1_noisy | ibm | chain | 106616 | 33402 | 31415 (2) | 5.9% |  | 42009 (1) |  |

## Gain against the budget t (qick, tree, no sink)

cases: sum over k <= t of C(m, k), the number of switch cases of a
program with one dispatch group. Each program below has one group
(`qlin fastpath --json` reports groups = 1 and this size).

| benchmark | m | full gain (2^m cases) | gain at t (cases) |
|---|---|---|---|
| dynamarq/repetition5_0_noisy | 4 | 11.4% (16) | t=0: 7.4% (1), t=1: 8.9% (5), t=2: 11.2% (11), t=3: 11.3% (15) |
| dynamarq/repetition5_1_noisy | 4 | 12.1% (16) | t=0: 8.5% (1), t=1: 9.9% (5), t=2: 12.0% (11), t=3: 12.1% (15) |
| qec/repetition11_0_noisy | 10 | 91.2% (1024) | t=0: 51.4% (1), t=1: 57.3% (11), t=2: 83.5% (56), t=3: 86.1% (176), t=4: 90.5% (386), t=5: 90.9% (638), t=6: 91.2% (848) |
| qec/repetition11_1_noisy | 10 | 89.9% (1024) | t=0: 50.7% (1), t=1: 56.5% (11), t=2: 82.3% (56), t=3: 84.8% (176), t=4: 89.2% (386), t=5: 89.6% (638), t=6: 89.8% (848) |
| qec/repetition7_0_noisy | 6 | 40.7% (64) | t=0: 26.8% (1), t=1: 30.4% (7), t=2: 39.3% (22), t=3: 40.1% (42), t=4: 40.6% (57), t=5: 40.7% (63) |
| qec/repetition7_1_noisy | 6 | 38.6% (64) | t=0: 25.7% (1), t=1: 29.0% (7), t=2: 37.3% (22), t=3: 38.0% (42), t=4: 38.5% (57), t=5: 38.5% (63) |
| qec/repetition9_0_noisy | 8 | 73.4% (256) | t=0: 45.2% (1), t=1: 50.6% (9), t=2: 69.2% (37), t=3: 71.0% (93), t=4: 73.1% (163), t=5: 73.3% (219), t=6: 73.4% (247) |
| qec/repetition9_1_noisy | 8 | 70.7% (256) | t=0: 43.7% (1), t=1: 48.8% (9), t=2: 66.7% (37), t=3: 68.4% (93), t=4: 70.5% (163), t=5: 70.6% (219), t=6: 70.7% (247) |
| qec/surface3_0_noisy | 8 | 13.8% (256) | t=0: 4.9% (1), t=1: 10.2% (9), t=2: 13.3% (37), t=3: 13.7% (93), t=4: 13.8% (163), t=5: 13.8% (219), t=6: 13.8% (247) |
