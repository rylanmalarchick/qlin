(* C6 statistics recomputed from results/*.json: the 60-pair run
   (notes/c6-prereg.txt, bench/analyze_c6.py) and the amplified design C6b
   (notes/c6b-prereg.txt, bench/analyze_c6b.py). Each analysis follows the
   prereg text; the tests are Wolfram's own (TTest, SignedRankTest,
   ShapiroWilkTest).
   Run from the repo root: wolframscript -file notes/wolfram/c6_stats.wl *)
times[path_]:=Association[#["variant"]->#["times"]/1000.&/@
  Select[Import[path,"RawJSON"],StringEndsQ[#["benchmark"],"five_qubit_code.qlin"]&]];
ci[x_]:=Mean[x]+{-1,1}*Quantile[StudentTDistribution[Length[x]-1],0.975]*StandardDeviation[x]/Sqrt[Length[x]];

(* 60 pairs: d = source - best defer per round; drop a pair when |d| > 1000 us. *)
t60=times["results/phase4_ibm_five_qubit_n60.json"];
n60=Min[Length[t60["source"]],Length[t60["best_defer"]]];
d=Take[t60["source"],n60]-Take[t60["best_defer"],n60];
kept=Select[d,Abs[#]<=1000.&];
Print[<|"n60_pairs"->Length[d],"n60_dropped"->Length[d]-Length[kept],
 "n60_mean"->Mean[kept],"n60_se"->StandardDeviation[kept]/Sqrt[Length[kept]],"n60_ci"->ci[kept],
 "n60_t_vs_19_p"->TTest[kept,19.],"n60_wilcoxon_p"->SignedRankTest[d],"n60_median"->Median[d],
 "n60_shapiro_p"->ShapiroWilkTest[kept]|>];

(* C6b: per round, the least-squares slope of time per shot on k for each
   variant, without jobs more than 1000 us above the median of their
   (variant, k) cell; the gap is source slope - defer slope. *)
tb=Association[Normal[times["results/phase7_c6b.json"]]];
ks={1,2,4,8}; vs={"source","best_defer"};
cell[v_,k_]:=tb[v<>"_x"<>ToString[k]];
rounds=Min[Length/@Flatten[Table[cell[v,k],{v,vs},{k,ks}],1]];
med=Association[Flatten[Table[{v,k}->Median[Take[cell[v,k],rounds]],{v,vs},{k,ks}]]];
slope[pts_]:=If[Length[Union[pts[[All,1]]]]<2,Missing[],
  Module[{kb=Mean[pts[[All,1]]],vb=Mean[pts[[All,2]]]},
   Total[(pts[[All,1]]-kb)*(pts[[All,2]]-vb)]/Total[(pts[[All,1]]-kb)^2]]];
keptPts[v_,r_]:=Select[Table[{k,cell[v,k][[r]]},{k,ks}],#[[2]]-med[{v,#[[1]]}]<=1000.&];
dropped=Total[Table[4-Length[keptPts[v,r]],{v,vs},{r,rounds}],2];
gaps=DeleteMissing[Table[With[{a=slope[keptPts["source",r]],b=slope[keptPts["best_defer",r]]},
  If[MissingQ[a]||MissingQ[b],Missing[],a-b]],{r,rounds}]];
Print[<|"c6b_rounds"->rounds,"c6b_both"->Length[gaps],"c6b_dropped"->dropped,
 "c6b_mean"->Mean[gaps],"c6b_se"->StandardDeviation[gaps]/Sqrt[Length[gaps]],"c6b_ci"->ci[gaps],
 "c6b_t_vs_19.22_p"->TTest[gaps,19.22],"c6b_wilcoxon_p"->SignedRankTest[gaps],
 "c6b_shapiro_p"->ShapiroWilkTest[gaps]|>];
