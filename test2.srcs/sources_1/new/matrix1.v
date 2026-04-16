module matrix1 (
    input wire clk,
    input wire [15:0] address,
    output reg signed [31:0] data_out
);
    reg signed [31:0] memory [0:50175];

    initial begin
        $readmemh("matrix1.mif", memory);
    end

    always @(posedge clk) begin
        data_out <= memory[address];
    end
endmodule
