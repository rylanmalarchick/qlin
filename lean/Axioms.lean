import Qlin

/-! The G5 theorems. `scripts/lean_axioms.sh` checks that each depends
only on propext, Classical.choice, and Quot.sound. -/



-- R1
#print axioms Qlin.den_add
#print axioms Qlin.den_zero
#print axioms Qlin.den_restrict
#print axioms Qlin.den_comm
#print axioms Qlin.supp_den
-- R2
#print axioms Qlin.fold_true
#print axioms Qlin.fold_false
#print axioms Qlin.hoist_sound
#print axioms Qlin.merge_sound
#print axioms Qlin.unroll_sound
#print axioms Qlin.ite_congr
#print axioms Qlin.denB_congr
-- R3
#print axioms Qlin.fastpath_step
#print axioms Qlin.sink_past_disjoint
#print axioms Qlin.sink_past_clifford
#print axioms Qlin.Pauli.conj_h
#print axioms Qlin.Pauli.conj_s
#print axioms Qlin.Pauli.conj_sdg
#print axioms Qlin.Pauli.conj_sx
#print axioms Qlin.Pauli.conj_pauli
#print axioms Qlin.Pauli.conj_cx
#print axioms Qlin.Pauli.conj_cz
#print axioms Qlin.Pauli.conj_cy
#print axioms Qlin.Pauli.conj_swap
-- R4
#print axioms Qlin.run_mono
#print axioms Qlin.hoist_latency
#print axioms Qlin.merge_latency
#print axioms Qlin.makespan_le
-- CQ model (A1 and A2 for density matrices)
#print axioms Qlin.CQ.lift_comm
#print axioms Qlin.CQ.chan_comm
#print axioms Qlin.CQ.Spec.sem_restrict
#print axioms Qlin.CQ.Spec.sem_comm
#print axioms Qlin.CQ.interp
#print axioms Qlin.CQ.interp_leaf
#print axioms Qlin.CQ.Chart.lift_emb_mul
#print axioms Qlin.CQ.chan_sign
#print axioms Qlin.CQ.Chart.chan_conj
#print axioms Qlin.CQ.chan_kron
#print axioms Qlin.CQ.sink1_cq
#print axioms Qlin.CQ.sink2_cq
#print axioms Qlin.CQ.sink_h_cq
#print axioms Qlin.CQ.sink_cx_cq
#print axioms Qlin.CQ.meas_complete
#print axioms Qlin.CQ.reset_complete
#print axioms Qlin.CQ.hoist_sound_cq
#print axioms Qlin.CQ.merge_sound_cq
#print axioms Qlin.CQ.fastpath_step_cq
#print axioms Qlin.CQ.ctrl_local
#print axioms Qlin.CQ.proj_ctrl
#print axioms Qlin.CQ.chan_proj_ctrl
#print axioms Qlin.CQ.defer_cq
-- Negative tests
#print axioms Qlin.interp_nontrivial
#print axioms Qlin.hoist_needs_hc
#print axioms Qlin.hoist_needs_disj
#print axioms Qlin.merge_needs_disj
#print axioms Qlin.fastpath_needs_hw
#print axioms Qlin.hoist_latency_needs_henc
#print axioms Qlin.merge_latency_needs_henc
#print axioms Qlin.TV.checkBlock_sound
