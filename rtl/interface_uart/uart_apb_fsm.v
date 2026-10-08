module uart_apb_fsm (
  // Input APB Bus
  input wire pclk,
  input wire presetn,

  // Input tu APB Master, Bus APB
  input wire psel,
  input wire penable,
  input wire pwrite,

  // Tin hieu tu datapath
  input wire addr_match,

  // Output cho datapath interface
  output reg reg_wr_en,
  output reg reg_rd_en,

  // Output cho Bus APB CPU
  output reg pready,
  output reg pslverr
);

  localparam IDLE   = 2'b00;
  localparam SETUP  = 2'b01;
  localparam ACCESS = 2'b10;

  // Reg luu trang thai
  reg [1:0] next_state;
  reg [1:0] current_state;

  // State register
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) current_state <= IDLE;
    else          current_state <= next_state;
  end

  // Next state logic
  always @(current_state or psel) begin
    next_state = current_state;

    case (current_state)
      IDLE: begin
        if (psel) next_state = SETUP;
        else      next_state = IDLE;
      end
      SETUP: next_state = ACCESS;
      ACCESS: begin
        if (psel) next_state = SETUP;
        else      next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  // Output logic
  always @(current_state or addr_match or pwrite) begin
    {pready, pslverr, reg_wr_en, reg_rd_en} = 4'b0;

    case (current_state)
      IDLE: begin
        pready    = 0;
        pslverr   = 0;
        reg_wr_en = 0;
        reg_rd_en = 0;
      end
      SETUP: begin
      end
      ACCESS: begin
        pready    = 1;
        pslverr   = !addr_match;
        reg_wr_en = pwrite && addr_match;
        reg_rd_en = !pwrite && addr_match;
      end
      default: begin
        pready    = 0;
        pslverr   = 0;
        reg_wr_en = 0;
        reg_rd_en = 0;
      end
    endcase
  end
endmodule