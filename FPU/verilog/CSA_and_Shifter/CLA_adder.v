module CLA16(A, B, Ci, S, Co, PG1, GG1);

input [15:0] A;
input [15:0] B;
input Ci;
output [15:0] S;
output Co;
output PG1;
output GG1;

wire [3:0] GG;
wire [3:0] PG;
wire [3:1] C;
wire Ci;

  CLALogic CarryLogic_2 (GG[3:0], PG[3:0], Ci, C[3:1], Co, PG1, GG1);

// 4bit    A     B       Ci     S   PG        GG    Co
CLA4 u0 (A[3:0], B[3:0], Ci, S[3:0],PG[0], GG[0]);
CLA4 u1 (A[7:4], B[7:4], C[1],  S[7:4], PG[1], GG[1]);
CLA4 u2 (A[11:8], B[11:8], C[2], S[11:8], PG[2], GG[2]);
CLA4 u3 (A[15:12], B[15:12], C[3], S[15:12], PG[3], GG[3]);

endmodule

module CLA4(A, B, Ci, S, PG, GG);
   input [3:0] A;
   input [3:0] B;
   input Ci;
   output [3:0] S;
   //output Co;
   output PG;
   output GG;
   wire Ci;
   wire [3:0] G;
   wire [3:0] P;
   wire [3:1] C;

   CLALogic CarryLogic (G, P, Ci, C, Co, PG, GG);
   GPFullAdder FA0 (A[0], B[0], Ci, G[0], P[0], S[0]);
   GPFullAdder FA1 (A[1], B[1], C[1], G[1], P[1], S[1]);
   GPFullAdder FA2 (A[2], B[2], C[2], G[2], P[2], S[2]);
   GPFullAdder FA3 (A[3], B[3], C[3], G[3], P[3], S[3]);

endmodule

module CLALogic (G, P, Ci, C, Co, PG, GG);
   input [3:0] G;
   input [3:0] P;
   input Ci;
   output [3:1] C;
   output Co;
   output PG;
   output GG;

   wire GG_int;
   wire PG_int;

   assign C[1] = G[0] | (P[0] & Ci);
   assign C[2] = G[1] | (P[1] & G[0])| (P[1] & P[0] & Ci);
   assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0])| (P[2] & P[1] & P[0] & Ci);


   assign PG_int = P[3] & P[2] & P[1] & P[0];
   assign GG_int = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]);
   assign Co = GG_int | (PG_int & Ci);
   assign PG = PG_int;
   assign GG = GG_int;

   endmodule

   module GPFullAdder(X, Y, Cin, G, P, Sum);
      input X;
      input Y;
      input Cin;
      output G;
      output P;
      output Sum;

      wire P_int;

      assign G = X & Y;
      assign P = P_int;
      assign P_int = X ^ Y;
      assign Sum = P_int ^ Cin;
  endmodule