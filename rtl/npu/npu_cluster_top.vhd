library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;



entity npu_cluster_top is
    port (
        cpu_clk    : in  std_logic;
        cpu_rst    : in  std_logic;
        npu_clk    : in  std_logic_vector(NUM_NPUS - 1 downto 0);
        job_start  : in  std_logic;
        job_m      : in  std_logic_vector(15 downto 0);
        job_k      : in  std_logic_vector(15 downto 0);
        job_n      : in  std_logic_vector(15 downto 0);
        job_a_base : in  std_logic_vector(31 downto 0);
        job_b_base : in  std_logic_vector(31 downto 0);
        job_c_base : in  std_logic_vector(31 downto 0);
        job_done   : out std_logic;
        npu0_a_tile : in  data_mat_t(0 to 63, 0 to 63);
        npu0_b_tile : in  data_mat_t(0 to 63, 0 to 63);
        npu0_c_tile : out acc_mat_t(0 to 63, 0 to 63);
        npu1_a_tile : in  data_mat_t(0 to 31, 0 to 31);
        npu1_b_tile : in  data_mat_t(0 to 31, 0 to 31);
        npu1_c_tile : out acc_mat_t(0 to 31, 0 to 31);
        npu2_a_tile : in  data_mat_t(0 to 15, 0 to 15);
        npu2_b_tile : in  data_mat_t(0 to 15, 0 to 15);
        npu2_c_tile : out acc_mat_t(0 to 15, 0 to 15);
        npu3_a_tile : in  data_mat_t(0 to 7,  0 to 7);
        npu3_b_tile : in  data_mat_t(0 to 7,  0 to 7);
        npu3_c_tile : out acc_mat_t(0 to 7,  0 to 7);
        npu4_a_tile : in  data_mat_t(0 to 3,  0 to 3);
        npu4_b_tile : in  data_mat_t(0 to 3,  0 to 3);
        npu4_c_tile : out acc_mat_t(0 to 3,  0 to 3);
        npu5_a_tile : in  data_mat_t(0 to 3,  0 to 3);
        npu5_b_tile : in  data_mat_t(0 to 3,  0 to 3);
        npu5_c_tile : out acc_mat_t(0 to 3,  0 to 3)
    );
end npu_cluster_top;

architecture Behavioral of npu_cluster_top is

    -- Per-NPU synchronized resets (npu_clk domains)
    signal npu_rst : std_logic_vector(NUM_NPUS - 1 downto 0);

    -- FIFO signals
    signal cmd_wr_en   : std_logic_vector(NUM_NPUS - 1 downto 0);
    signal cmd_wr_data : std_logic_vector(DESC_WIDTH - 1 downto 0);
    signal cmd_full    : std_logic_vector(NUM_NPUS - 1 downto 0);

    type desc_array_t is array(0 to NUM_NPUS - 1) of
        std_logic_vector(DESC_WIDTH - 1 downto 0);
    signal cmd_rd_data : desc_array_t;
    signal cmd_rd_en   : std_logic_vector(NUM_NPUS - 1 downto 0);
    signal cmd_empty   : std_logic_vector(NUM_NPUS - 1 downto 0);

    -- Done signals
    signal done_npu  : std_logic_vector(NUM_NPUS - 1 downto 0);
    signal done_sync : std_logic_vector(NUM_NPUS - 1 downto 0);

    -- Per-NPU start pulses (npu_clk domain)
    signal npu_start : std_logic_vector(NUM_NPUS - 1 downto 0);

    -- Tile sequencer state (npu_clk domain)
    type seq_state_t    is (SEQ_IDLE, SEQ_WAIT);
    type seq_state_arr_t is array(0 to NUM_NPUS - 1) of seq_state_t;
    signal seq_r : seq_state_arr_t := (others => SEQ_IDLE);

    -- Planner <-> sched_ram
    signal plan_done_s   : std_logic;
    signal num_tiles_s   : std_logic_vector(15 downto 0);
    signal sched_we_s    : std_logic;
    signal sched_waddr_s : std_logic_vector(15 downto 0);
    signal sched_wdata_s : std_logic_vector(DESC_WIDTH - 1 downto 0);

    -- Dispatch_fsm <-> sched_ram
    signal sched_re_s    : std_logic;
    signal sched_raddr_s : std_logic_vector(15 downto 0);
    signal sched_rdata_s : std_logic_vector(DESC_WIDTH - 1 downto 0);

