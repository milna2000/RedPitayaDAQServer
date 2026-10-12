// iq_mixer_axis.v
//
// Block-design wrapper around iq_mixer.v. It only unpacks and repacks buses,
// so that every connection in the Vivado block design is a single
// interface-to-interface wire (no Slice or Concat blocks needed).
// All of the arithmetic stays in iq_mixer.v.
//
// Bus layouts (fixed for this design):
//   S_AXIS_DATA  24 bit : FIR Compiler output. Bits [15:0] are the sample,
//                         the same 16 bits the RedPitayaDAQServer design uses.
//   S_AXIS_REF   32 bit : DDS Compiler "Sine and Cosine", 16 bit each.
//                         cosine = [15:0], sine = [31:16].
//   M_AXIS_I/Q   24 bit : 17-bit mixer result, sign-extended to 24 bits,
//                         one sample per FIR output sample.
//
// The reference DDS runs freely at 125 MHz. Its value is simply captured
// each time the FIR delivers a sample (s_axis_data_tvalid).

module iq_mixer_axis (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS_DATA:S_AXIS_REF:M_AXIS_I:M_AXIS_Q, ASSOCIATED_RESET aresetn" *)
    input  wire        aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TDATA" *)
    input  wire [23:0] s_axis_data_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TVALID" *)
    input  wire        s_axis_data_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_REF TDATA" *)
    input  wire [31:0] s_axis_ref_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_REF TVALID" *)
    input  wire        s_axis_ref_tvalid,   // not used; the DDS is always valid after start-up

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_I TDATA" *)
    output wire [23:0] m_axis_i_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_I TVALID" *)
    output wire        m_axis_i_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_Q TDATA" *)
    output wire [23:0] m_axis_q_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_Q TVALID" *)
    output wire        m_axis_q_tvalid
);

    wire signed [16:0] i_mix;
    wire signed [16:0] q_mix;
    wire               mix_valid;

    iq_mixer #(
        .ADC_WIDTH (16),
        .REF_WIDTH (16)
    ) mixer (
        .clk        (aclk),
        .rst_n      (aresetn),
        .ce         (s_axis_data_tvalid),
        .adc_sample (s_axis_data_tdata[15:0]),
        .ref_cos    (s_axis_ref_tdata[15:0]),
        .ref_sin    (s_axis_ref_tdata[31:16]),
        .i_mix      (i_mix),
        .q_mix      (q_mix),
        .mix_valid  (mix_valid)
    );

    // Sign-extend 17 -> 24 bits
    assign m_axis_i_tdata  = {{7{i_mix[16]}}, i_mix};
    assign m_axis_q_tdata  = {{7{q_mix[16]}}, q_mix};
    assign m_axis_i_tvalid = mix_valid;
    assign m_axis_q_tvalid = mix_valid;

endmodule