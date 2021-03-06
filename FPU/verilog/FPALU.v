// Implementation of the FPALU (FP29iADD, FP16iMUL)
// For the W4823 FIR Project
// Anhang Li - Nov. 19 2021

// TODO: 
// 1. Add Latches to minimize useless flipping

//            FORMAT  SIGN  EXP  MANTISSA  WIDTH
//  RAW IEEE  FP16    1     5    10        16
//  INPUT     FP16i   1     5    11        17
//  POST MUL  FP29i   1     6    22        29
//  POST ACC  FP29i   1     6    22        29
//  OUTPUT    FP16    1     5    10        16 

module FPALU (
	input           rst_n,
	input           clk,
	
	input           din_uni_a_sgn,
	input [5:0]     din_uni_a_exp,
	input [21:0]    din_uni_a_man_dn,   // Always Left-Aligned, Denorm

	input           din_uni_b_sgn,
	input [5:0]     din_uni_b_exp,
	input [21:0]    din_uni_b_man_dn,   // Always Left-Aligned, Denorm

	input           add_muln,           // 1: Adder Mode, 0: Multiplier Mode
	output          dout_uni_y_sgn,
	output [5:0]    dout_uni_y_exp, 
	output [21:0]   dout_uni_y_man_dn

);
// ----- CONSTANTS -----
localparam ML_MANSIZE = 11;
localparam ML_EXPSIZE = 3;
localparam ML_FPSIZE  = 1 + ML_EXPSIZE + ML_MANSIZE;
localparam AL_MANSIZE = 2 * ML_MANSIZE;
localparam AL_EXPSIZE = 1 + ML_EXPSIZE;
localparam AL_FPSIZE  = 1 + AL_EXPSIZE + AL_MANSIZE;

localparam OPSIZE = 2;

localparam OPC_ADD29i  = 2'b11;	// Adding   Mode
localparam OPC_MUL16i  = 2'b10;	// Multiply Mode
localparam OPC_ADDSKIP = 2'b01;	// We found a zero, skip the addition entirely
localparam OPC_SLEEP   = 2'b00; // Low Power Mode


// ----- PIPELINE STAGE 1 -----
//
wire [OPSIZE-1:0] s1_opcode = add_muln;

// ACHTUNG:
// You MUST deal with zeros somewhere, maybe here.
// e.g. adding 0e10 to 123e0 will result in 0e10, which is clearly incorrect
// when one of the input is all zeros, you must give up the current exponent compare


// ADDER: Exponent Compare
wire [AL_EXPSIZE:0]   s1_ea_sub_eb = {1'b0,din_uni_a_exp} - {1'b0,din_uni_b_exp};
wire                  s1_ea_lt_eb  = s1_ea_sub_eb[AL_EXPSIZE];
wire                  s1_ea_gte_eb  = s1_ea_lt_eb;
wire [AL_EXPSIZE-1:0] s1_ea_sub_eb_abs = s1_ea_gt_eb ? \
		s1_ea_sub_eb[AL_EXPSIZE-1:0] : {~s1_ea_sub_eb+1'b1}[AL_EXPSIZE-1:0];
// ADDER: Sign Compare
wire       s1_addsubn = ~(din_uni_a_sgn ^ din_uni_b_sgn);	// 1: ADD, 0: SUB
// ADDER: Shifter XCHG
// Exchange while waiting for ABS(EA-EB) completion
wire [AL_MANSIZE-1:0]	s1_mmux_lhs;
wire [AL_MANSIZE-1:0]	s1_mmux_rhs;
xchg #(.DWIDTH(22)) s1_u_manxchg(
	.ia(din_uni_a_man_dn),
	.ib(din_uni_b_man_dn),
	.xchg(s1_ea_lt_eb),		// B has larger EXP, Right shift A.MAN to align with B.MAN 
	.oa(s1_mmux_lhs),
	.ob(s1_mmux_rhs)
);

