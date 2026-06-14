library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;


entity accelerator_top is
    generic (
        SIZE : natural := 32
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        start  : in  std_logic;
        a_tile : in  data_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        b_tile : in  data_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        c_tile : out acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
        done   : out std_logic
    );
end accelerator_top;

architecture Behavioral of accelerator_top is

    signal acc_clr_s    : std_logic;
    signal stream_en_s  : std_logic;
    signal pe_en_s      : std_logic;
    signal store_s      : std_logic;
    signal swap_s       : std_logic;
    signal done_s       : std_logic;
    signal stream_idx_s : natural range 0 to SIZE - 1;

    signal a_stream_s : data_vec_t(0 to SIZE - 1);
    signal b_stream_s : data_vec_t(0 to SIZE - 1);
    signal a_skew_s   : data_vec_t(0 to SIZE - 1);
    signal b_skew_s   : data_vec_t(0 to SIZE - 1);

    signal c_raw_s  : acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1);
    signal c_tile_r : acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1) :=
        (others => (others => (others => '0')));

begin

    -- Controller
    cu : entity work.controller_fsm
        generic map (SIZE => SIZE)
        port map (
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

    -- Operand streaming mux
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

    -- Diagonal skew
    sa : entity work.skew_injector
        generic map (SIZE => SIZE)
        port map (clk => clk, en => '1', d_in => a_stream_s, d_out => a_skew_s);

    sb : entity work.skew_injector
        generic map (SIZE => SIZE)
        port map (clk => clk, en => '1', d_in => b_stream_s, d_out => b_skew_s);

    -- Systolic array
    ar : entity work.systolic_array
        generic map (SIZE => SIZE)
        port map (
            clk     => clk,
            en      => pe_en_s,
            acc_clr => acc_clr_s,
            a_west  => a_skew_s,
            b_north => b_skew_s,
            c_out   => c_raw_s);

    -- Output latch
    process(clk)
    begin
        if rising_edge(clk) then
            if store_s = '1' then
                c_tile_r <= c_raw_s;
            end if;
        end if;
    end process;

    done   <= done_s;
    c_tile <= c_tile_r;

end Behavioral;