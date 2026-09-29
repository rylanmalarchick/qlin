(* IBM statistics (C6, C14) recomputed from results/*.json.
   Run from the repo root: wolfram -script notes/wolfram/ibm_stats.wl *)
n27=Import["results/phase4_ibm_five_qubit_n27.json","RawJSON"];
t=Association[#["variant"]->#["times"]/1000.&/@n27];
d=t["source"]-t["best_defer"]; keep=Select[d,Abs[#]<1000&];
ci[x_]:=Mean[x]+{-1,1}*Quantile[StudentTDistribution[Length[x]-1],0.975]*StandardDeviation[x]/Sqrt[Length[x]];
probe=Select[Import["results/phase4_ibm.json","RawJSON"],#["benchmark"]=="branch_probe"&];
pts=Flatten[Table[{p["k"],#/1000.}&/@p["times"],{p,probe}],1]; lm=LinearModelFit[pts,k,k];
Print[<|"pairs"->Length[d],"mean"->Mean[d],"se"->StandardDeviation[d]/Sqrt[Length[d]],
 "paired_t_p"->PairedTTest[{t["source"],t["best_defer"]}],"wilcoxon_p"->SignedRankTest[d],"median"->Median[d],
 "kept"->Length[keep],"kept_mean"->Mean[keep],"kept_se"->StandardDeviation[keep]/Sqrt[Length[keep]],
 "kept_ci"->ci[keep],"t_vs_0_p"->TTest[keep,0.],"t_vs_19_p"->TTest[keep,19.],
 "probe_points"->Length[pts],"slope_us"->lm["BestFitParameters"][[2]],"slope_ci"->lm["ParameterConfidenceIntervals"][[2]]|>];
