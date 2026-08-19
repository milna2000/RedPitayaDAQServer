module Amp_phase_G #(
    parameter integer ADDR_WIDTH = 14   // address width is 14; remaining 2 MSBs select quadrant
)(
    input  wire        clk,
    input  wire        aresetn,
    input  wire [15:0] phase,           // unsigned, angle = phase * 2*pi / 65536
    input  wire [15:0] amplitude,       // unsigned
    output reg  [31:0] G                // G[15:0]  = Gr (Q1.15, A * cos(phase))
                                        // G[31:16] = Gi (Q1.15, A * sin(phase))
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);
    localparam integer QUARTER_TURN = (1 << ADDR_WIDTH); // 0x4000 for ADDR_WIDTH=14

    (* rom_style = "block" *)
    reg signed [15:0] sine_rom [0:DEPTH-1];
    integer k;

    initial begin
        for (k = 0; k < DEPTH; k = k + 1) begin
            sine_rom[k] = $rtoi(32767.0 * $sin((k * 3.14159265358979323846) / (2.0 * DEPTH)));
        end
    end

    function signed [15:0] lookup_sin;
        input [15:0] ph;
        reg [ADDR_WIDTH-1:0] idx, idx_mirror;
        reg signed [15:0] mag;
        begin
            idx        = ph[ADDR_WIDTH-1:0];
            idx_mirror = ~idx; // (2^ADDR_WIDTH - 1) - idx
            case (ph[15:14])
                2'b00: mag =  sine_rom[idx];
                2'b01: mag =  sine_rom[idx_mirror];
                2'b10: mag = -sine_rom[idx];
                2'b11: mag = -sine_rom[idx_mirror];
                default: mag = 16'sd0;
            endcase
            lookup_sin = mag;
        end
    endfunction

    // -------------------------------------------------------------------
    // Stage 1: Obtain sin and cos via lookup & pipeline amplitude
    // -------------------------------------------------------------------
    reg [15:0] amplitude_s1;
    reg signed [15:0] cos_s1, sin_s1;

    always @(posedge clk) begin
        if (~aresetn) begin
            amplitude_s1 <= 16'd0;
            cos_s1       <= 16'sd0;
            sin_s1       <= 16'sd0;
        end else begin
            amplitude_s1 <= amplitude;
            cos_s1       <= lookup_sin(phase + QUARTER_TURN[15:0]);
            sin_s1       <= lookup_sin(phase);
        end
    end

    // -------------------------------------------------------------------
    // Stage 2: Multiply by amplitude (Forced LUT-based multiplication)
    // -------------------------------------------------------------------
    reg signed [32:0] prod_gr_s2, prod_gi_s2;

    // (* use_dsp = "no" *) forces Vivado to synthesize multipliers in LUT logic
    wire signed [32:0] mult_gr_wire = $signed({1'b0, amplitude_s1}) * cos_s1;
    wire signed [32:0] mult_gi_wire = $signed({1'b0, amplitude_s1}) * sin_s1;

    always @(posedge clk) begin
        if (~aresetn) begin
            prod_gr_s2 <= 33'sd0;
            prod_gi_s2 <= 33'sd0;
        end else begin
            prod_gr_s2 <= mult_gr_wire;
            prod_gi_s2 <= mult_gi_wire;
        end
    end

    // -------------------------------------------------------------------
    // Stage 3: Round and rescale back to Q1.15, drive output G
    // -------------------------------------------------------------------
    wire signed [15:0] gr_rounded = (prod_gr_s2 + 33'sd32768) >>> 16;
    wire signed [15:0] gi_rounded = (prod_gi_s2 + 33'sd32768) >>> 16;

    always @(posedge clk) begin
        if (~aresetn) begin
            G <= 32'd0;
        end else begin
            G <= {gi_rounded, gr_rounded}; // [31:16]=Gi, [15:0]=Gr
        end
    end

endmodule