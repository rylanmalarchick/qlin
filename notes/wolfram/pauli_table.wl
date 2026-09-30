(* Pauli conjugation table of src/pauli.rs, as stated in lean/Qlin/PauliTable.lean.
   Checks C * P == phi * P' * C with phi = +-1 for every input Pauli.
   Run: wolfram -script notes/wolfram/pauli_table.wl *)
pX={{0,1},{1,0}}; pY={{0,-I},{I,0}}; pZ={{1,0},{0,-1}};
pauli[x_,z_]:=Which[!x&&!z,IdentityMatrix[2],x&&!z,pX,x&&z,pY,True,pZ];
pauli2[x1_,z1_,x2_,z2_]:=KroneckerProduct[pauli[x1,z1],pauli[x2,z2]];
hM={{1,1},{1,-1}}; sM={{1,0},{0,I}}; sdgM={{1,0},{0,-I}}; sxM={{1+I,1-I},{1-I,1+I}};
mk[f_]:=Table[f[{Quotient[i,2],Mod[i,2]},{Quotient[j,2],Mod[j,2]}],{i,0,3},{j,0,3}];
cxM=mk[If[#1[[1]]==#2[[1]]&&#1[[2]]==Mod[#2[[2]]+#2[[1]],2],1,0]&];
czM=mk[If[#1==#2,If[#1=={1,1},-1,1],0]&];
cyM=mk[If[#1[[1]]==#2[[1]],If[#2[[1]]==0,If[#1[[2]]==#2[[2]],1,0],pY[[#1[[2]]+1,#2[[2]]+1]]],0]&];
swapM=mk[If[#1=={#2[[2]],#2[[1]]},1,0]&];
tH[x_,z_]:={z,x}; tS[x_,z_]:={x,Xor[z,x]}; tSX[x_,z_]:={Xor[x,z],z};
tCX[xc_,zc_,xt_,zt_]:={{xc,Xor[zc,zt]},{Xor[xt,xc],zt}};
tCZ[xa_,za_,xb_,zb_]:={{xa,Xor[za,xb]},{xb,Xor[zb,xa]}};
tCY[xc_,zc_,xt_,zt_]:=Module[{t1=tS[xt,zt],r},r=tCX[xc,zc,t1[[1]],t1[[2]]];{r[[1]],tS@@r[[2]]}];
ok1[G_,t_]:=AllTrue[Tuples[{True,False},2],Function[p,With[{q=t@@p},AnyTrue[{1,-1},G.pauli@@p==# pauli@@q.G&]]]];
ok2[G_,t_]:=AllTrue[Tuples[{True,False},4],Function[p,With[{q=Flatten[t@@p]},AnyTrue[{1,-1},G.pauli2@@p==# pauli2@@q.G&]]]];
okP=AllTrue[Tuples[{True,False},4],Function[p,AnyTrue[{1,-1},pauli[p[[1]],p[[2]]].pauli[p[[3]],p[[4]]]==# pauli[p[[3]],p[[4]]].pauli[p[[1]],p[[2]]]&]]];
Print[<|"h"->ok1[hM,tH],"s"->ok1[sM,tS],"sdg"->ok1[sdgM,tS],"sx"->ok1[sxM,tSX],"xyz"->okP,
 "cx"->ok2[cxM,tCX],"cz"->ok2[czM,tCZ],"cy"->ok2[cyM,tCY],"swap"->ok2[swapM,{{#3,#4},{#1,#2}}&],
 "cyIsSCXSdg"->(cyM==KroneckerProduct[IdentityMatrix[2],sM].cxM.KroneckerProduct[IdentityMatrix[2],sdgM]),
 "sxSq"->(sxM.sxM/4==pX)|>];
(* Negative control: planted wrong tables must fail. *)
Print[<|"planted_h_identity"->ok1[hM,{#1,#2}&],"planted_s_noflip"->ok1[sM,{#1,#2}&],
 "planted_cx_swapped_roles"->ok2[cxM,{{Xor[#1,#3],#2},{#3,Xor[#4,#2]}}&]|>];
