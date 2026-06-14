library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;


entity skew_injector is
    generic (
        SIZE : natural := 32
    );
    port (
        clk   : in  std_logic;
        en    : in  std_logic;
        d_in  : in  data_vec_t(0 to SIZE - 1);
        d_out : out data_vec_t(0 to SIZE - 1)
    );
end skew_injector;

architecture Behavioral of skew_injector is
    type shift_reg_t is array (0 to SIZE - 1, 0 to SIZE - 1) of data_t;
    signal sr_r : shift_reg_t := (others => (others => (others => '0')));
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' then
                for r in 0 to SIZE - 1 loop
                    sr_r(r, 0) <= d_in(r);
                    for s in 1 to SIZE - 1 loop
                        sr_r(r, s) <= sr_r(r, s - 1);
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -- Stream 0: combinational passthrough (zero delay)
    -- Stream i (i > 0): tap after i-1 register stages
    skew_out : for i in 0 to SIZE - 1 generate
        zero_delay : if i = 0 generate
            d_out(i) <= d_in(i);
        end generate;
        nonzero_delay : if i > 0 generate
            d_out(i) <= sr_r(i, i - 1);
        end generate;
    end generate;

end Behavioral;