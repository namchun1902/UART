`timescale 1ns/1ps

module tb_apb_datapath;

  //-------------------------------------------------------------
  // Signals
  //-------------------------------------------------------------
  reg         pclk;
  reg         presetn;
  reg  [11:0] paddr;
  reg  [31:0] pwdata;
  reg  [3:0]  pstrb;
  reg         reg_wr_en;
  reg         reg_rd_en;
  reg  [7:0]  rx_data;
  reg         rx_done;
  reg         parity_error;
  reg         tx_done;

  wire [31:0] prdata;
  wire        addr_match;
  wire [7:0]  tx_data;
  wire        start_tx;
  wire        clear_rx_done;
  wire [1:0]  data_bit_num;
  wire        stop_bit_num;
  wire        parity_en;
  wire        parity_type;

  //-------------------------------------------------------------
  // DUT
  //-------------------------------------------------------------
  apb_datapath dut (
    .pclk          (pclk),
    .presetn       (presetn),
    .paddr         (paddr),
    .pwdata        (pwdata),
    .pstrb         (pstrb),
    .reg_wr_en     (reg_wr_en),
    .reg_rd_en     (reg_rd_en),
    .rx_data       (rx_data),
    .rx_done       (rx_done),
    .parity_error  (parity_error),
    .tx_done       (tx_done),
    .prdata        (prdata),
    .addr_match    (addr_match),
    .tx_data       (tx_data),
    .start_tx      (start_tx),
    .clear_rx_done (clear_rx_done),
    .data_bit_num  (data_bit_num),
    .stop_bit_num  (stop_bit_num),
    .parity_en     (parity_en),
    .parity_type   (parity_type)
  );

  //-------------------------------------------------------------
  // Clock: 50 MHz
  //-------------------------------------------------------------
  localparam CLK_PERIOD = 20;
  initial pclk = 0;
  always #(CLK_PERIOD/2) pclk = ~pclk;

  //-------------------------------------------------------------
  // Counters
  //-------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  //-------------------------------------------------------------
  // Task: Write a register via APB datapath
  //   Simulates the FSM asserting reg_wr_en for 1 clock cycle
  //-------------------------------------------------------------
  task write_reg(input [11:0] addr, input [31:0] data, input [3:0] strb);
    begin
      @(posedge pclk);
      paddr     <= addr;
      pwdata    <= data;
      pstrb     <= strb;
      reg_wr_en <= 1;
      @(posedge pclk);
      reg_wr_en <= 0;
    end
  endtask

  //-------------------------------------------------------------
  // Task: Read a register via APB datapath
  //-------------------------------------------------------------
  task read_reg(input [11:0] addr, output [31:0] data);
    begin
      @(posedge pclk);
      paddr     <= addr;
      reg_rd_en <= 1;
      #1; // let combinational MUX settle
      data = prdata;
      @(posedge pclk);
      reg_rd_en <= 0;
    end
  endtask

  //-------------------------------------------------------------
  // Task: Check value
  //-------------------------------------------------------------
  task check(input [31:0] actual, input [31:0] expected, input [255:0] msg);
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: got=0x%08h, exp=0x%08h", msg, actual, expected);
        fail_count = fail_count + 1;
      end else begin
        $display("[PASS] %0s: 0x%08h", msg, actual);
        pass_count = pass_count + 1;
      end
    end
  endtask

  task check1(input actual, input expected, input [255:0] msg);
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0s: got=%b, exp=%b", msg, actual, expected);
        fail_count = fail_count + 1;
      end else begin
        $display("[PASS] %0s: %b", msg, actual);
        pass_count = pass_count + 1;
      end
    end
  endtask

  //-------------------------------------------------------------
  // Test Stimulus
  //-------------------------------------------------------------
  reg [31:0] rd_data;

  initial begin
    $dumpfile("tb_apb_datapath.vcd");
    $dumpvars(0, tb_apb_datapath);

    // ---- Initialize ----
    presetn      = 0;
    paddr        = 0;
    pwdata       = 0;
    pstrb        = 4'b0000;
    reg_wr_en    = 0;
    reg_rd_en    = 0;
    rx_data      = 0;
    rx_done      = 0;
    parity_error = 0;
    tx_done      = 0;

    // ========================================================
    // TC1: Reset Test
    // ========================================================
    $display("\n===== TC1: Reset Test =====");
    repeat(3) @(posedge pclk);
    // Read all registers - expect 0
    paddr = 12'h000; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC1a: tx_data_reg after reset");
    reg_rd_en = 0;
    @(posedge pclk);

    paddr = 12'h004; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC1b: rx_data_reg after reset");
    reg_rd_en = 0;
    @(posedge pclk);

    paddr = 12'h008; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC1c: cfg_reg after reset");
    reg_rd_en = 0;
    @(posedge pclk);

    paddr = 12'h00C; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC1d: ctrl_reg after reset");
    reg_rd_en = 0;
    @(posedge pclk);

    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC1e: stt_reg after reset");
    reg_rd_en = 0;

    // Release reset
    @(posedge pclk);
    presetn = 1;
    @(posedge pclk);

    // ========================================================
    // TC2: addr_match Logic
    // ========================================================
    $display("\n===== TC2: Address Match Logic =====");
    paddr = 12'h000; #1;
    check1(addr_match, 1, "TC2a: addr 0x000 match");

    paddr = 12'h004; #1;
    check1(addr_match, 1, "TC2b: addr 0x004 match");

    paddr = 12'h008; #1;
    check1(addr_match, 1, "TC2c: addr 0x008 match");

    paddr = 12'h00C; #1;
    check1(addr_match, 1, "TC2d: addr 0x00C match");

    paddr = 12'h010; #1;
    check1(addr_match, 1, "TC2e: addr 0x010 match");

    paddr = 12'h014; #1;
    check1(addr_match, 0, "TC2f: addr 0x014 no match");

    paddr = 12'hFFF; #1;
    check1(addr_match, 0, "TC2g: addr 0xFFF no match");

    paddr = 12'h100; #1;
    check1(addr_match, 0, "TC2h: addr 0x100 no match");

    // ========================================================
    // TC3: Write & Read tx_data_reg (0x000)
    // ========================================================
    $display("\n===== TC3: Write/Read tx_data_reg (0x000) =====");
    write_reg(12'h000, 32'h000000A5, 4'b0001);
    @(posedge pclk);

    // Read back
    paddr = 12'h000; reg_rd_en = 1; #1;
    check(prdata, 32'h000000A5, "TC3a: tx_data_reg readback");
    reg_rd_en = 0;

    // Check tx_data output (lower 8 bits)
    check(tx_data, 8'hA5, "TC3b: tx_data output");

    // ========================================================
    // TC4: Write & Read cfg_reg (0x008)
    // ========================================================
    $display("\n===== TC4: Write/Read cfg_reg (0x008) =====");

    // cfg = data_bit_num[1:0]=11, stop_bit_num=1, parity_en=1, parity_type=1
    // => cfg_reg = 5'b11111 = 0x1F
    write_reg(12'h008, 32'h0000001F, 4'b0001);
    @(posedge pclk);

    paddr = 12'h008; reg_rd_en = 1; #1;
    check(prdata, 32'h0000001F, "TC4a: cfg_reg readback");
    reg_rd_en = 0;

    check(data_bit_num, 2'b11, "TC4b: data_bit_num=11 (8 bits)");
    check1(stop_bit_num, 1, "TC4c: stop_bit_num=1 (2 stop bits)");
    check1(parity_en, 1, "TC4d: parity_en=1");
    check1(parity_type, 1, "TC4e: parity_type=1 (even)");

    // Change cfg: 5 data bits, 1 stop, no parity
    // data_bit_num=00, stop=0, parity_en=0, parity_type=0 => 0x00
    write_reg(12'h008, 32'h00000000, 4'b0001);
    @(posedge pclk);

    check(data_bit_num, 2'b00, "TC4f: data_bit_num=00 (5 bits)");
    check1(stop_bit_num, 0, "TC4g: stop_bit_num=0 (1 stop bit)");
    check1(parity_en, 0, "TC4h: parity_en=0");
    check1(parity_type, 0, "TC4i: parity_type=0 (odd)");

    // ========================================================
    // TC5: Write & Read ctrl_reg (0x00C) - start_tx auto-clear
    // ========================================================
    $display("\n===== TC5: ctrl_reg & start_tx Auto-Clear =====");

    // Write ctrl_reg[0]=1 -> start_tx=1
    write_reg(12'h00C, 32'h00000001, 4'b0001);
    // start_tx should be 1 immediately after write is sampled
    @(posedge pclk);
    check1(start_tx, 1, "TC5a: start_tx=1 after write ctrl[0]=1");

    // Next cycle: ctrl_reg[0] auto-clears to 0
    @(posedge pclk);
    check1(start_tx, 0, "TC5b: start_tx=0 auto-clear next cycle");

    // Write ctrl with upper bits set
    write_reg(12'h00C, 32'h0000FFFF, 4'b0001);
    @(posedge pclk);
    // ctrl_reg[0] = 1 first cycle
    check1(start_tx, 1, "TC5c: start_tx=1 with upper bits");
    @(posedge pclk);
    check1(start_tx, 0, "TC5d: start_tx=0 auto-clear (upper bits retained)");

    // Read back ctrl_reg - upper bits should be retained, bit[0] cleared
    paddr = 12'h00C; reg_rd_en = 1; #1;
    check(prdata[0], 0, "TC5e: ctrl_reg[0] reads 0 after auto-clear");
    reg_rd_en = 0;

    // ========================================================
    // TC6: rx_data_reg (0x004) - written by rx_done
    // ========================================================
    $display("\n===== TC6: rx_data_reg (Hardware RX Latch) =====");

    // Simulate RX completing with data = 0x5A
    @(posedge pclk);
    rx_data = 8'h5A;
    rx_done = 1;
    @(posedge pclk);
    rx_done = 0;
    @(posedge pclk);

    // Read rx_data_reg
    paddr = 12'h004; reg_rd_en = 1; #1;
    check(prdata, 32'h0000005A, "TC6a: rx_data_reg=0x5A after rx_done");
    reg_rd_en = 0;
    @(posedge pclk);

    // Simulate second RX with data = 0xFF
    rx_data = 8'hFF;
    rx_done = 1;
    @(posedge pclk);
    rx_done = 0;
    @(posedge pclk);

    paddr = 12'h004; reg_rd_en = 1; #1;
    check(prdata, 32'h000000FF, "TC6b: rx_data_reg=0xFF overwrites");
    reg_rd_en = 0;

    // ========================================================
    // TC7: stt_reg (0x010) - Status Register
    // ========================================================
    $display("\n===== TC7: stt_reg (Status Register) =====");

    // Clear all status inputs
    tx_done      = 0;
    rx_done      = 0;
    parity_error = 0;
    @(posedge pclk);
    @(posedge pclk);

    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata, 32'h00000000, "TC7a: stt_reg=0 (all clear)");
    reg_rd_en = 0;
    @(posedge pclk);

    // Set tx_done
    tx_done = 1;
    @(posedge pclk);
    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata[0], 1, "TC7b: stt_reg[0]=1 (tx_done)");
    reg_rd_en = 0;
    tx_done = 0;
    @(posedge pclk);

    // Set rx_done
    rx_data = 8'h00;
    rx_done = 1;
    @(posedge pclk);
    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata[1], 1, "TC7c: stt_reg[1]=1 (rx_done)");
    reg_rd_en = 0;
    rx_done = 0;
    @(posedge pclk);

    // Set parity_error
    parity_error = 1;
    @(posedge pclk);
    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata[2], 1, "TC7d: stt_reg[2]=1 (parity_error)");
    reg_rd_en = 0;
    parity_error = 0;
    @(posedge pclk);

    // All three set
    tx_done      = 1;
    rx_done      = 1;
    parity_error = 1;
    rx_data      = 8'h00;
    @(posedge pclk);
    paddr = 12'h010; reg_rd_en = 1; #1;
    check(prdata[2:0], 3'b111, "TC7e: stt_reg[2:0]=111 (all flags)");
    reg_rd_en = 0;
    tx_done      = 0;
    rx_done      = 0;
    parity_error = 0;

    // ========================================================
    // TC8: clear_rx_done signal
    // ========================================================
    $display("\n===== TC8: clear_rx_done Signal =====");
    @(posedge pclk);

    // Reading addr 0x004 with reg_rd_en -> clear_rx_done=1
    paddr = 12'h004;
    reg_rd_en = 1;
    #1;
    check1(clear_rx_done, 1, "TC8a: clear_rx_done=1 when reading 0x004");

    // Reading other addr -> clear_rx_done=0
    paddr = 12'h000;
    #1;
    check1(clear_rx_done, 0, "TC8b: clear_rx_done=0 when reading 0x000");

    // Not reading (reg_rd_en=0) addr 0x004 -> clear_rx_done=0
    paddr = 12'h004;
    reg_rd_en = 0;
    #1;
    check1(clear_rx_done, 0, "TC8c: clear_rx_done=0 when rd_en=0");

    // ========================================================
    // TC9: pstrb gating (write with pstrb[0]=0 should NOT write)
    // ========================================================
    $display("\n===== TC9: Byte Strobe (pstrb) Gating =====");
    @(posedge pclk);

    // First write known value
    write_reg(12'h000, 32'h00000042, 4'b0001);
    @(posedge pclk);

    // Try to overwrite with pstrb[0]=0 -> should NOT update
    write_reg(12'h000, 32'h000000FF, 4'b0000);
    @(posedge pclk);

    paddr = 12'h000; reg_rd_en = 1; #1;
    check(prdata, 32'h00000042, "TC9a: Write blocked when pstrb[0]=0");
    reg_rd_en = 0;

    // Overwrite with pstrb[0]=1 -> should update
    write_reg(12'h000, 32'h000000FF, 4'b0001);
    @(posedge pclk);

    paddr = 12'h000; reg_rd_en = 1; #1;
    check(prdata, 32'h000000FF, "TC9b: Write passes when pstrb[0]=1");
    reg_rd_en = 0;

    // ========================================================
    // TC10: Write to invalid address (no register affected)
    // ========================================================
    $display("\n===== TC10: Write to Invalid Address =====");
    @(posedge pclk);

    // Store current values
    write_reg(12'h000, 32'hDEAD0001, 4'b0001);
    @(posedge pclk);
    write_reg(12'h008, 32'hDEAD0008, 4'b0001);
    @(posedge pclk);

    // Write to invalid address
    write_reg(12'hFFF, 32'hBADBAD00, 4'b0001);
    @(posedge pclk);

    // Verify original values intact
    paddr = 12'h000; reg_rd_en = 1; #1;
    check(prdata, 32'hDEAD0001, "TC10a: tx_data_reg unchanged after invalid write");
    reg_rd_en = 0;
    @(posedge pclk);

    paddr = 12'h008; reg_rd_en = 1; #1;
    check(prdata, 32'hDEAD0008, "TC10b: cfg_reg unchanged after invalid write");
    reg_rd_en = 0;

    // ========================================================
    // TC11: Read from invalid address -> prdata = 0
    // ========================================================
    $display("\n===== TC11: Read from Invalid Address =====");
    @(posedge pclk);

    paddr = 12'hFFF; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC11a: Read invalid addr -> prdata=0");
    reg_rd_en = 0;

    paddr = 12'h020; reg_rd_en = 1; #1;
    check(prdata, 32'h0, "TC11b: Read 0x020 -> prdata=0");
    reg_rd_en = 0;

    // ========================================================
    // TC12: prdata = 0 when reg_rd_en = 0
    // ========================================================
    $display("\n===== TC12: prdata when rd_en=0 =====");
    @(posedge pclk);

    paddr = 12'h000; reg_rd_en = 0; #1;
    check(prdata, 32'h0, "TC12: prdata=0 when reg_rd_en=0");

    // ========================================================
    // Summary
    // ========================================================
    $display("\n========================================");
    $display("  TOTAL: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================\n");

    #100;
    $finish;
  end

endmodule