// MULTIPLIER: Partial Product Generation 
// The original plan was to use Booth Radix-4 Wallace Tree.
// It might be an overkill: producing overcomplicated logic, which may increase power
// Simplify it to wallace tree only, the summation can start in the first cycle.




// ----- PIPELINE STAGE 2 -----
//
// Pipeline Signal Relay
reg [OPSIZE-1:0]     s2_opcode_r;
always @(posedge clk) begin
	s2_opcode_r <= s1_opcode;
end

// ADDER: Signal Relay
reg [AL_EXPSIZE-1:0] s2_ea_sub_eb_abs_r;
reg                  s2_ea_gte_eb_r;
reg [AL_MANSIZE-1:0] s2_mmux_lhs_r;
reg [AL_MANSIZE-1:0] s2_mmux_rhs_r;
reg                  s2_addsubn_r;
always @(posedge clk) begin
	s2_ea_sub_eb_abs_r <= s1_ea_sub_eb_abs;
	s2_ea_gte_eb_r     <= s1_ea_gte_eb;
	s2_mmux_lhs_r      <= s1_mmux_lhs_r;
	s2_mmux_rhs_r      <= s2_mmux_rhs_r;
	s2_addsubn_r       <= s1_addsubn;
end

// ADDER: LHS Zero Detector
// This is added to deal with adding with denormalized zero
// when the zero has a larger exponent
wire              s2_lhs_is_zero = |s2_mmux_lhs_r;
wire [OPSIZE-1:0] s2_opcode_mod;
assign s2_opcode_mod = ((s2_opcode_r==OPC_ADD29i)&&s2_lhs_is_zero) ? \
	OPC_ADDSKIP : s2_opcode_r;

// ADDER: Shifter
// When shifting by [MSB], the output becomes zero
wire [31:0]	s2_bsr_out;
wire [AL_MANSIZE-1:0] s2_bsr_out_gated = s2_ea_sub_eb_abs_r[AL_EXPSIZE-1] ? \
		{AL_MANSIZE{1'b0}} : s2_bsr_out[31:32-AL_MANSIZE];
bsr #(.SWIDTH(AL_EXPSIZE-1)) s2_u_bsr(
	.din(s2_mmux_rhs_r),
	.s(s2_ea_sub_eb_abs_r[AL_EXPSIZE-2:0]),
	.filler(1'b0),
	.dout(s2_bsr_out)
);

// ADDER: Exchanger & Inverter
//
wire [AL_MANSIZE-1:0] s2_mmux2_lhs;
wire [AL_MANSIZE-1:0] s2_mmux2_rhs;
xchg #(.DWIDTH(AL_MANSIZE)) s2_u_manxchg(
	.ia(s2_mmux_lhs_r),
	.ib(s2_bsr_out_gated),
	.xchg(~s2_ea_gte_eb_r),
	.oa(s2_mmux2_lhs),
	.ob(s2_mmux2_rhs)
);

wire [AL_MANSIZE:0]   s2_mmux3_rhs_addsub = s2_addsubn_r ? \
	s2_mmux2_rhs : ~s2_mmux2_rhs;

// ADDER: Denorm Zero: Bypass Path
wire [AL_MANSIZE:0]   s2_mmux3_lhs_addsub;
assign s2_mmux3_lhs_addsub = (s2_lhs_is_zero) ? \
	{1'b0,s2_mmux_rhs_r} : {1'b0, s2_mmux2_lhs};

// MULTIPLIER, Part I: Partial Product Generation
reg [ML_EXPSIZE-1:0]	  s2_ea_r;
reg [ML_EXPSIZE-1:0]	  s2_eb_r;
reg [ML_MANSIZE-1:0]	  s2_ma_r;	   // Multiplicant
reg [(BR4SYM_SIZE*6)-1:0] s2_br4enc_r; // Multiplier Encoded in Radix-4 Booth Symbols
always @(posegde clk)     s2_br4enc_r <= s1_br4enc;

// Partial Product Generation:


// ----- PIPELINE STAGE 3 -----
//
// SEGMENT 1. Pipeline Signal Relay
reg [OPSIZE-1:0]     s3_opcode_r;
always @(posedge clk) begin
	s3_opcode_r <= s2_opcode_r;
end

// ADDER: Summing (CLA)
reg [AL_MANSIZE:0]  s3_lhs_r;
reg [AL_MANSIZE:0]  s3_rhs_r;
reg                 s3_addsubn_r;
always @(posedge clk) begin
	s3_lhs_r     <= s2_mmux2_lhs_addsub;
	s3_rhs_r     <= s2_mmux3_rhs_addsub;
	s3_addsubn_r <= s2_addsubn_r;
end

wire [AL_MANSIZE:0] s3_alu_out;

cla_adder #(.DATA_WID(22)) s3_s4_u_cla(
	.in1(s3_lhs_r),
	.in2(s3_rhs_r),
	.carry_in(~s3_addsubn_r),
	.sum(s3_alu_out),
	.carry_out()
);
// assign s3_alu_out = s3_lhs_r + s3_rhs_r + ~s3_addsubn_r;

