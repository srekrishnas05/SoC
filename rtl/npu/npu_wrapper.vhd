library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;

-- ============================================================
-- NPU Wrapper
-- ============================================================
-- Bridges the CPU MMIO bus (P4, 0x40000400) to accelerator_top.
--
-- Register map (byte address offset from 0x40000400):
--
--   0x00  NPU_CTRL    [0]=start(W), [1]=sw_reset(W),
--                     [2]=busy(R),  [3]=done_latch(R/W1C)
--   0x04  NPU_STATUS  [1:0] = FSM done/busy mirror (RO)
--   0x08  NPU_SEL     [0]=0 select A matrix, 1 select B matrix
--   0x0C  NPU_WADDR   [9:0] flat byte index into matrix (row*32+col)
--   0x10  NPU_WDATA   [7:0] one INT8 byte; write triggers buffer write
--   0x14  NPU_RADDR   [9:0] flat index of result word to read
--   0x18  NPU_RESULT  [31:0] signed 32-bit accumulator (RO)
--
-- Write flow:
--   1. Write matrix sel to NPU_SEL
--   2. For each byte: write index to NPU_WADDR, write byte to NPU_WDATA
--   3. Write 1 to NPU_CTRL[0] (start)
--   4. Poll NPU_CTRL[3] (done_latch) or wait for IRQ
--   5. For each result: write index to NPU_RADDR, read NPU_RESULT
--   6. Write 1 to NPU_CTRL[3] to clear done_latch
--
-- IRQ: done_irq pulses one cycle when computation completes.
--      Wire to CPU irq_line via IRQ controller.
-- ============================================================

entity npu_wrapper is
    port (
        clk      : in  std_logic;

        -- MMIO bus (P4 port)
        p4_addr  : in  std_logic_vector(7 downto 0);
        p4_wdata : in  std_logic_vector(31 downto 0);
        p4_we    : in  std_logic;
        p4_rdata : out std_logic_vector(31 downto 0);

        -- IRQ to CPU interrupt controller
        done_irq : out std_logic
    );
end npu_wrapper;

architecture Behavioral of npu_wrapper is

    -- --------------------------------------------------------
    -- Internal registers
    -- --------------------------------------------------------
    signal ctrl_start    : std_logic := '0';
    signal ctrl_reset    : std_logic := '0';
    signal done_latch    : std_logic := '0';
    signal mat_sel       : std_logic := '0';          -- 0=A, 1=B
    signal waddr_reg     : natural range 0 to 1023 := 0;
    signal raddr_reg     : natural range 0 to 1023 := 0;

    -- --------------------------------------------------------
    -- Ping-pong buffer signals (A and B, one buffer each)
    -- --------------------------------------------------------
    signal pp_we_a    : std_logic := '0';
    signal pp_we_b    : std_logic := '0';
    signal pp_waddr   : natural range 0 to 1023 := 0;
    signal pp_wdata   : std_logic_vector(7 downto 0) := (others => '0');
    signal pp_raddr_a : natural range 0 to 1023 := 0;
    signal pp_raddr_b : natural range 0 to 1023 := 0;
    signal pp_rdata_a : std_logic_vector(7 downto 0);
    signal pp_rdata_b : std_logic_vector(7 downto 0);
    signal pp_swap    : std_logic := '0';

    -- --------------------------------------------------------
    -- Tile reconstruction: assemble data_mat_t from buffer reads
    -- The accelerator streams column stream_idx of A (rows 0..31)
    -- and row stream_idx of B (cols 0..31) each cycle.
    -- We present the full tile combinationally by driving raddr
    -- from the FSM's stream_idx output.
    -- Because the buffer is 1R1W and we need 32 reads per cycle,
    -- we hold the full matrix in a registered tile cache that is
    -- filled before start is asserted.
    -- --------------------------------------------------------
    signal a_tile_r : data_mat_t(0 to SIZE-1, 0 to SIZE-1) :=
        (others => (others => (others => '0')));
    signal b_tile_r : data_mat_t(0 to SIZE-1, 0 to SIZE-1) :=
        (others => (others => (others => '0')));

    -- --------------------------------------------------------
    -- Tile load state machine
    -- Reads all 1024 bytes from each ping-pong buffer into the
    -- tile registers before asserting start to accelerator_top.
    -- --------------------------------------------------------
    type load_state_t is (LS_IDLE, LS_LOAD_A, LS_LOAD_B, LS_LAUNCH);
    signal load_state  : load_state_t := LS_IDLE;
    signal load_idx    : natural range 0 to 1023 := 0;
    signal load_start  : std_logic := '0';  -- one-cycle pulse to start loading
    signal accel_start : std_logic := '0';  -- one-cycle pulse to accelerator

    -- --------------------------------------------------------
    -- Accelerator signals
    -- --------------------------------------------------------
    signal accel_done  : std_logic;
    signal accel_swap  : std_logic;
    signal c_tile_s    : acc_mat_t(0 to SIZE-1, 0 to SIZE-1);
    signal c_tile_r    : acc_mat_t(0 to SIZE-1, 0 to SIZE-1) :=
        (others => (others => (others => '0')));

    signal busy_s      : std_logic := '0';

    -- --------------------------------------------------------
    -- Component declarations
    -- --------------------------------------------------------
    component ping_pong_buffer
        generic (
            DATA_WIDTH : positive := 8;
            DEPTH      : positive := 1024);
        port (
            clk   : in  std_logic;
            swap  : in  std_logic;
            we    : in  std_logic;
            waddr : in  natural range 0 to DEPTH - 1;
            wdata : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
            raddr : in  natural range 0 to DEPTH - 1;
            rdata : out std_logic_vector(DATA_WIDTH - 1 downto 0));
    end component;

    component accelerator_top
        port (
            clk    : in  std_logic;
            rst    : in  std_logic;
            start  : in  std_logic;
            a_tile : in  data_mat_t(0 to SIZE-1, 0 to SIZE-1);
            b_tile : in  data_mat_t(0 to SIZE-1, 0 to SIZE-1);
            c_tile : out acc_mat_t(0 to SIZE-1, 0 to SIZE-1);
            done   : out std_logic;
            swap   : out std_logic);
    end component;

