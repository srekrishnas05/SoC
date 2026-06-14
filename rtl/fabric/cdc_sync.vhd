library IEEE;
use IEEE.STD_LOGIC_1164.ALL;



entity cdc_sync is
    generic (
        STAGES : natural := 2   
    );
    port (
        dst_clk : in  std_logic;
        d_in    : in  std_logic;
        d_out   : out std_logic
    );
end cdc_sync;

architecture Behavioral of cdc_sync is

    type sync_chain_t is array (0 to STAGES - 1) of std_logic;
    signal chain_r : sync_chain_t := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of chain_r : signal is "TRUE";

begin

    process(dst_clk)
    begin
        if rising_edge(dst_clk) then
            chain_r(0) <= d_in;
            for i in 1 to STAGES - 1 loop
                chain_r(i) <= chain_r(i - 1);
            end loop;
        end if;
    end process;

    d_out <= chain_r(STAGES - 1);

end Behavioral;