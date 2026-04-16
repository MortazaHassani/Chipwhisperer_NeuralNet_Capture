`timescale 1ns / 1ps
`default_nettype none

module cw305_top #(
    parameter pBYTECNT_SIZE = 7,
    parameter pADDR_WIDTH   = 21
)(
    // USB interface
    input  wire                   usb_clk,
    inout  wire [7:0]             usb_data,
    input  wire [pADDR_WIDTH-1:0] usb_addr,
    input  wire                   usb_rdn,
    input  wire                   usb_wrn,
    input  wire                   usb_cen,
    input  wire                   usb_trigger,

    // Clocks
    input  wire                   pll_clk1,
    input  wire                   tio_clkin,

    // 20-pin connector
    output wire                   tio_trigger,
    output wire                   tio_clkout,

    // DIP switches / button
    input  wire                   j16_sel,
    input  wire                   k16_sel,
    input  wire                   l14_sel,
    input  wire                   k15_sel,
    input  wire                   pushbutton,

    // LEDs
    output wire                   led1,
    output wire                   led2,
    output wire                   led3
);

    wire [7:0] usb_din;
    wire [7:0] usb_dout;
    wire       usb_isout;

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_iobuf
            IOBUF u_iobuf (
                .IO(usb_data[gi]),
                .I (usb_dout[gi]),
                .O (usb_din[gi]),
                .T (~usb_isout)
            );
        end
    endgenerate

    wire crypt_clk;
    BUFG u_bufg (.I(pll_clk1), .O(crypt_clk));

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_clkout (
        .Q (tio_clkout),
        .C (crypt_clk),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R (1'b0),
        .S (1'b0)
    );

    wire [pADDR_WIDTH-1:pBYTECNT_SIZE] reg_address;
    wire [pBYTECNT_SIZE-1:0]           reg_bytecnt;
    wire [7:0]                          reg_datao;
    wire [7:0]                          reg_datai;
    wire                                reg_read;
    wire                                reg_write;
    wire                                reg_addrvalid;

    cw305_usb_reg_fe #(
        .pBYTECNT_SIZE(pBYTECNT_SIZE),
        .pADDR_WIDTH  (pADDR_WIDTH)
    ) u_usb_reg_fe (
        .rst          (1'b0),
        .usb_clk      (usb_clk),
        .usb_din      (usb_din),
        .usb_dout     (usb_dout),
        .usb_isout    (usb_isout),
        .usb_addr     (usb_addr),
        .usb_rdn      (usb_rdn),
        .usb_wrn      (usb_wrn),
        .usb_alen     (1'b1),
        .usb_cen      (usb_cen),
        .reg_address  (reg_address),
        .reg_bytecnt  (reg_bytecnt),
        .reg_datao    (reg_datao),
        .reg_datai    (reg_datai),
        .reg_read     (reg_read),
        .reg_write    (reg_write),
        .reg_addrvalid(reg_addrvalid)
    );

    `include "cw305_user_defines.v"

    reg [1:0] reg_user_led;
    reg       reg_nn_go;
    
    // Image memory write control from USB
    wire        image_write_en = reg_write && reg_addrvalid && (reg_address < 14'd784);
    wire [15:0] image_write_addr = {2'b0, reg_address};
    wire [7:0]  image_write_data = reg_datao;

    always @(posedge usb_clk) begin
        reg_nn_go <= 1'b0;
        if (reg_write && reg_addrvalid) begin
            case (reg_address)
                `REG_NN_GO    : reg_nn_go   <= reg_datao[0];
                `REG_USER_LED : reg_user_led <= reg_datao[1:0];
                default: ;
            endcase
        end
    end

    // Sync NN_GO to crypt_clk
    reg [5:0] go_stretch_ctr;
    reg       go_stretch_active;
    always @(posedge usb_clk) begin
        if (reg_nn_go)
            go_stretch_ctr <= 6'd63;
        else if (go_stretch_ctr != 6'd0)
            go_stretch_ctr <= go_stretch_ctr - 6'd1;
        go_stretch_active <= (go_stretch_ctr != 6'd0) | reg_nn_go;
    end

    (* ASYNC_REG = "TRUE" *) reg go_sync1, go_sync2;
    reg go_prev;
    always @(posedge crypt_clk) begin
        go_sync1 <= go_stretch_active;
        go_sync2 <= go_sync1;
        go_prev  <= go_sync2;
    end
    wire nn_start_pulse = go_sync2 & ~go_prev;

    // Neural Network Instance
    wire nn_done;
    wire [3:0] nn_result;
    wire [3:0] nn_current_state;
    wire [3:0] nn_next_state;

    neural_network u_nn (
        .clk              (crypt_clk),
        .resetn           (1'b1), // Tie reset high for now, or use pushbutton
        .start            (nn_start_pulse),
        .done             (nn_done),
        .current_state    (nn_current_state),
        .next_state       (nn_next_state),
        .argmax_output    (nn_result),
        .image_write_addr (image_write_addr),
        .image_write_data (image_write_data),
        .image_write_en   (image_write_en)
    );

    // Trigger stretcher
    reg [5:0] trig_stretch;
    always @(posedge crypt_clk) begin
        if (nn_start_pulse)
            trig_stretch <= 6'd63;
        else if (trig_stretch != 6'd0)
            trig_stretch <= trig_stretch - 6'd1;
    end
    assign tio_trigger = (trig_stretch != 6'd0);

    // Read mux
    reg [7:0] reg_read_data;
    always @(*) begin
        if (reg_address < 14'd784) begin
            reg_read_data = 8'h0; // Image memory read not implemented via USB for now
        end else begin
            case (reg_address)
                `REG_NN_GO     : reg_read_data = {7'b0, reg_nn_go};
                `REG_NN_RESULT : reg_read_data = {4'b0, nn_result};
                `REG_NN_DONE   : reg_read_data = {7'b0, nn_done};
                `REG_USER_LED  : reg_read_data = {6'b0, reg_user_led};
                `REG_NN_STATE  : reg_read_data = {4'b0, nn_current_state};
                default        : reg_read_data = 8'hAD;
            endcase
        end
    end
    assign reg_datai = reg_read_data;

    assign led1 = nn_done;
    assign led2 = reg_user_led[0];
    assign led3 = reg_user_led[1];

    (* keep = "true" *) wire unused = usb_trigger | tio_clkin
                                    | j16_sel | k16_sel | l14_sel | k15_sel
                                    | pushbutton | (|reg_bytecnt) | reg_read
                                    | (|nn_next_state);

endmodule
