module Amp_phase_G #(
    parameter CORDIC_LATENCY = 20
)(
    input  wire        clk,
    input  wire        aresetn,
    input  wire [15:0] phase,
    input  wire [15:0] amplitude,
    output reg  [31:0] G
);
    wire        cordic_valid;
    wire [31:0] cordic_data;

    
  cordic_0 cordic_i (
      .aclk(clk),                       
      .s_axis_phase_tvalid(1'b1), 
      .s_axis_phase_tdata(phase), 
      .m_axis_dout_tvalid(cordic_valid),
      .m_axis_dout_tdata(cordic_data)
   );

    // Extract cosine/sine. Confirmed by direct raw_tdata inspection:
    // cordic_data[15:0] = cos, cordic_data[31:16] = sin.
    //
    // IMPORTANT: Data Format = SignedFraction for Sin/Cos CORDIC uses
    // 2 INTEGER bits (Q2.14), not 1 (Q1.15) -- Xilinx reserves headroom
    // for the ~1.647x CORDIC processing gain. Confirmed empirically:
    // raw cos/sin settle to magnitude ~16384 (not ~32767) for unity
    // inputs. The multiply/round stage below accounts for this.
    wire signed [15:0] cordic_cos = cordic_data[15:0];
    wire signed [15:0] cordic_sin = cordic_data[31:16];

    //-------------------------------------------------------------------
    // Delay amplitude by CORDIC_LATENCY cycles so it lines up with the
    // phase value it was originally paired with when the result returns.
    //-------------------------------------------------------------------
    reg [15:0] amp_delay [0:CORDIC_LATENCY-1];
    integer d;

    always @(posedge clk) begin
        if (!aresetn) begin
            for (d = 0; d < CORDIC_LATENCY; d = d + 1)
                amp_delay[d] <= 16'd0;
        end else begin
            amp_delay[0] <= amplitude;
            for (d = 1; d < CORDIC_LATENCY; d = d + 1)
                amp_delay[d] <= amp_delay[d-1];
        end
    end

    wire [15:0] amp_aligned = amp_delay[CORDIC_LATENCY-1];

    //-------------------------------------------------------------------
    // Multiply CORDIC's Q2.14 cos/sin by the aligned amplitude, round to
    // nearest, register into G as Q1.15.
    //
    // cos_raw = true_cos * 2^14, amp_raw = true_amp * 2^16
    // product = true_cos * true_amp * 2^30
    // desired G = true_cos * true_amp * 2^15  =>  shift right by 15
    // (round constant = 2^14, output slice = bits [30:15])
    //-------------------------------------------------------------------
    wire signed [31:0] gr_mult = cordic_cos * $signed({1'b0, amp_aligned});
    wire signed [31:0] gi_mult = cordic_sin * $signed({1'b0, amp_aligned});

    wire signed [31:0] gr_rounded = gr_mult + 32'sd16384;
    wire signed [31:0] gi_rounded = gi_mult + 32'sd16384;

    // Arithmetic shift down to Q1.15, then saturate: cos/sin can land
    // exactly on, or one ULP past, +-full-scale (CORDIC gain-compensation
    // rounding), which after multiplying by near-full-scale amplitude can
    // round up to exactly +32768 or down past -32768 -- one bit outside
    // the signed 16-bit range. Without saturation this silently wraps
    // (+32768 -> -32768, and similarly at the negative boundary).
    wire signed [31:0] gr_shifted = gr_rounded >>> 15;
    wire signed [31:0] gi_shifted = gi_rounded >>> 15;

    wire signed [15:0] Gr_sat =
        (gr_shifted > 32'sd32767)  ? 16'sd32767 :
        (gr_shifted < -32'sd32768) ? -16'sd32768 :
        gr_shifted[15:0];

    wire signed [15:0] Gi_sat =
        (gi_shifted > 32'sd32767)  ? 16'sd32767 :
        (gi_shifted < -32'sd32768) ? -16'sd32768 :
        gi_shifted[15:0];

    always @(posedge clk) begin
        if (!aresetn) begin
            G <= 32'd0;
        end else if (cordic_valid) begin
            G <= {Gr_sat, Gi_sat};
        end
    end

endmodule