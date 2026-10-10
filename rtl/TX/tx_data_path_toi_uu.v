module tx_data_path
#(parameter DATA_NUM = 8)
(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                tick_last,   
    input  wire [1:0]          data_bit_num,    
    input  wire                stop_bit_num,    
    input  wire                clr_bit,     
    input  wire                clr_stop,    
    input  wire                load_reg,    
    input  wire                shift_reg,   
    input  wire [1:0]          tx_sel,      
    input  wire [DATA_NUM-1:0] tx_data,     
    input  wire                parity_type, 
    output wire                bit_last,    
    output wire                stop_last,   
    output reg                 tx           
);

    //---------------------------------------------------------
    // 1. KHỐI BỘ ĐẾM BIT DỮ LIỆU
    //---------------------------------------------------------
    reg [2:0] bit_cnt; 
    reg [2:0] max_val;

    always @(*) begin
        case(data_bit_num)
            2'b00:   max_val = 3'd4; 
            2'b01:   max_val = 3'd5; 
            2'b10:   max_val = 3'd6; 
            2'b11:   max_val = 3'd7; 
            default: max_val = 3'd7; 
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) bit_cnt <= 3'd0;
        else if(clr_bit) bit_cnt <= 3'd0;
        else if(tick_last) bit_cnt <= bit_cnt + 3'd1;
    end
    assign bit_last = (bit_cnt == max_val);


    //---------------------------------------------------------
    // 2. KHỐI BỘ ĐẾM BIT DỪNG
    //---------------------------------------------------------
    reg [1:0] stop_cnt; 
    reg [1:0] max_stop_val;

    always @(*) begin
        case(stop_bit_num)
            1'b0:    max_stop_val = 2'd1; 
            1'b1:    max_stop_val = 2'd2; 
            default: max_stop_val = 2'd1; 
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) stop_cnt <= 2'd0; 
        else if(clr_stop) stop_cnt <= 2'd0;
        else if(tick_last) stop_cnt <= stop_cnt + 2'd1;
    end
    assign stop_last = (stop_cnt == max_stop_val - 2'd1);


    //---------------------------------------------------------
    // 3. KHỐI TÍNH TOÁN PARITY
    //---------------------------------------------------------
    reg  [DATA_NUM-1:0] mask;
    wire [DATA_NUM-1:0] masked_data; 
    wire                even_parity_cal;
    wire                parity_bit;

    always @(*) begin
        case(data_bit_num)
            2'b00:   mask = 8'b0001_1111; 
            2'b01:   mask = 8'b0011_1111; 
            2'b10:   mask = 8'b0111_1111; 
            2'b11:   mask = 8'b1111_1111; 
            default: mask = 8'b1111_1111;
        endcase
    end

    assign masked_data     = tx_data & mask;  
    assign even_parity_cal = ^masked_data;    
    assign parity_bit      = parity_type ? even_parity_cal : ~even_parity_cal; 

    //---------------------------------------------------------
    // 4 & 5. THANH GHI PISO VÀ MUX ĐẦU RA
    //---------------------------------------------------------
    reg  [DATA_NUM-1:0] reg_data;
    wire                serial_out;

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) reg_data <= {DATA_NUM{1'b1}}; 
        else if(load_reg) reg_data <= tx_data;
        else if(shift_reg) reg_data <= {1'b1, reg_data[DATA_NUM-1:1]}; 
    end
    assign serial_out = reg_data[0];

    always @(*) begin
        case(tx_sel)
            2'b00:   tx = 1'b0;       
            2'b01:   tx = 1'b1;       
            2'b10:   tx = serial_out; 
            2'b11:   tx = parity_bit; 
            default: tx = 1'b1;       
        endcase
    end
endmodule
