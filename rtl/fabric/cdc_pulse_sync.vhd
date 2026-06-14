library IEEE;
use IEEE.STD_LOGIC_1164.ALL;



entity cdc_pulse_sync is
    port (
        src_clk  : in  std_logic;
        dst_clk  : in  std_logic;
        pulse_in : in  std_logic;   
        pulse_out: out std_logic    
    );
end cdc_pulse_sync;

architecture Behavioral of cdc_pulse_sync is

    signal toggle_r     : std_logic := '0';

    signal sync_chain_r : std_logic_vector(1 downto 0) := "00";
    signal prev_r       : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of sync_chain_r : signal is "TRUE";

begin

    process(src_clk)
    begin
        if rising_edge(src_clk) then
            if pulse_in = '1' then
                toggle_r <= not toggle_r;
            end if;
        end if;
    end process;

    process(dst_clk)
    begin
        if rising_edge(dst_clk) then
            sync_chain_r <= sync_chain_r(0) & toggle_r;
            prev_r       <= sync_chain_r(1);
        end if;
    end process;

    pulse_out <= sync_chain_r(1) xor prev_r;

end Behavioral;