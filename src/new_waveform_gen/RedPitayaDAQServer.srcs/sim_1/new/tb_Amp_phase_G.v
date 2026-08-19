`timescale 1ns / 1ps

module tb_Amp_phase_G;

    localparam integer ADDR_WIDTH = 14;
    localparam integer LATENCY    = 3;   // 3 pipeline stages, in_valid to out_valid
    localparam real    PI         = 3.14159265358979323846;

    reg         clk;
    reg         aresetn;
    reg         in_valid;
    reg  [15:0] phase;
    reg  [15:0] amplitude;
    wire        out_valid;
    wire [31:0] G;

    Amp_phase_G #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk       (clk),
        .aresetn   (aresetn),
        .in_valid  (in_valid),
        .phase     (phase),
        .amplitude (amplitude),
        .out_valid (out_valid),
        .G         (G)
    );

    // 100 MHz clock -- arbitrary, this module has no fixed clock requirement
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // convert a phase in degrees to the 16-bit code the DUT expects
    function [15:0] deg_to_phase16;
        input real deg;
        real turns;
        begin
            turns = deg / 360.0;
            deg_to_phase16 = $rtoi(turns * 65536.0) & 16'hFFFF;
        end
    endfunction

    // convert an amplitude fraction [0,1] to Q0.16
    function [15:0] amp_to_q016;
        input real a;
        begin
            amp_to_q016 = $rtoi(a * 65536.0) & 16'hFFFF;
        end
    endfunction

    // drive one test point and check the result LATENCY cycles later
    integer error_count;
    integer test_count;

    task run_case;
        input real phase_deg;
        input real amp_frac;
        real   phase_rad;
        real   expected_gr_real, expected_gi_real;
        integer expected_gr, expected_gi;
        reg signed [15:0] measured_gr, measured_gi;
        integer err_gr, err_gi;
        // allow 2 LSB slack: ROM quantization (ADDR_WIDTH=14) + phase16
        // quantization + round-to-nearest rounding, all small by design
        localparam integer TOLERANCE_LSB = 2;
        begin
            phase     = deg_to_phase16(phase_deg);
            amplitude = amp_to_q016(amp_frac);
            in_valid  = 1'b1;
            @(posedge clk);
            in_valid  = 1'b0;

            repeat (LATENCY - 1) @(posedge clk);

            if (out_valid !== 1'b1) begin
                $display("[TB] ERROR: out_valid not high at expected latency, phase=%.1f amp=%.3f",
                          phase_deg, amp_frac);
                error_count = error_count + 1;
            end

            measured_gr = G[15:0];
            measured_gi = G[31:16];

            phase_rad        = phase_deg * PI / 180.0;
            expected_gr_real = amp_frac * $cos(phase_rad);
            expected_gi_real = amp_frac * $sin(phase_rad);
            expected_gr      = $rtoi(expected_gr_real * 32768.0);
            expected_gi      = $rtoi(expected_gi_real * 32768.0);

            err_gr = measured_gr - expected_gr;
            err_gi = measured_gi - expected_gi;
            if (err_gr < 0) err_gr = -err_gr;
            if (err_gi < 0) err_gi = -err_gi;

            test_count = test_count + 1;

            if (err_gr > TOLERANCE_LSB || err_gi > TOLERANCE_LSB) begin
                error_count = error_count + 1;
                $display("[TB] MISMATCH phase=%6.1f deg amp=%.3f : Gr exp=%0d got=%0d (err=%0d), Gi exp=%0d got=%0d (err=%0d)",
                          phase_deg, amp_frac, expected_gr, measured_gr, err_gr,
                          expected_gi, measured_gi, err_gi);
            end else begin
                $display("[TB]    OK  phase=%6.1f deg amp=%.3f : Gr exp=%0d got=%0d, Gi exp=%0d got=%0d",
                          phase_deg, amp_frac, expected_gr, measured_gr, expected_gi, measured_gi);
            end
        end
    endtask

    initial begin
        error_count = 0;
        test_count  = 0;

        aresetn  = 1'b0;
        in_valid = 1'b0;
        phase    = 16'd0;
        amplitude= 16'd0;
        repeat (5) @(posedge clk);
        aresetn = 1'b1;
        repeat (5) @(posedge clk);

        // phase sweep at full amplitude -- covers all four quadrants and
        // both mirror cases within each quadrant (lookup_sin's 4-way case)
        run_case(0.0,   1.0);
        run_case(30.0,  1.0);
        run_case(45.0,  1.0);
        run_case(60.0,  1.0);
        run_case(90.0,  1.0);
        run_case(120.0, 1.0);
        run_case(135.0, 1.0);
        run_case(150.0, 1.0);
        run_case(180.0, 1.0);
        run_case(210.0, 1.0);
        run_case(225.0, 1.0);
        run_case(240.0, 1.0);
        run_case(270.0, 1.0);
        run_case(300.0, 1.0);
        run_case(315.0, 1.0);
        run_case(330.0, 1.0);

        // amplitude sweep at a fixed phase -- checks the multiply/rescale
        run_case(45.0, 0.0);
        run_case(45.0, 0.25);
        run_case(45.0, 0.5);
        run_case(45.0, 0.75);
        run_case(45.0, 1.0);

        // back-to-back changes with no gap -- checks the pipeline doesn't
        // need a settle gap between in_valid pulses
        run_case(0.0,  1.0);
        run_case(90.0, 1.0);
        run_case(180.0, 1.0);

        $display("--------------------------------------------------------");
        $display("[TB] Tests run   : %0d", test_count);
        $display("[TB] Mismatches  : %0d", error_count);
        if (error_count == 0)
            $display("[TB] RESULT: PASS");
        else
            $display("[TB] RESULT: FAIL");
        $display("--------------------------------------------------------");

        $finish;
    end

endmodule