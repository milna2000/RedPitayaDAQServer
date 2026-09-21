## What changed

### New waveform generator hierarchy
- Removed the `waveform_gen_inst` blocks.
- Added a new `new_waveform_gen` module, instantiated 6 times inside `fourier_synth_standard` to produce 6 independent tones (3 per DAC channel).

### Complex gain modulation
- Each tone's amplitude/phase is now applied via complex gain modulation: `Re(R·G) = I·Gr − Q·Gi`.
- Added a new Verilog module, `Amp_phase_G`, which computes the complex gain `G = Gr + jGi` from amplitude and phase inputs using a Xilinx CORDIC Compiler IP (Sin/Cos mode).
- `Amp_phase_G` includes a 20-stage × 16-bit `amp_delay` shift register (auto-infers as SRLs) to align the gain path with the signal path.

### 21/09/2026

- Verilog module, `Amp_phase_G` is modified, because the CORDIC IP calculation are done in Q1.15 instead of Q2.14

