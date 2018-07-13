// ---------------------------------------

module LUT4(input A, B, C, D, output Z);
	parameter [15:0] INIT = 16'h0000;
	assign Z = INIT[{D, C, B, A}];
endmodule

// ---------------------------------------

module L6MUX21 (input D0, D1, SD, output Z);
	assign Z = SD ? D1 : D0;
endmodule

// ---------------------------------------

module CCU2C(input CIN, A0, B0, C0, D0, A1, B1, C1, D1,
	           output S0, S1, COUT);

	parameter [15:0] INIT0 = 16'h0000;
	parameter [15:0] INIT1 = 16'h0000;
	parameter INJECT1_0 = "YES";
	parameter INJECT1_1 = "YES";

	// First half
	wire LUT4_0 = INIT0[{D0, C0, B0, A0}];
	wire LUT2_0 = INIT0[{2'b00, B0, A0}];

	wire gated_cin_0 = (INJECT1_0 == "YES") ? 1'b0 : CIN;
	assign S0 = LUT4_0 ^ gated_cin_0;

	wire gated_lut2_0 = (INJECT1_0 == "YES") ? 1'b0 : LUT2_0;
	wire cout_0 = (~LUT4_0 & gated_lut2_0) | (LUT4_0 & CIN);

	// Second half
	wire LUT4_1 = INIT1[{D1, C1, B1, A1}];
	wire LUT2_1 = INIT1[{2'b00, B1, A1}];

	wire gated_cin_1 = (INJECT1_1 == "YES") ? 1'b0 : cout_0;
	assign S1 = LUT4_1 ^ gated_cin_1;

	wire gated_lut2_1 = (INJECT1_1 == "YES") ? 1'b0 : LUT2_1;
	assign COUT = (~LUT4_1 & gated_lut2_1) | (LUT4_1 & cout_0);

endmodule

// ---------------------------------------

module TRELLIS_RAM16X2 (
	input DI0, DI1,
	input WAD0, WAD1, WAD2, WAD3,
	input WRE, WCK,
	input RAD0, RAD1, RAD2, RAD3,
	output DO0, DO1
);
  parameter WCKMUX = "WCK";
	parameter WREMUX = "WRE";
	parameter INITVAL_0 = 16'h0000;
	parameter INITVAL_1 = 16'h0000;

	reg [1:0] mem[15:0];

	integer i;
	initial begin
		for (i = 0; i < 16; i = i + 1)
			mem[i] <= {INITVAL_1[i], INITVAL_0[i]};
	end

	wire muxwck = (WCKMUX == "INV") ? ~WCK : WCK;

	wire muxwre = (WREMUX == "1") ? 1'b1 :
							  (WREMUX == "0") ? 1'b0 :
							  (WREMUX == "INV") ? ~WRE :
							  WRE;

	always @(posedge muxwck)
		if (muxwre)
			mem[{WAD3, WAD2, WAD1, WAD0}] <= {DI1, DI0};

	assign {DO1, DO0} = mem[{RAD3, RAD2, RAD1, RAD0}];
endmodule

// ---------------------------------------

module PFUMX (input ALUT, BLUT, C0, output Z);
	assign Z = C0 ? ALUT : BLUT;
endmodule

// ---------------------------------------

module DPR16X4C (
		input [3:0] DI,
		input WCK, WRE,
		input [3:0] RAD,
		input [3:0] WAD,
		output [3:0] DO
);
	// For legacy Lattice compatibility, INITIVAL is a hex
	// string rather than a numeric parameter
	parameter INITVAL = "0x0000000000000000";

	function [63:0] convert_initval;
		input [143:0] hex_initval;
		reg done;
		reg [63:0] temp;
		reg [7:0] char;
		integer i;
		begin
			done = 1'b0;
			temp = 0;
			for (i = 0; i < 16; i = i + 1) begin
				if (!done) begin
					char = hex_initval[8*i +: 8];
					if (char == "x") begin
						done = 1'b1;
					end else begin
						if (char >= "0" && char <= "9")
							temp[4*i +: 4] = char - "0";
						else if (char >= "A" && char <= "F")
							temp[4*i +: 4] = 10 + char - "A";
						else if (char >= "a" && char <= "f")
							temp[4*i +: 4] = 10 + char - "a";
					end
				end
			end
			convert_initval = temp;
		end
	endfunction

	localparam conv_initval = convert_initval(INITVAL);

	reg [3:0] ram[0:15];
	integer i;
	initial begin
		for (i = 0; i < 15; i = i + 1) begin
			ram[i] = conv_initval[4*i +: 4];
		end
	end

	always @(posedge WCK)
		if (WRE)
			ram[WAD] <= DI;

	assign DO = ram[RAD];

endmodule

// ---------------------------------------

module TRELLIS_FF(input CLK, LSR, CE, DI, output reg Q);
	parameter GSR = "ENABLED";
	parameter [127:0] CEMUX = "1";
	parameter CLKMUX = "CLK";
	parameter LSRMUX = "LSR";
	parameter SRMODE = "LSR_OVER_CE";
	parameter REGSET = "RESET";

	wire muxce = (CEMUX == "1") ? 1'b1 :
	             (CEMUX == "0") ? 1'b0 :
							 (CEMUX == "INV") ? ~CE :
							 CE;

	wire muxlsr = (LSRMUX == "INV") ? ~LSR : LSR;
	wire muxclk = (CLKMUX == "INV") ? ~CLK : CLK;

	wire srval = (REGSET == "SET") ? 1'b1 : 1'b0;

	initial Q = 1'b0;

	generate
		if (SRMODE == "ASYNC") begin
			always @(posedge muxclk, posedge muxlsr)
				if (muxlsr)
					Q <= srval;
				else
					Q <= DI;
		end else begin
			always @(posedge muxclk)
				if (muxlsr)
					Q <= srval;
				else
					Q <= DI;
		end
	endgenerate
endmodule

// ---------------------------------------

module OBZ(input I, T, output O);
assign O = T ? 1'bz : I;
endmodule

// ---------------------------------------

module IB(input I, output O);
assign O = I;
endmodule

// ---------------------------------------

module TRELLIS_IO(
	inout B,
	input I,
	input T,
	output O
);
	parameter DIR = "INPUT";

	generate
		if (DIR == "INPUT") begin
			assign B = 1'bz;
			assign O = B;
		end else if (DIR == "OUTPUT") begin
			assign B = T ? 1'bz : I;
			assign O = 1'bx;
		end else if (DIR == "INOUT") begin
			assign B = T ? 1'bz : I;
			assign O = B;
		end else begin
			ERROR_UNKNOWN_IO_MODE error();
		end
	endgenerate

endmodule

// ---------------------------------------

module OB(input I, output O);
assign O = I;
endmodule

// ---------------------------------------

module BB(input I, T, output O, inout B);
assign B = T ? 1'bz : I;
assign O = B;
endmodule

// ---------------------------------------

module INV(input A, output Z);
	assign Z = !A;
endmodule

// ---------------------------------------

module TRELLIS_SLICE(
	input A0, B0, C0, D0,
	input A1, B1, C1, D1,
	input M0, M1,
	input FCI, FXA, FXB,

	input CLK, LSR, CE,
	input DI0, DI1,

	input WD0, WD1,
	input WAD0, WAD1, WAD2, WAD3,
	input WRE, WCK,

	output F0, Q0,
	output F1, Q1,
	output FCO, OFX0, OFX1,

	output WDO0, WDO1, WDO2, WDO3,
	output WADO0, WADO1, WADO2, WADO3
);

	parameter MODE = "LOGIC";
	parameter GSR = "ENABLED";
	parameter SRMODE = "LSR_OVER_CE";
	parameter [127:0] CEMUX = "1";
	parameter CLKMUX = "CLK";
	parameter LSRMUX = "LSR";
	parameter LUT0_INITVAL = 16'h0000;
	parameter LUT1_INITVAL = 16'h0000;
	parameter REG0_SD = "0";
	parameter REG1_SD = "0";
	parameter REG0_REGSET = "RESET";
	parameter REG1_REGSET = "RESET";
	parameter [127:0] CCU2_INJECT1_0 = "NO";
	parameter [127:0] CCU2_INJECT1_1 = "NO";
	parameter WREMUX = "WRE";

	function [15:0] permute_initval;
		input [15:0] initval;
		integer i;
		begin
			for (i = 0; i < 16; i = i + 1) begin
				permute_initval[{i[0], i[2], i[1], i[3]}] = initval[i];
			end
		end
	endfunction

	generate
		if (MODE == "LOGIC") begin
			// LUTs
			LUT4 #(
				.INIT(LUT0_INITVAL)
			) lut4_0 (
				.A(A0), .B(B0), .C(C0), .D(D0),
				.Z(F0)
			);
			LUT4 #(
				.INIT(LUT1_INITVAL)
			) lut4_1 (
				.A(A1), .B(B1), .C(C1), .D(D1),
				.Z(F1)
			);
			// LUT expansion muxes
			PFUMX lut5_mux (.ALUT(F1), .BLUT(F0), .C0(M0), .Z(OFX0));
			L6MUX21 lutx_mux (.D0(FXA), .D1(FXB), .SD(M1), .Z(OFX1));
		end else if (MODE == "CCU2") begin
			CCU2C #(
				.INIT0(LUT0_INITVAL),
				.INIT1(LUT1_INITVAL),
				.INJECT1_0(CCU2_INJECT1_0),
				.INJECT1_1(CCU2_INJECT1_1)
		  ) ccu2c_i (
				.CIN(FCI),
				.A0(A0), .B0(B0), .C0(C0), .D0(D0),
				.A1(A1), .B1(B1), .C1(C1), .D1(D1),
				.S0(F0), .S1(F1),
				.COUT(FCO)
			);
		end else if (MODE == "RAMW") begin
			assign WDO0 = C1;
			assign WDO1 = A1;
			assign WDO2 = D1;
			assign WDO3 = B1;
			assign WADO0 = D0;
			assign WADO1 = B0;
			assign WADO2 = C0;
			assign WADO3 = A0;
		end else if (MODE == "DPRAM") begin
			TRELLIS_RAM16X2 #(
				.INITVAL_0(permute_initval(LUT0_INITVAL)),
				.INITVAL_1(permute_initval(LUT1_INITVAL)),
				.WREMUX(WREMUX)
			) ram_i (
				.DI0(WD0), .DI1(WD1),
				.WAD0(WAD0), .WAD1(WAD1), .WAD2(WAD2), .WAD3(WAD3),
				.WRE(WRE), .WCK(WCK),
				.RAD0(D0), .RAD1(B0), .RAD2(C0), .RAD3(A0),
				.DO0(F0), .DO1(F1)
			);
			// TODO: confirm RAD and INITVAL ordering
			// DPRAM mode contract?
			always @(*) begin
				assert(A0==A1);
				assert(B0==B1);
				assert(C0==C1);
				assert(D0==D1);
			end
		end else begin
			ERROR_UNKNOWN_SLICE_MODE error();
		end
	endgenerate

	// FF input selection muxes
	wire muxdi0 = (REG0_SD == "1") ? DI0 : M0;
	wire muxdi1 = (REG1_SD == "1") ? DI1 : M1;
	// Flipflops
	TRELLIS_FF #(
		.GSR(GSR),
		.CEMUX(CEMUX),
		.CLKMUX(CLKMUX),
		.LSRMUX(LSRMUX),
		.SRMODE(SRMODE),
		.REGSET(REG0_REGSET)
	) ff_0 (
		.CLK(CLK), .LSR(LSR), .CE(CE),
		.DI(muxdi0),
		.Q(Q0)
	);
	TRELLIS_FF #(
		.GSR(GSR),
		.CEMUX(CEMUX),
		.CLKMUX(CLKMUX),
		.LSRMUX(LSRMUX),
		.SRMODE(SRMODE),
		.REGSET(REG1_REGSET)
	) ff_1 (
		.CLK(CLK), .LSR(LSR), .CE(CE),
		.DI(muxdi1),
		.Q(Q1)
	);
endmodule

