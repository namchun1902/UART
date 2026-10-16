
module unsaved (
	clk_clk,
	reset_reset_n,
	uart_apb_0_conduit_end_cts_n,
	uart_apb_0_conduit_end_rts_n,
	uart_apb_0_conduit_end_tx,
	uart_apb_0_conduit_end_rx,
	uart_apb_0_conduit_end_pstrb);	

	input		clk_clk;
	input		reset_reset_n;
	input		uart_apb_0_conduit_end_cts_n;
	output		uart_apb_0_conduit_end_rts_n;
	output		uart_apb_0_conduit_end_tx;
	input		uart_apb_0_conduit_end_rx;
	input	[3:0]	uart_apb_0_conduit_end_pstrb;
endmodule
