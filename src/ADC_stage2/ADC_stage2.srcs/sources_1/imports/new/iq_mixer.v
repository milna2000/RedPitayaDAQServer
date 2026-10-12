// iq_mixer.v
//
// IQ mixer for the stage 2 lock-in / IQ demodulator.
//
// Placement: AFTER the existing CIC -> FIR receive chain (control path),
// so it runs at the decimated sample rate, not at 125 MHz.
//   - adc_sample is the 16-bit FIR output (the filtered, decimated ADC data)
//   - ce is the FIR's m_axis_data_tvalid (one pulse per decimated sample)
//   - ref_cos / ref_sin must advance once per ce pulse (reference DDS
//     stepped at the decimated rate)
//
// Computes:
//   I_mix = adc_sample * ref_cos
//   Q_mix = adc_sample * ref_sin
//
// Each product contains a DC term (proportional to Gr/Gi, i.e. amplitude
// and phase of the input tone relative to the reference) plus a term at
// 2x the reference frequency, which the downstream CIC decimator removes.
//
// ref_cos / ref_sin are assumed to come from a DDS Compiler (or CORDIC)
// in signed fractional format, i.e. full scale represents +/-1.0
// (Q1.(REF_WIDTH-1), two's complement). Confirm this against your actual
// DDS Compiler output format once configured -- if it differs, adjust
// FRAC_BITS below to match.
//
// One pipeline register is included after the multiply to help the
// synthesis tool map cleanly onto DSP48 slices.

module iq_mixer #(
    parameter ADC_WIDTH  = 16,  // input sample width (16 = FIR output; 14 = raw Red Pitaya ADC)
    parameter REF_WIDTH  = 16,  // reference sin/cos width from DDS Compiler
    parameter FRAC_BITS  = REF_WIDTH - 1, // fractional bits in ref_cos/ref_sin (Q1.15 default)
    parameter OUT_WIDTH  = ADC_WIDTH + 1  // output width after rescaling (1 guard bit)
)(
    input  wire                          clk,
    input  wire                          rst_n,     // synchronous, active-low
    input  wire                          ce,        // clock enable / sample valid

    input  wire signed [ADC_WIDTH-1:0]   adc_sample,
    input  wire signed [REF_WIDTH-1:0]   ref_cos,
    input  wire signed [REF_WIDTH-1:0]   ref_sin,

    output reg  signed [OUT_WIDTH-1:0]   i_mix,
    output reg  signed [OUT_WIDTH-1:0]   q_mix,
    output reg                           mix_valid
);

    // Full-precision products before rescaling.
    wire signed [ADC_WIDTH+REF_WIDTH-1:0] i_full;
    wire signed [ADC_WIDTH+REF_WIDTH-1:0] q_full;

    assign i_full = adc_sample * ref_cos;
    assign q_full = adc_sample * ref_sin;

    // Round-to-nearest when rescaling back down by FRAC_BITS, so the
    // output stays in the same units as adc_sample (i.e. binary point
    // realigned after multiplying by a Q1.(FRAC_BITS) reference).
    wire signed [ADC_WIDTH+REF_WIDTH-1:0] i_rounded;
    wire signed [ADC_WIDTH+REF_WIDTH-1:0] q_rounded;

    assign i_rounded = i_full + (1 <<< (FRAC_BITS - 1));
    assign q_rounded = q_full + (1 <<< (FRAC_BITS - 1));

    always @(posedge clk) begin
        if (!rst_n) begin
            i_mix     <= {OUT_WIDTH{1'b0}};
            q_mix     <= {OUT_WIDTH{1'b0}};
            mix_valid <= 1'b0;
        end else if (ce) begin
            i_mix     <= i_rounded[FRAC_BITS +: OUT_WIDTH];
            q_mix     <= q_rounded[FRAC_BITS +: OUT_WIDTH];
            mix_valid <= 1'b1;
        end else begin
            mix_valid <= 1'b0;
        end
    end

endmodule