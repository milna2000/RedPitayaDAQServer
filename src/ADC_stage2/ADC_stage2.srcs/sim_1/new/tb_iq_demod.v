// tb_iq_demod.v -- simulation-only testbench for the IQ_demo block design.
// Supplies the 125 MHz clock, releases the reset, and prints every
// amplitude/phase result from the CORDIC to the Tcl console.
//
// CORDIC output bus (48 bit):  [23:0] = amplitude,  [47:24] = phase.
// Phase is in "scaled radians": 2^21 counts = 180 degrees.
`timescale 1ns / 1ps

module tb_iq_demod;

    reg aclk_0    = 1'b0;
    reg aresetn_0 = 1'b0;   // active-low: 0 = held in reset

    wire [47:0] dout_tdata;
    wire        dout_tvalid;

    // 125 MHz clock: 8 ns period
    always #4 aclk_0 = ~aclk_0;

    // Hold reset for 25 clock cycles, then release
    initial #200 aresetn_0 = 1'b1;

    IQ_demo_wrapper dut (
        .aclk_0               (aclk_0),
        .aresetn_0            (aresetn_0),
        .M_AXIS_DOUT_0_tdata  (dout_tdata),
        .M_AXIS_DOUT_0_tvalid (dout_tvalid)
    );

    // Split the bus so both values can be dragged into the waveform
    wire signed [23:0] amplitude = dout_tdata[23:0];
    wire signed [23:0] phase_raw = dout_tdata[47:24];
    real               phase_deg;

    integer n = 0;
    always @(posedge aclk_0) begin
        if (dout_tvalid) begin
            phase_deg = phase_raw * 180.0 / 2097152.0;
            n = n + 1;
            $display("result %0d at %0d us: amplitude = %0d, phase = %0.2f deg",
                     n, $time/1000, amplitude, phase_deg);
        end
    end

endmodule