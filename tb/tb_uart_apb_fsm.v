`timescale 1ns/1ps

module tb_uart_apb_fsm;

  //-------------------------------------------------------------
  // Signals
  //-------------------------------------------------------------
  reg        pclk;
  reg        presetn;
  reg        psel;
  reg        penable;
  reg        pwrite;
  reg        addr_match;

  wire       reg_wr_en;
  wire       reg_rd_en;
  wire       pready;
  wire       pslverr;

  //-------------------------------------------------------------
  // DUT
  //-------------------------------------------------------------
  uart_apb_fsm dut (
    .pclk      (pclk),
    .presetn   (presetn),
    .psel      (psel),
    .penable   (penable),
    .pwrite    (pwrite),
    .addr_match(addr_match),
    .reg_wr_en (reg_wr_en),
    .reg_rd_en (reg_rd_en),
    .pready    (pready),
    .pslverr   (pslverr)
  );

  //-------------------------------------------------------------
  // Clock: 50 MHz => 20 ns period
  //-------------------------------------------------------------
  localparam CLK_PERIOD = 20;
  initial pclk = 0;
  always #(CLK_PERIOD/2) pclk = ~pclk;

  //-------------------------------------------------------------
  // Task: APB Write Transaction
  //-------------------------------------------------------------
  task apb_write(input match);
    begin
      // SETUP phase
      @(posedge pclk);
      psel      <= 1;
      penable   <= 0;
      pwrite    <= 1;
      addr_match <= match;

      // ACCESS phase
      @(posedge pclk);
      penable   <= 1;

      // Wait for pready (1 cycle in ACCESS state)
      @(posedge pclk);
      
      // De-assert
      psel      <= 0;
      penable   <= 0;
      pwrite    <= 0;
    end
  endtask

  //-------------------------------------------------------------
  // Task: APB Read Transaction
  //-------------------------------------------------------------
  task apb_read(input match);
    begin
      // SETUP phase
      @(posedge pclk);
      psel      <= 1;
      penable   <= 0;
      pwrite    <= 0;
      addr_match <= match;

      // ACCESS phase
      @(posedge pclk);
      penable   <= 1;

      // Wait for pready
      @(posedge pclk);

      // De-assert
      psel      <= 0;
      penable   <= 0;
    end
  endtask

  //-------------------------------------------------------------
  // Helper: Check outputs at ACCESS state
  //-------------------------------------------------------------
  integer pass_count = 0;
  integer fail_count = 0;

  task check_outputs(
    input exp_pready,
    input exp_pslverr,
    input exp_wr_en,
    input exp_rd_en,
    input [255:0] test_name
  );
    begin
      // Sample at ACCESS state (current clock edge)
      #1; // small delay to let combinational outputs settle
      if (pready !== exp_pready || pslverr !== exp_pslverr ||
          reg_wr_en !== exp_wr_en || reg_rd_en !== exp_rd_en) begin
        $display("[FAIL] %0s", test_name);
        $display("  pready:    got=%b exp=%b", pready, exp_pready);
        $display("  pslverr:   got=%b exp=%b", pslverr, exp_pslverr);
        $display("  reg_wr_en: got=%b exp=%b", reg_wr_en, exp_wr_en);
        $display("  reg_rd_en: got=%b exp=%b", reg_rd_en, exp_rd_en);
        fail_count = fail_count + 1;
      end else begin
        $display("[PASS] %0s", test_name);
        pass_count = pass_count + 1;
      end
    end
  endtask

  //-------------------------------------------------------------
  // Test Stimulus
  //-------------------------------------------------------------
  initial begin
    $dumpfile("tb_uart_apb_fsm.vcd");
    $dumpvars(0, tb_uart_apb_fsm);

    // ---- Initialize ----
    presetn    = 0;
    psel       = 0;
    penable    = 0;
    pwrite     = 0;
    addr_match = 0;

    // ---- TC1: Reset test ----
    $display("\n===== TC1: Reset Test =====");
    repeat(3) @(posedge pclk);
    #1;
    if (pready === 0 && pslverr === 0 && reg_wr_en === 0 && reg_rd_en === 0)
      begin $display("[PASS] TC1: All outputs 0 during reset"); pass_count = pass_count + 1; end
    else
      begin $display("[FAIL] TC1: Outputs not 0 during reset"); fail_count = fail_count + 1; end

    // Release reset
    @(posedge pclk);
    presetn = 1;
    @(posedge pclk);

    // ---- TC2: IDLE state - no psel ----
    $display("\n===== TC2: IDLE State (psel=0) =====");
    @(posedge pclk);
    psel = 0;
    @(posedge pclk);
    check_outputs(0, 0, 0, 0, "TC2: IDLE outputs all zero");

    // ---- TC3: APB Write with addr_match=1 ----
    $display("\n===== TC3: APB Write (addr_match=1) =====");
    apb_write(1);
    // Check at the ACCESS cycle - outputs are combinational on current_state
    // After apb_write, FSM was in ACCESS state during the 3rd posedge
    // We need to check during ACCESS state
    // Re-run checking inline:

    @(posedge pclk); // let bus go idle
    @(posedge pclk);

    // Proper inline test: observe during ACCESS
    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 1;
    addr_match <= 1;
    penable    <= 0;
    @(posedge pclk); // SETUP -> will go to ACCESS next cycle
    penable    <= 1;
    @(posedge pclk); // Now in ACCESS
    check_outputs(1, 0, 1, 0, "TC3: Write valid addr -> pready=1, pslverr=0, wr_en=1");
    psel <= 0;
    penable <= 0;
    pwrite <= 0;

    // ---- TC4: APB Read with addr_match=1 ----
    $display("\n===== TC4: APB Read (addr_match=1) =====");
    @(posedge pclk);
    @(posedge pclk); // ensure IDLE

    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 0;
    addr_match <= 1;
    penable    <= 0;
    @(posedge pclk); // SETUP
    penable    <= 1;
    @(posedge pclk); // ACCESS
    check_outputs(1, 0, 0, 1, "TC4: Read valid addr -> pready=1, pslverr=0, rd_en=1");
    psel <= 0;
    penable <= 0;

    // ---- TC5: APB Write with addr_match=0 (invalid address) ----
    $display("\n===== TC5: APB Write (addr_match=0) - Error =====");
    @(posedge pclk);
    @(posedge pclk);

    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 1;
    addr_match <= 0;
    penable    <= 0;
    @(posedge pclk); // SETUP
    penable    <= 1;
    @(posedge pclk); // ACCESS
    check_outputs(1, 1, 0, 0, "TC5: Write invalid addr -> pslverr=1, wr_en=0");
    psel <= 0;
    penable <= 0;
    pwrite <= 0;

    // ---- TC6: APB Read with addr_match=0 (invalid address) ----
    $display("\n===== TC6: APB Read (addr_match=0) - Error =====");
    @(posedge pclk);
    @(posedge pclk);

    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 0;
    addr_match <= 0;
    penable    <= 0;
    @(posedge pclk); // SETUP
    penable    <= 1;
    @(posedge pclk); // ACCESS
    check_outputs(1, 1, 0, 0, "TC6: Read invalid addr -> pslverr=1, rd_en=0");
    psel <= 0;
    penable <= 0;

    // ---- TC7: Back-to-back transactions (psel stays high) ----
    $display("\n===== TC7: Back-to-back Transactions =====");
    @(posedge pclk);
    @(posedge pclk);

    // First transaction: Write
    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 1;
    addr_match <= 1;
    penable    <= 0;
    @(posedge pclk); // SETUP
    penable    <= 1;
    @(posedge pclk); // ACCESS for 1st txn
    check_outputs(1, 0, 1, 0, "TC7a: Back-to-back 1st write");

    // Keep psel=1 -> goes back to SETUP
    pwrite     <= 0;  // switch to read
    addr_match <= 1;
    penable    <= 0;
    @(posedge pclk); // SETUP for 2nd txn
    penable    <= 1;
    @(posedge pclk); // ACCESS for 2nd txn
    check_outputs(1, 0, 0, 1, "TC7b: Back-to-back 2nd read");
    psel <= 0;
    penable <= 0;

    // ---- TC8: Reset during ACCESS state ----
    $display("\n===== TC8: Reset During ACCESS =====");
    @(posedge pclk);
    @(posedge pclk);

    @(posedge pclk);
    psel       <= 1;
    pwrite     <= 1;
    addr_match <= 1;
    penable    <= 0;
    @(posedge pclk); // SETUP
    penable    <= 1;
    // Assert reset during ACCESS
    @(posedge pclk);
    presetn <= 0;
    @(posedge pclk);
    #1;
    if (pready === 0 && reg_wr_en === 0)
      begin $display("[PASS] TC8: Reset during ACCESS -> returns to IDLE"); pass_count = pass_count + 1; end
    else
      begin $display("[FAIL] TC8: Reset during ACCESS"); fail_count = fail_count + 1; end
    psel <= 0;
    penable <= 0;
    pwrite <= 0;
    presetn <= 1;
    @(posedge pclk);

    // ---- Summary ----
    $display("\n========================================");
    $display("  TOTAL: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("========================================\n");
    
    #100;
    $finish;
  end

endmodule
