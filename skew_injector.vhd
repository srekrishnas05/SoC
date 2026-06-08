library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;

-- ============================================================
-- Skew Injector
-- ============================================================
-- Aligns SIZE parallel input streams in time so they enter the
-- systolic array along the correct diagonal:
--
--   stream 0 : 0 cycles of delay
--   stream 1 : 1 cycle  of delay
--   ...
--   stream N-1 : N-1 cycles of delay
--
-- Implemented as a SIZE x SIZE shift-register matrix.
-- Each row r advances one stage per cycle when en is high.
-- ============================================================

entity skew_injector is
    port (
        clk  : in  std_logic;
        en   : in  std_logic;
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

    -- Stream 0 has zero-cycle delay; stream i (i>0) uses (i-1) stages.
    skew_out_gen : for i in 0 to SIZE - 1 generate
        stream0_gen : if i = 0 generate
            d_out(i) <= d_in(i);
        end generate stream0_gen;
        streamn_gen : if i > 0 generate
            d_out(i) <= sr_r(i, i - 1);
        end generate streamn_gen;
    end generate skew_out_gen;

end Behavioral;