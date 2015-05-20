// This file is part of FirFilter.Sv (Trivial SystemVerilog implementation
// of FIR filters)
// 
// Copyright (C) 2015  Leonid Azarenkov < leonid AT rezonics DOT com >
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// 
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


module FirFilter
#(
    parameter INPUT_WIDTH  = 16,
    parameter COEFF_WIDTH  = 8,
    parameter OUTPUT_WIDTH = 26,

    parameter SYMMETRY     = 0, // 0 - Non-symmetric, 1 - Symmetric, 2 - Anti-symmetric
    parameter NUM_TAPS     = 37,
    parameter logic [COEFF_WIDTH - 1: 0] COEFFS [0: NUM_TAPS - 1] = '{8, 6, 0, -7, -11, -8, 0, 10, 16, 12, 0, -16, -26, -22, 0, 38, 80, 114, 127, 114, 80, 38, 0, -22, -26, -16, 0, 12, 16, 10, 0, -8, -11, -7, 0, 6, 8},
    
    parameter PIPELINE_MUL       = 1, // pipeline register for multiplier
    parameter PIPELINE_ADD_RATIO = 1, // pipeline ratio for adders (1 - register for each adder, 2 - register for every other adder, 3 - ...)
    parameter OUTPUT_REG         = 1  // filter output register
)
(
    input   logic                       clk,
    input   logic                       rst,
    
    input   logic                       valid_in,
    output  logic                       valid_out,

    // data in/out
    input   logic [INPUT_WIDTH - 1: 0]  din,
    output  logic [OUTPUT_WIDTH - 1: 0] dout
);

/// calculate number of adders for specified level of adder tree
function automatic int calcNi(int TapsNum, int lvl);
    int Ni = TapsNum + TapsNum % 2;
    
    for (int i = 0; i < lvl; ++i) begin
        Ni = Ni / 2 + (Ni / 2) % 2;
    end
    
    return Ni;
endfunction

/// calculate full precision output width
function automatic int calcOutWidthFull();
    longint Acc = 0;
    
    for (int i = 0; i < NUM_TAPS; ++i) begin
        longint tmp = $signed(COEFFS[i]);
        tmp = (tmp >= 0) ? tmp : -tmp;
        Acc += tmp;
    end
    
    return $clog2(Acc) + INPUT_WIDTH;
endfunction

/// Local parameters
localparam TreeLevels = $clog2(NUM_TAPS); // number of adder tree levels
localparam TreeWidth0 = 1 << TreeLevels;  // number of elements in entry level
localparam TreeLinkWidthMin = INPUT_WIDTH + COEFF_WIDTH;     // minimal bit width of adder tree link
localparam TreeLinkWidthMax = TreeLinkWidthMin + TreeLevels; // maximal bit width of adder tree link
localparam OutWidthFullPrec = calcOutWidthFull();

// Signals
logic [INPUT_WIDTH - 1: 0] delayLine [0: NUM_TAPS - 1];
logic [TreeLinkWidthMax - 1: 0] adderTreeLinks [TreeLevels: 0] [TreeWidth0 - 1: 0];
logic [OutWidthFullPrec - 1: 0] doutFullPrec;
logic [OUTPUT_WIDTH - 1: 0] dout_i;
logic valid_d, valid_m;
logic valid_i[TreeLevels: 0];
genvar i;
genvar j;


// input stage and delay line
always_ff @(posedge clk) begin
    if (rst) begin
        for (int i = 0; i < NUM_TAPS; ++i) begin
            delayLine[i] <= '0;
        end
    end else begin
        if (valid_in) begin
            delayLine[0] <= din;
            for (int i = 1; i < NUM_TAPS; ++i) begin
                delayLine[i] <= delayLine[i - 1];
            end
        end
    end
    
    valid_d <= (~rst) & valid_in;
end

