module image_memory (
    input wire clk,
    input wire [15:0] read_address,
    output reg [31:0] data_out,
    input wire [15:0] write_address,
    input wire [7:0] write_data,
    input wire write_enable
);
    reg signed [31:0] memory [0:783];

    // Initialize with zeros or a default image
    integer i;
    initial begin
        for (i = 0; i < 784; i = i + 1)
            memory[i] = 32'h0;
    end

    always @(posedge clk) begin
        if (write_enable)
            memory[write_address] <= {24'h0, write_data};
        data_out <= memory[read_address];
    end
endmodule
