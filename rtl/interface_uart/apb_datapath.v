module apb_datapath (
  // Input APB Bus
  input wire pclk,
  input wire presetn,
  input wire [11:0] paddr,  // Bus dia chi tu APB Master
  input wire [31:0] pwdata, // Tin hieu vao 3 thanh ghi tx_data_reg, cfg_reg, ctrl_reg
  input wire [3:0] pstrb,

  // Input tu FSM
  input wire reg_wr_en,
  input wire reg_rd_en,

  // Tu uart_tx & uart_rx
  input wire [7:0] rx_data,
  input wire rx_done,
  input wire parity_error,

  input wire tx_done,

  // Output ve APB Bus
  output reg [31:0] prdata,

  // Output cho FSM
  output wire addr_match,
  
  // Output cho uart_tx & uart_rx
  output wire [7:0] tx_data,
  output wire start_tx,
  output wire clear_rx_done,

  // Tin hieu cho ca tx, rx tu cfg_reg
  output wire [1:0] data_bit_num,
  output wire stop_bit_num,
  output wire parity_en,
  output wire parity_type
);
  // Cac thanh ghi trong datapath
  reg [31:0] tx_data_reg;
  reg [31:0] cfg_reg;
  reg [31:0] ctrl_reg;
  reg [31:0] rx_data_reg;
  reg [31:0] stt_reg;

  // 1. Tin hieu ve FSM / KHoi Validator
  assign addr_match = (paddr==12'h000) || (paddr==12'h004) || (paddr==12'h008) || (paddr==12'h00C) || (paddr==12'h010);

  // Tin hieu enable cho cac thanh ghi
  wire wr_tx_data_en;
  wire wr_cfg_en;
  wire wr_ctrl_en;

  // 2. Write Decoder
  assign wr_tx_data_en = reg_wr_en && pstrb[0] && (paddr == 12'h000);
  assign wr_cfg_en     = reg_wr_en && pstrb[0] && (paddr == 12'h008);
  assign wr_ctrl_en    = reg_wr_en && pstrb[0] && (paddr == 12'h00C);

  // 3. Cac thanh ghi
  // I. Thanh ghi tx_data_reg
  always @(posedge pclk) begin
    if (!presetn) begin
      tx_data_reg <= 0;
    end else if (wr_tx_data_en) begin
      tx_data_reg <= pwdata;
    end else begin
      tx_data_reg <= tx_data_reg;
    end
  end

  // Cat 8 bit tu reg tx_data_reg
  assign tx_data = tx_data_reg[7:0];

  // II. Thanh ghi cfg_reg
  always @(posedge pclk) begin
    if (!presetn) begin
      cfg_reg <= 0;
    end else if (wr_cfg_en) begin
      cfg_reg <= pwdata;
    end else begin
      cfg_reg <= cfg_reg;
    end
  end

  // Cat bit sang tx, rx
  assign data_bit_num = cfg_reg[1:0];
  assign stop_bit_num = cfg_reg[2];
  assign parity_en    = cfg_reg[3];
  assign parity_type  = cfg_reg[4];

  // III. Thanh ghi ctrl_reg
  always @(posedge pclk) begin
    if (!presetn) begin
      ctrl_reg <= 0;
    end else if (wr_ctrl_en) begin
      ctrl_reg <= pwdata;
    end else begin
      ctrl_reg[0] <= 1'b0;
      ctrl_reg[31:1] <= ctrl_reg[31:1];
    end
  end

  // Cat bit sang tx
  assign start_tx = ctrl_reg[0];

  // IV. Thanh ghi rx_data_reg
  always @(posedge pclk) begin
    if(!presetn) begin
      rx_data_reg <= 0;
    end else if (rx_done) begin
      rx_data_reg <= {24'b0, rx_data};
    end else begin
      rx_data_reg <= rx_data_reg;
    end
  end

  // V. Thanh ghi stt_reg
  always @(posedge pclk) begin
    if (!presetn) begin
      stt_reg <= 0;
    end else begin
      stt_reg <= {29'b0, parity_error, rx_done, tx_done};
    end
  end
  
  // Tin hieu clear_rx_done cho uart RX
  assign clear_rx_done = (paddr == 12'h004) && reg_rd_en;

  //4. Bo MUX cho prdata
  always @(reg_rd_en or paddr or tx_data_reg or cfg_reg or ctrl_reg or rx_data_reg or stt_reg) begin
    if (reg_rd_en) begin
      case (paddr)
        12'h000: prdata = tx_data_reg;
        12'h008: prdata = cfg_reg;
        12'h00C: prdata = ctrl_reg;
        12'h004: prdata = rx_data_reg;
        12'h010: prdata = stt_reg;
        default: prdata = 32'h00000000;
      endcase
    end else begin
      prdata = 32'h00000000;
    end
  end
endmodule