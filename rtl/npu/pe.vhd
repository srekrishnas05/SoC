library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.systolic_pkg.all;


entity pe is
    generic (
        SIZE : natural := 32  -- parent array dimension (unused in PE logic,
                               -- carried for structural consistency)
    );
    port (
        clk     : in  std_logic;
        en      : in  std_logic;
        acc_clr : in  std_logic;
        a_in    : in  data_t;
        b_in    : in  data_t;
        a_out   : out data_t;
        b_out   : out data_t;
        c_out   : out acc_t
    );
end pe;

architecture Behavioral of pe is
    signal a_r   : data_t := (others => '0');
    signal b_r   : data_t := (others => '0');
    signal acc_r : acc_t  := (others => '0');
begin

    process(clk)
    begin
        if rising_edge(clk) then
            a_r <= a_in;
            b_r <= b_in;

            if acc_clr = '1' then
                acc_r <= (others => '0');
            elsif en = '1' then
                acc_r <= acc_r + resize(a_in * b_in, ACC_WIDTH);
            end if;
        end if;
    end process;

    a_out <= a_r;
    b_out <= b_r;
    c_out <= acc_r;

end Behavioral;