// ADDER: Denorm Zero: Bypass Path
wire [AL_MANSIZE:0] s3_mmux_postalu;
assign s3_mmux_postalu = (s3_opcode_r==OPC_ADDSKIP) ? s3_lhs_r : s3_alu_out;

// ----- PIPELINE STAGE 4 -----
// 
// General Note for S4 and S5:
//  In a regular FP Pipeline, all operations need to perform zero detect
//  and shifting. (i.e. Normalization)
//  But our application, FIR, is special:
//  Normalization in constant multiplication is useless, 
//  The result will be re-normalized anyway during the accumulation
//  so we can actually save two cycles on multiplication
//  

// UNIFIED OUTPUT STAGE: Zero Detect and EXP Bias Calculation
// Pipeline Signal Relay
reg [OPSIZE-1:0]     s4_opcode_r;
always @(posedge clk) begin
	s4_opcode_r <= s3_opcode_r;
end

reg [AL_MANSIZE:0] s4_alu_out_r;
reg [4:0]          s4_lzd;
always @(posedge clk) begin
	s4_alu_out_r <= s3_mmux_postalu;
end
// ADDER: Leading Zero Detect:
count_lead_zero #(.W_IN(32)) s4_u_lzd(
	.in({s4_alu_out_r,{(32-AL_MANSIZE-1){1'b0}}}),
	.out(s4_lzd)
);

// I guess the last two stage can also be by passed for denorm zero
// May not be necessary, we'll see when it comes to the multiplier impl.

// We don't deal with zeros here:
//  Because the mantissa within the ALU is always DENORMALIZED,
//  Adding zeros is just adding zeros to the mantissa.
// With additional processing you may be able to get lower power
//  (By skipping zero in the entire addition pipeline)
//  but the chance of having zero is not high anyway. 
// READ the note at stage 1 for more info

// ----- PIPELINE STAGE 5 -----
// UNIFIED OUTPUT STAGE: Final Shifting, Truncation, etc
// Pipeline Signal Relay
reg [OPSIZE-1:0]     s5_opcode_r;
always @(posedge clk) begin
	s5_opcode_r <= s4_opcode_r;
end

// ADDER: Final Shifter
reg [AL_MANSIZE:0] s5_alu_out_r;
reg [4:0]          s5_lzd_r;
always @(posedge clk) begin
	s5_alu_out_r <= s4_alu_out_r;
	s5_lzd_r     <= s4_lzd;
end
bsl #(.SWIDTH(5)) s5_u_bsl (
	.din(s5_alu_out_r),
	.s(s5_lzd_r),
	.filler(1'b0),
	.dout(dout_uni_y_man_dn)
);

// UNIFIED: Exponent Adjust


endmodule /* FPALU */

