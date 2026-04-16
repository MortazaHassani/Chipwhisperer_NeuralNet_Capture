module matrix_multiply(
    input wire clk,
    input wire start,
    input wire [9:0] m,    
    input wire [9:0] n,    
    input wire [9:0] k,    
    output reg [15:0] input_addr,
    input wire signed [31:0] input_data,    
    output reg [15:0] weight_addr,
    input wire signed [31:0] weight_data,   
    output reg [15:0] output_addr,
    output reg signed [31:0] output_data,   
    output reg write_enable,
    output reg done
);

    localparam IDLE = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0] current_state;
    reg [1:0] next_state;
    reg [9:0] i, j, p;
    reg signed [31:0] temp_sum;
    reg final_store_done;
    reg [1:0] wait_cycle;
    reg first_mult;
    reg last_calc_done;

    // Pipeline registers
    reg signed [31:0] input_data_r, weight_data_r;
    reg signed [31:0] product_r;
    reg [2:0] valid_pipe;
    reg [2:0] first_pipe;
    reg [2:0] last_pipe;
    reg [15:0] out_addr_pipe [0:2];

    always @(posedge clk) begin
        current_state <= next_state;
    end

    always @(*) begin
        case (current_state)
            IDLE: next_state = start ? COMPUTE : IDLE;
            COMPUTE: next_state = (final_store_done && last_calc_done) ? FINISH : COMPUTE;
            FINISH: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        case (current_state)
            IDLE: begin
                if (start) begin
                    i <= 0;
                    j <= 0;
                    p <= 0;
                    temp_sum <= 32'h0;
                    done <= 0;
                    final_store_done <= 0;
                    last_calc_done <= 0;
                    write_enable <= 0;
                    wait_cycle <= 2'd2; // Increased wait for deeper pipeline
                    first_mult <= 1;
                    input_addr <= 0;
                    weight_addr <= 0;
                    valid_pipe <= 0;
                    first_pipe <= 0;
                    last_pipe <= 0;
                end
            end

            COMPUTE: begin
                write_enable <= 0;
                
                // Pipeline stage 1: Memory Fetch (BRAM) - handled by input_addr/weight_addr
                
                // Pipeline stage 2: Input Registers (Wait for BRAM output)
                input_data_r <= input_data;
                weight_data_r <= weight_data;
                
                // Pipeline stage 3: Multiplier
                product_r <= input_data_r * weight_data_r;
                
                // Shift registers for control signals to match pipeline depth
                valid_pipe <= {valid_pipe[1:0], (wait_cycle == 0 && !final_store_done)};
                first_pipe <= {first_pipe[1:0], first_mult};
                last_pipe <= {last_pipe[1:0], (p == k-1 && wait_cycle == 0 && !final_store_done)};
                out_addr_pipe[0] <= i * n + j;
                out_addr_pipe[1] <= out_addr_pipe[0];
                out_addr_pipe[2] <= out_addr_pipe[1];

                if (wait_cycle > 0) begin
                    wait_cycle <= wait_cycle - 1;
                end else if (!final_store_done) begin
                    first_mult <= 0;

                    if (p == k-1) begin
                        if (i == m-1 && j == n-1) begin
                            final_store_done <= 1;
                        end else begin
                            if (j == n-1) begin
                                i <= i + 1;
                                j <= 0;
                            end else begin
                                j <= j + 1;
                            end
                            p <= 0;
                            wait_cycle <= 2'd2;
                            first_mult <= 1;

                            input_addr <= (j == n-1) ? (i + 1) * k : i * k;
                            weight_addr <= (j == n-1) ? 0 : (j + 1);
                        end
                    end else begin
                        p <= p + 1;
                        input_addr <= i * k + p + 1;
                        weight_addr <= (p + 1) * n + j;
                    end
                end

                // Pipeline stage 4: Accumulator and Write
                if (valid_pipe[2]) begin
                    if (first_pipe[2]) begin
                        temp_sum <= product_r;
                    end else begin
                        temp_sum <= temp_sum + product_r;
                    end

                    if (last_pipe[2]) begin
                        output_addr <= out_addr_pipe[2];
                        output_data <= (first_pipe[2]) ? product_r : temp_sum + product_r;
                        write_enable <= 1;
                        if (final_store_done)
                            last_calc_done <= 1;
                    end
                end
            end

            FINISH: begin
                done <= 1;
                write_enable <= 0;
                valid_pipe <= 0;
            end
        endcase
    end

endmodule
