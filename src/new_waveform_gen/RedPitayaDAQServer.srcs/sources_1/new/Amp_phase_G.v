module Amp_phase_G #(
    parameter CORDIC_LATENCY = 20   // <<< REPLACE with the exact latency
                                     //     reported in your CORDIC IP's
                                     //     customization GUI (Step 1)
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
      .aclk(clk),                                // input wire aclk
      .s_axis_phase_tvalid(1'b1),  // input wire s_axis_phase_tvalid
      .s_axis_phase_tdata(phase),    // input wire [15 : 0] s_axis_phase_tdata
      .m_axis_dout_tvalid(cordic_valid),    // output wire m_axis_dout_tvalid
      .m_axis_dout_tdata(cordic_data)      // output wire [31 : 0] m_axis_dout_tdata
   );

    // Extract cosine/sine -- VERIFY this packing against your actual
    // CORDIC instantiation template / PG105, this is currently assumed.
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
    // Multiply CORDIC's unit-magnitude cos/sin by the aligned amplitude,
    // round to nearest, register into G.
    //-------------------------------------------------------------------
    wire signed [31:0] gr_mult = cordic_cos * $signed({1'b0, amp_aligned});
    wire signed [31:0] gi_mult = cordic_sin * $signed({1'b0, amp_aligned});

    wire signed [31:0] gr_rounded = gr_mult + 32'sd32768;
    wire signed [31:0] gi_rounded = gi_mult + 32'sd32768;

    always @(posedge clk) begin
        if (!aresetn) begin
            G <= 32'd0;
        end else if (cordic_valid) begin
            G <= {gr_rounded[31 -: 16], gi_rounded[31 -: 16]};
        end
        // else: hold last value if cordic_valid deasserts for a cycle
    end

endmodule