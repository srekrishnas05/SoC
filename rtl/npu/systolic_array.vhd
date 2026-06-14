library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;


entity systolic_array is
    generic (
        SIZE : natural := 32
    );
    port (
        clk     : in  std_logic;
        en      : in  std_logic;
        acc_clr : in  std_logic;
        a_west  : in  data_vec_t(0 to SIZE - 1);
        b_north : in  data_vec_t(0 to SIZE - 1);
        c_out   : out acc_mat_t(0 to SIZE - 1, 0 to SIZE - 1)
    );
end systolic_array;

architecture Behavioral of systolic_array is

    -- Internal busses: one extra column/row for sink wires
    type data_bus_a_t is array (0 to SIZE - 1, 0 to SIZE) of data_t;
    type data_bus_b_t is array (0 to SIZE,     0 to SIZE - 1) of data_t;

    signal a_bus_s : data_bus_a_t;
    signal b_bus_s : data_bus_b_t;

begin

    -- Drive west and north edges
    west_gen : for r in 0 to SIZE - 1 generate
        a_bus_s(r, 0) <= a_west(r);
    end generate;

    north_gen : for c in 0 to SIZE - 1 generate
        b_bus_s(0, c) <= b_north(c);
    end generate;

    -- SIZE x SIZE PE grid
    row_gen : for r in 0 to SIZE - 1 generate
        col_gen : for c in 0 to SIZE - 1 generate
            u_pe : entity work.pe
                generic map (SIZE => SIZE)
                port map (
                    clk     => clk,
                    en      => en,
                    acc_clr => acc_clr,
                    a_in    => a_bus_s(r, c),
                    b_in    => b_bus_s(r, c),
                    a_out   => a_bus_s(r, c + 1),
                    b_out   => b_bus_s(r + 1, c),
                    c_out   => c_out(r, c));
        end generate;
    end generate;

end Behavioral;