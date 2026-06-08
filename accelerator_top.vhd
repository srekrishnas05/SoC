library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;

-- ============================================================
-- NPU Accelerator Top
-- ============================================================
-- 32x32 output-stationary INT8 systolic matmul:
--
--   c_tile = a_tile * b_tile  (signed INT8 x INT8 -> ACC_WIDTH)
--
-- Sub-blocks:
--   cu : controller_fsm  - sequences COMPUTE / DRAIN / STORE
--   sa : skew_injector   - diagonal alignment of A operands
--   sb : skew_injector   - diagonal alignment of B operands
--   ar : systolic_array  - 32x32 grid of MAC PEs
--
-- The output tile is latched into c_tile_r when the controller
-- pulses store_s, then driven on c_tile.
-- ============================================================

entity accelerator_top is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        a_tile : in  data_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        b_tile : in  data_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        c_tile : out acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        done   : out std_logic;
        swap   : out std_logic
    );
end accelerator_top;

architecture Behavioral of accelerator_top is

    -- Controller wires
    signal acc_clr_s    : std_logic;
    signal stream_en_s  : std_logic;
    signal pe_en_s      : std_logic;
    signal store_s      : std_logic;
    signal swap_s       : std_logic;
    signal done_s       : std_logic;
    signal stream_idx_s : natural range 0 to SIZE - 1;

    -- Operand streams (one element per row/col per cycle)
    signal a_stream_s : data_vec_t(0 to SIZE - 1);
    signal b_stream_s : data_vec_t(0 to SIZE - 1);

    -- After diagonal skew
    signal a_skew_s : data_vec_t(0 to SIZE - 1);
    signal b_skew_s : data_vec_t(0 to SIZE - 1);

    -- Raw and latched output tile
    signal c_raw_s  : acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
    signal c_tile_r : acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1) :=
        (others => (others => (others => '0')));

    -- --------------------------------------------------------
    -- Component declarations
    -- --------------------------------------------------------
    component controller_fsm port(
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        acc_clr    : out std_logic;
        stream_en  : out std_logic;
        pe_en      : out std_logic;
        store      : out std_logic;
        swap       : out std_logic;
        done       : out std_logic;
        stream_idx : out natural range 0 to SIZE - 1);
    end component;

    component skew_injector port(
        clk   : in  std_logic;
        en    : in  std_logic;
        d_in  : in  data_vec_t(0 to SIZE - 1);
        d_out : out data_vec_t(0 to SIZE - 1));
    end component;

    component systolic_array port(
        clk     : in  std_logic;
        en      : in  std_logic;
        acc_clr : in  std_logic;
        a_west  : in  data_vec_t(0 to SIZE - 1);
        b_north : in  data_vec_t(0 to SIZE - 1);
        c_out   : out acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1));
    end component;

begin

    -- --------------------------------------------------------
    -- Controller
    -- --------------------------------------------------------
    cu : controller_fsm port map(
        clk        => clk,
        rst        => rst,
        start      => start,
        acc_clr    => acc_clr_s,
        stream_en  => stream_en_s,
        pe_en      => pe_en_s,
        store      => store_s,
        swap       => swap_s,
        done       => done_s,
        stream_idx => stream_idx_s);

    -- --------------------------------------------------------
    -- Operand streaming mux
    -- ---- A reads column stream_idx_s of a_tile
    -- ---- B reads row    stream_idx_s of b_tile
    -- Outputs are zero when streaming is disabled, so the array
    -- naturally drains during DRAIN/STORE phases.
    -- --------------------------------------------------------
    process(all)
    begin
        for i in 0 to SIZE - 1 loop
            a_stream_s(i) <= (others => '0');
            b_stream_s(i) <= (others => '0');
        end loop;

        if stream_en_s = '1' then
            for i in 0 to SIZE - 1 loop
                a_stream_s(i) <= a_tile(i, stream_idx_s);
                b_stream_s(i) <= b_tile(stream_idx_s, i);
            end loop;
        end if;
    end process;

    -- --------------------------------------------------------
    -- Diagonal skew on both operand streams
    -- --------------------------------------------------------
    sa : skew_injector port map(
        clk   => clk,
        en    => '1',
        d_in  => a_stream_s,
        d_out => a_skew_s);

    sb : skew_injector port map(
        clk   => clk,
        en    => '1',
        d_in  => b_stream_s,
        d_out => b_skew_s);

    -- --------------------------------------------------------
    -- 32x32 PE array
    -- --------------------------------------------------------
    ar : systolic_array port map(
        clk     => clk,
        en      => pe_en_s,
        acc_clr => acc_clr_s,
        a_west  => a_skew_s,
        b_north => b_skew_s,
        c_out   => c_raw_s);

    -- --------------------------------------------------------
    -- Output tile latch
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if store_s = '1' then
                c_tile_r <= c_raw_s;
            end if;
        end if;
    end process;

    done   <= done_s;
    swap   <= swap_s;
    c_tile <= c_tile_r;

end Behavioral;