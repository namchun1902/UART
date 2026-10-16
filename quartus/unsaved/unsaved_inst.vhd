	component unsaved is
		port (
			clk_clk                      : in  std_logic                    := 'X';             -- clk
			reset_reset_n                : in  std_logic                    := 'X';             -- reset_n
			uart_apb_0_conduit_end_cts_n : in  std_logic                    := 'X';             -- cts_n
			uart_apb_0_conduit_end_rts_n : out std_logic;                                       -- rts_n
			uart_apb_0_conduit_end_tx    : out std_logic;                                       -- tx
			uart_apb_0_conduit_end_rx    : in  std_logic                    := 'X';             -- rx
			uart_apb_0_conduit_end_pstrb : in  std_logic_vector(3 downto 0) := (others => 'X')  -- pstrb
		);
	end component unsaved;

	u0 : component unsaved
		port map (
			clk_clk                      => CONNECTED_TO_clk_clk,                      --                    clk.clk
			reset_reset_n                => CONNECTED_TO_reset_reset_n,                --                  reset.reset_n
			uart_apb_0_conduit_end_cts_n => CONNECTED_TO_uart_apb_0_conduit_end_cts_n, -- uart_apb_0_conduit_end.cts_n
			uart_apb_0_conduit_end_rts_n => CONNECTED_TO_uart_apb_0_conduit_end_rts_n, --                       .rts_n
			uart_apb_0_conduit_end_tx    => CONNECTED_TO_uart_apb_0_conduit_end_tx,    --                       .tx
			uart_apb_0_conduit_end_rx    => CONNECTED_TO_uart_apb_0_conduit_end_rx,    --                       .rx
			uart_apb_0_conduit_end_pstrb => CONNECTED_TO_uart_apb_0_conduit_end_pstrb  --                       .pstrb
		);