begin

    rst_gen : for i in 0 to NUM_NPUS - 1 generate
        u_rst : entity work.rst_sync
            port map (clk=>npu_clk(i), rst_in=>cpu_rst, rst_out=>npu_rst(i));
    end generate;

    u_planner : entity work.tile_planner
        port map (
            clk=>cpu_clk, rst=>cpu_rst, job_start=>job_start,
            job_m=>job_m, job_k=>job_k, job_n=>job_n,
            job_a_base=>job_a_base, job_b_base=>job_b_base,
            job_c_base=>job_c_base,
            sched_we=>sched_we_s, sched_addr=>sched_waddr_s,
            sched_data=>sched_wdata_s,
            plan_done=>plan_done_s, num_tiles=>num_tiles_s);

    u_sched_ram : entity work.sched_ram
        generic map (DEPTH=>65536, WIDTH=>DESC_WIDTH)
        port map (
            clk=>cpu_clk,
            we=>sched_we_s, waddr=>sched_waddr_s, wdata=>sched_wdata_s,
            re=>sched_re_s, raddr=>sched_raddr_s, rdata=>sched_rdata_s);

    u_dispatch : entity work.dispatch_fsm
        port map (
            clk=>cpu_clk, rst=>cpu_rst,
            plan_done=>plan_done_s, num_tiles=>num_tiles_s,
            sched_re=>sched_re_s, sched_addr=>sched_raddr_s,
            sched_data=>sched_rdata_s,
            cmd_wr_en=>cmd_wr_en, cmd_data=>cmd_wr_data,
            cmd_full=>cmd_full, done_sync=>done_sync,
            job_done=>job_done);


    -- ---- NPU 0 : 64x64 ----
    u_fifo_0 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(0), wr_data=>cmd_wr_data, full=>cmd_full(0),
            rd_clk=>npu_clk(0), rd_rst=>npu_rst(0),
            rd_en=>cmd_rd_en(0), rd_data=>cmd_rd_data(0), empty=>cmd_empty(0));

    u_done_sync_0 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(0), dst_clk=>cpu_clk, pulse_in=>done_npu(0), pulse_out=>done_sync(0));

    process(npu_clk(0))
    begin
        if rising_edge(npu_clk(0)) then
            cmd_rd_en(0) <= '0';
            npu_start(0) <= '0';
            if npu_rst(0) = '1' then
                seq_r(0) <= SEQ_IDLE;
            else
                case seq_r(0) is
                    when SEQ_IDLE =>
                        if cmd_empty(0) = '0' then
                            cmd_rd_en(0) <= '1';
                            npu_start(0) <= '1';
                            seq_r(0)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(0) = '1' then
                            seq_r(0) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_0 : entity work.accelerator_top
        generic map (SIZE=>64)
        port map (clk=>npu_clk(0), rst=>npu_rst(0), start=>npu_start(0),
            a_tile=>npu0_a_tile, b_tile=>npu0_b_tile, c_tile=>npu0_c_tile,
            done=>done_npu(0));

    -- ---- NPU 1 : 32x32 ----
    u_fifo_1 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(1), wr_data=>cmd_wr_data, full=>cmd_full(1),
            rd_clk=>npu_clk(1), rd_rst=>npu_rst(1),
            rd_en=>cmd_rd_en(1), rd_data=>cmd_rd_data(1), empty=>cmd_empty(1));

    u_done_sync_1 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(1), dst_clk=>cpu_clk, pulse_in=>done_npu(1), pulse_out=>done_sync(1));

    process(npu_clk(1))
    begin
        if rising_edge(npu_clk(1)) then
            cmd_rd_en(1) <= '0';
            npu_start(1) <= '0';
            if npu_rst(1) = '1' then
                seq_r(1) <= SEQ_IDLE;
            else
                case seq_r(1) is
                    when SEQ_IDLE =>
                        if cmd_empty(1) = '0' then
                            cmd_rd_en(1) <= '1';
                            npu_start(1) <= '1';
                            seq_r(1)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(1) = '1' then
                            seq_r(1) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_1 : entity work.accelerator_top
        generic map (SIZE=>32)
        port map (clk=>npu_clk(1), rst=>npu_rst(1), start=>npu_start(1),
            a_tile=>npu1_a_tile, b_tile=>npu1_b_tile, c_tile=>npu1_c_tile,
            done=>done_npu(1));

    -- ---- NPU 2 : 16x16 ----
    u_fifo_2 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(2), wr_data=>cmd_wr_data, full=>cmd_full(2),
            rd_clk=>npu_clk(2), rd_rst=>npu_rst(2),
            rd_en=>cmd_rd_en(2), rd_data=>cmd_rd_data(2), empty=>cmd_empty(2));

    u_done_sync_2 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(2), dst_clk=>cpu_clk, pulse_in=>done_npu(2), pulse_out=>done_sync(2));

    process(npu_clk(2))
    begin
        if rising_edge(npu_clk(2)) then
            cmd_rd_en(2) <= '0';
            npu_start(2) <= '0';
            if npu_rst(2) = '1' then
                seq_r(2) <= SEQ_IDLE;
            else
                case seq_r(2) is
                    when SEQ_IDLE =>
                        if cmd_empty(2) = '0' then
                            cmd_rd_en(2) <= '1';
                            npu_start(2) <= '1';
                            seq_r(2)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(2) = '1' then
                            seq_r(2) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_2 : entity work.accelerator_top
        generic map (SIZE=>16)
        port map (clk=>npu_clk(2), rst=>npu_rst(2), start=>npu_start(2),
            a_tile=>npu2_a_tile, b_tile=>npu2_b_tile, c_tile=>npu2_c_tile,
            done=>done_npu(2));

    -- ---- NPU 3 : 8x8 ----
    u_fifo_3 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(3), wr_data=>cmd_wr_data, full=>cmd_full(3),
            rd_clk=>npu_clk(3), rd_rst=>npu_rst(3),
            rd_en=>cmd_rd_en(3), rd_data=>cmd_rd_data(3), empty=>cmd_empty(3));

    u_done_sync_3 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(3), dst_clk=>cpu_clk, pulse_in=>done_npu(3), pulse_out=>done_sync(3));

    process(npu_clk(3))
    begin
        if rising_edge(npu_clk(3)) then
            cmd_rd_en(3) <= '0';
            npu_start(3) <= '0';
            if npu_rst(3) = '1' then
                seq_r(3) <= SEQ_IDLE;
            else
                case seq_r(3) is
                    when SEQ_IDLE =>
                        if cmd_empty(3) = '0' then
                            cmd_rd_en(3) <= '1';
                            npu_start(3) <= '1';
                            seq_r(3)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(3) = '1' then
                            seq_r(3) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_3 : entity work.accelerator_top
        generic map (SIZE=>8)
        port map (clk=>npu_clk(3), rst=>npu_rst(3), start=>npu_start(3),
            a_tile=>npu3_a_tile, b_tile=>npu3_b_tile, c_tile=>npu3_c_tile,
            done=>done_npu(3));

    -- ---- NPU 4 : 4x4 A ----
    u_fifo_4 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(4), wr_data=>cmd_wr_data, full=>cmd_full(4),
            rd_clk=>npu_clk(4), rd_rst=>npu_rst(4),
            rd_en=>cmd_rd_en(4), rd_data=>cmd_rd_data(4), empty=>cmd_empty(4));

    u_done_sync_4 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(4), dst_clk=>cpu_clk, pulse_in=>done_npu(4), pulse_out=>done_sync(4));

    process(npu_clk(4))
    begin
        if rising_edge(npu_clk(4)) then
            cmd_rd_en(4) <= '0';
            npu_start(4) <= '0';
            if npu_rst(4) = '1' then
                seq_r(4) <= SEQ_IDLE;
            else
                case seq_r(4) is
                    when SEQ_IDLE =>
                        if cmd_empty(4) = '0' then
                            cmd_rd_en(4) <= '1';
                            npu_start(4) <= '1';
                            seq_r(4)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(4) = '1' then
                            seq_r(4) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_4 : entity work.accelerator_top
        generic map (SIZE=>4)
        port map (clk=>npu_clk(4), rst=>npu_rst(4), start=>npu_start(4),
            a_tile=>npu4_a_tile, b_tile=>npu4_b_tile, c_tile=>npu4_c_tile,
            done=>done_npu(4));

    -- ---- NPU 5 : 4x4 B ----
    u_fifo_5 : entity work.async_fifo
        generic map (DATA_W=>DESC_WIDTH, DEPTH=>4)
        port map (
            wr_clk=>cpu_clk,   wr_rst=>cpu_rst,
            wr_en=>cmd_wr_en(5), wr_data=>cmd_wr_data, full=>cmd_full(5),
            rd_clk=>npu_clk(5), rd_rst=>npu_rst(5),
            rd_en=>cmd_rd_en(5), rd_data=>cmd_rd_data(5), empty=>cmd_empty(5));

    u_done_sync_5 : entity work.cdc_pulse_sync
                port map (src_clk=>npu_clk(5), dst_clk=>cpu_clk, pulse_in=>done_npu(5), pulse_out=>done_sync(5));

    process(npu_clk(5))
    begin
        if rising_edge(npu_clk(5)) then
            cmd_rd_en(5) <= '0';
            npu_start(5) <= '0';
            if npu_rst(5) = '1' then
                seq_r(5) <= SEQ_IDLE;
            else
                case seq_r(5) is
                    when SEQ_IDLE =>
                        if cmd_empty(5) = '0' then
                            cmd_rd_en(5) <= '1';
                            npu_start(5) <= '1';
                            seq_r(5)     <= SEQ_WAIT;
                        end if;
                    when SEQ_WAIT =>
                        if done_npu(5) = '1' then
                            seq_r(5) <= SEQ_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    u_npu_5 : entity work.accelerator_top
        generic map (SIZE=>4)
        port map (clk=>npu_clk(5), rst=>npu_rst(5), start=>npu_start(5),
            a_tile=>npu5_a_tile, b_tile=>npu5_b_tile, c_tile=>npu5_c_tile,
            done=>done_npu(5));

end Behavioral;