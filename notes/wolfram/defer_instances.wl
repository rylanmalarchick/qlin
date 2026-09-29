(* Defer rewrite on two instances: the classical program and the output of
   `qlin opt` (defer chosen) give the same cq state, exactly, for a symbolic
   input state {{a0,b0},{c0,d0}} on q0 and |0> on every other qubit.
   The cq state maps each bit assignment to an unnormalized density matrix.
   teleportation_wrong.qlin (cz q0 q2 replaced by cx q0 q2) must fail.
   Run from the repo root after cargo build --release:
     wolfram -script notes/wolfram/defer_instances.wl *)
qlin="target/release/qlin";
gm=<|"h"->{{1,1},{1,-1}}/Sqrt[2],"x"->{{0,1},{1,0}},"z"->{{1,0},{0,-1}},"y"->{{0,-I},{I,0}},
 "s"->{{1,0},{0,I}},"cx"->{{1,0,0,0},{0,1,0,0},{0,0,0,1},{0,0,1,0}},"cz"->DiagonalMatrix[{1,1,1,-1}]|>;
(* q0 is the most significant bit of the basis index *)
full[u_,qs_,n_]:=Module[{d=2^n},SparseArray[Flatten@Table[
  With[{bi=IntegerDigits[i-1,2,n],bj=IntegerDigits[j-1,2,n]},
   If[Delete[bi,List/@(qs+1)]==Delete[bj,List/@(qs+1)],
     {i,j}->u[[FromDigits[bi[[qs+1]],2]+1,FromDigits[bj[[qs+1]],2]+1]],Nothing]],{i,d},{j,d}],{d,d}]];
proj[q_,v_,n_]:=full[If[v==0,{{1,0},{0,0}},{{0,0},{0,1}}],{q},n];
evalC[c_,a_]:=Switch[First@Keys[c],"Bit",a[[c["Bit"]+1]]==1,"Not",!evalC[c["Not"],a],
  "And",evalC[c["And"][[1]],a]&&evalC[c["And"][[2]],a],"Or",evalC[c["Or"][[1]],a]||evalC[c["Or"][[2]],a],
  "Xor",Xor[evalC[c["Xor"][[1]],a],evalC[c["Xor"][[2]],a]],"Const",c["Const"]];
addTo[acc_,k_,m_]:=If[KeyExistsQ[acc,k],acc[k]+m,m];
runOp[st_,op_,n_]:=Module[{k=First@Keys[op],a=First@Values[op],out=<||>},Switch[k,
 "Gate",With[{u=full[gm[a["gate"]],a["qubits"],n]},Map[u.#.ConjugateTranspose[u]&,st]],
 "Measure",KeyValueMap[Function[{bits,r},Do[With[{p=proj[a["q"],v,n],nb=ReplacePart[bits,a["b"]+1->v]},
    out[nb]=addTo[out,nb,p.r.p]],{v,0,1}]],st];out,
 "If",Module[{t=Select[KeyValueMap[List,st],evalC[a["cond"],#[[1]]]&],e},
   e=Complement[KeyValueMap[List,st],t];
   Merge[{runBlock[Association[Rule@@@t],a["then_"],n],runBlock[Association[Rule@@@e],a["else_"],n]},Total]]]];
runBlock[st_,ops_,n_]:=Fold[runOp[#1,#2,n]&,st,ops];
run[file_]:=Module[{p=ImportString[RunProcess[{qlin,"json",file},"StandardOutput"],"RawJSON"],n,rho0},
  n=p["n_qubits"];rho0=KroneckerProduct[{{a0,b0},{c0,d0}},Sequence@@Table[{{1,0},{0,0}},n-1]];
  runBlock[<|ConstantArray[0,p["n_bits"]]->rho0|>,p["body"],n]];
same[f1_,f2_]:=Module[{r1=run[f1],r2=run[f2]},
  AllTrue[Union[Keys[r1],Keys[r2]],AllTrue[Flatten@Normal[Lookup[r1,Key[#],0]-Lookup[r2,Key[#],0]],PossibleZeroQ[Simplify[#]]&]&]];
Print[<|"teleport"->same["benchmarks/hand/teleportation.qlin","notes/wolfram/teleportation_defer.qlin"],
 "teleport_planted_wrong"->same["benchmarks/hand/teleportation.qlin","notes/wolfram/teleportation_wrong.qlin"],
 "long_range_cnot3"->same["benchmarks/dynamarq/long_range_cnot3.qlin","notes/wolfram/long_range_cnot3_defer.qlin"]|>];
(* |M_t| = sum_{k<=t} C(m,k), by enumeration, m <= 12. *)
Print["M_t formula: ",AllTrue[Flatten@Table[Count[Tuples[{0,1},m],v_/;Total[v]<=t]==Sum[Binomial[m,k],{k,0,t}],{m,1,12},{t,0,m}],TrueQ]];