begin

    -- --------------------------------------------------------
    -- Ping-pong buffer A (activations)
    -- --------------------------------------------------------
    u_ppb_a : ping_pong_buffer
        generic map (DATA_WIDTH => 8, DEPTH => 1024)
        port map (
            clk   => clk,
            swap  => pp_swap,
            we    => pp_we_a,
            waddr => pp_waddr,
            wdata => pp_wdata,
            raddr => pp_raddr_a,
            rdata => pp_rdata_a);

    -- --------------------------------------------------------
    -- Ping-pong buffer B (weights)
    -- --------------------------------------------------------
    u_ppb_b : ping_pong_buffer
        generic map (DATA_WIDTH => 8, DEPTH => 1024)
        port map (
            clk   => clk,
            swap  => pp_swap,
            we    => pp_we_b,
            waddr => pp_waddr,
            wdata => pp_wdata,
            raddr => pp_raddr_b,
            rdata => pp_rdata_b);

    -- --------------------------------------------------------
    -- Accelerator top
    -- --------------------------------------------------------
    u_accel : accelerator_top
        port map (
            clk    => clk,
            rst    => ctrl_reset,
            start  => accel_start,
            a_tile => a_tile_r,
            b_tile => b_tile_r,
            c_tile => c_tile_s,
            done   => accel_done,
            swap   => accel_swap);

    -- swap drives both ping-pong buffers
    pp_swap <= accel_swap;

    -- --------------------------------------------------------
    -- MMIO register write decode
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            -- Default pulse signals
            ctrl_start <= '0';
            ctrl_reset <= '0';
            pp_we_a    <= '0';
            pp_we_b    <= '0';
            load_start <= '0';
            accel_start <= '0';

            if p4_we = '1' then
                case p4_addr(4 downto 2) is          -- word-aligned offset

                    when "000" =>                     -- 0x00 NPU_CTRL
                        if p4_wdata(0) = '1' then
                            ctrl_start <= '1';        -- triggers tile load FSM
                            load_start <= '1';
                        end if;
                        if p4_wdata(1) = '1' then
                            ctrl_reset <= '1';
                        end if;
                        if p4_wdata(3) = '1' then
                            done_latch <= '0';        -- W1C clear
                        end if;

                    when "010" =>                     -- 0x08 NPU_SEL
                        mat_sel <= p4_wdata(0);

                    when "011" =>                     -- 0x0C NPU_WADDR
                        waddr_reg <= to_integer(
                            unsigned(p4_wdata(9 downto 0)));

                    when "100" =>                     -- 0x10 NPU_WDATA (triggers write)
                        pp_waddr <= waddr_reg;
                        pp_wdata <= p4_wdata(7 downto 0);
                        if mat_sel = '0' then
                            pp_we_a <= '1';
                        else
                            pp_we_b <= '1';
                        end if;

                    when "101" =>                     -- 0x14 NPU_RADDR
                        raddr_reg <= to_integer(
                            unsigned(p4_wdata(9 downto 0)));

                    when others => null;
                end case;
            end if;

            -- Latch done from accelerator
            if accel_done = '1' then
                done_latch <= '1';
                c_tile_r   <= c_tile_s;
            end if;
        end if;
    end process;

    -- --------------------------------------------------------
    -- Tile load FSM
    -- Reads 1024 bytes from buffer A then 1024 bytes from
    -- buffer B into tile registers, then fires accel_start.
    -- Runs at full clock rate (1024+1024+1 = 2049 cycles).
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            accel_start <= '0';
            busy_s      <= '0';

            case load_state is

                when LS_IDLE =>
                    if load_start = '1' then
                        load_idx   <= 0;
                        load_state <= LS_LOAD_A;
                        busy_s     <= '1';
                    end if;

                when LS_LOAD_A =>
                    busy_s        <= '1';
                    pp_raddr_a    <= load_idx;
                    -- rdata arrives next cycle; latch it
                    if load_idx > 0 then
                        a_tile_r((load_idx-1)/SIZE, (load_idx-1) mod SIZE)
                            <= signed(pp_rdata_a);
                    end if;
                    if load_idx = 1023 then
                        -- capture final byte next cycle via LS_LOAD_B entry
                        load_idx   <= 0;
                        load_state <= LS_LOAD_B;
                    else
                        load_idx <= load_idx + 1;
                    end if;

                when LS_LOAD_B =>
                    busy_s        <= '1';
                    -- capture last A byte on first entry
                    if load_idx = 0 then
                        a_tile_r(1023/SIZE, 1023 mod SIZE)
                            <= signed(pp_rdata_a);
                    end if;
                    pp_raddr_b <= load_idx;
                    if load_idx > 0 then
                        b_tile_r((load_idx-1)/SIZE, (load_idx-1) mod SIZE)
                            <= signed(pp_rdata_b);
                    end if;
                    if load_idx = 1023 then
                        load_idx   <= 0;
                        load_state <= LS_LAUNCH;
                    else
                        load_idx <= load_idx + 1;
                    end if;

                when LS_LAUNCH =>
                    busy_s        <= '1';
                    -- capture final B byte
                    b_tile_r(1023/SIZE, 1023 mod SIZE)
                        <= signed(pp_rdata_b);
                    accel_start   <= '1';
                    load_state    <= LS_IDLE;

            end case;
        end if;
    end process;

    -- --------------------------------------------------------
    -- IRQ output: one-cycle pulse on done
    -- --------------------------------------------------------
    done_irq <= accel_done;

    -- --------------------------------------------------------
    -- MMIO read decode
    -- --------------------------------------------------------
    process(all)
        variable row_v : natural range 0 to SIZE-1;
        variable col_v : natural range 0 to SIZE-1;
    begin
        p4_rdata <= (others => '0');
        row_v := raddr_reg / SIZE;
        col_v := raddr_reg mod SIZE;

        case p4_addr(4 downto 2) is
            when "000" =>                             -- NPU_CTRL
                p4_rdata(2) <= busy_s;
                p4_rdata(3) <= done_latch;
            when "001" =>                             -- NPU_STATUS
                p4_rdata(0) <= accel_done;
                p4_rdata(1) <= busy_s;
            when "110" =>                             -- NPU_RESULT
                p4_rdata <= std_logic_vector(c_tile_r(row_v, col_v));
            when others =>
                p4_rdata <= (others => '0');
        end case;
    end process;

end Behavioral;