// mul stage
generate
    for (i = 0; i < TreeWidth0; ++i) begin : mul
        if (i < NUM_TAPS) begin
            if (PIPELINE_MUL) begin
                always_ff @(posedge clk) begin
                    adderTreeLinks[0][i][TreeLinkWidthMin - 1: 0] <= $signed(delayLine[i]) * $signed(COEFFS[i]);
                end
            end else begin
                assign adderTreeLinks[0][i][TreeLinkWidthMin - 1: 0] = $signed(delayLine[i]) * $signed(COEFFS[i]);
            end
        end else begin
            assign adderTreeLinks[0][i] = '0;
        end
    end
    
    if (PIPELINE_MUL) begin
        always_ff @(posedge clk) begin
            valid_i[0] <= (~rst) & valid_d;
        end
    end else begin
        assign valid_i[0] = valid_d;
    end
endgenerate

// adder tree stage
generate
    for (j = 1; j <= TreeLevels; ++j) begin : adderTree
        for (i = 0; i < (TreeWidth0 >> j); ++i) begin : add
            if ( (i < calcNi(NUM_TAPS, j) - 1) || ((TreeWidth0 >> j) == calcNi(NUM_TAPS, j)) ) begin // sum input pairs from previous layer
                if (j % PIPELINE_ADD_RATIO == 0) begin
                    always_ff @(posedge clk) begin
                        adderTreeLinks[j][i][TreeLinkWidthMin - 1 + j: 0] <= $signed(adderTreeLinks[j - 1][2 * i    ][TreeLinkWidthMin - 1 + (j - 1): 0]) +
                                                                             $signed(adderTreeLinks[j - 1][2 * i + 1][TreeLinkWidthMin - 1 + (j - 1): 0]);
                    end
                end else begin
                    assign adderTreeLinks[j][i][TreeLinkWidthMin - 1 + j: 0] = $signed(adderTreeLinks[j - 1][2 * i    ][TreeLinkWidthMin - 1 + (j - 1): 0]) +
                                                                               $signed(adderTreeLinks[j - 1][2 * i + 1][TreeLinkWidthMin - 1 + (j - 1): 0]);
                end
            end else if (i == calcNi(NUM_TAPS, j) - 1) begin // single input, sign extend and pass to the next level
                if (j % PIPELINE_ADD_RATIO == 0) begin
                    always_ff @(posedge clk) begin
                        adderTreeLinks[j][i][TreeLinkWidthMin - 1 + j: 0] <= $signed(adderTreeLinks[j - 1][2 * i][TreeLinkWidthMin - 1 + (j - 1): 0]);
                    end
                end else begin
                    assign adderTreeLinks[j][i][TreeLinkWidthMin - 1 + j: 0] = $signed(adderTreeLinks[j - 1][2 * i][TreeLinkWidthMin - 1 + (j - 1): 0]);
                end
            end else begin
                assign adderTreeLinks[j][i][TreeLinkWidthMin - 1 + j: 0] = '0;
            end
        end
        
        if (j % PIPELINE_ADD_RATIO == 0) begin
            always_ff @(posedge clk) begin
                valid_i[j] <= (~rst) & valid_i[j - 1];
            end
        end else begin
            assign valid_i[j] = valid_i[j - 1];
        end
    end
endgenerate

// full precision output
assign doutFullPrec = adderTreeLinks[TreeLevels][0][OutWidthFullPrec - 1: 0];

//output reg
generate
    if (OUTPUT_WIDTH <= OutWidthFullPrec) begin
        //truncate LSB
        assign dout_i = doutFullPrec[OutWidthFullPrec - 1: OutWidthFullPrec - OUTPUT_WIDTH];
    end else begin
        assign dout_i = $signed(doutFullPrec);
    end
    
    if (OUTPUT_REG) begin
        always_ff @(posedge clk) begin
            dout      <= (rst) ? '0   : dout_i;
            valid_out <= (rst) ? 1'b0 : valid_i[TreeLevels];
        end
    end else begin
        assign dout      = dout_i;
        assign valid_out = valid_i[TreeLevels];
    end
endgenerate

endmodule