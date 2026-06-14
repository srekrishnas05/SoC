library IEEE;
use IEEE.STD_LOGIC_1164.ALL;



entity rst_sync is
    port (
        clk     : in  std_logic;
        rst_in  : in  std_logic;  -- async reset input (active high)
        rst_out : out std_logic   -- sync reset output (active high)
    );
end rst_sync;

architecture Behavioral of rst_sync is
    signal chain_r : std_logic_vector(1 downto 0) := "11";
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of chain_r : signal is "TRUE";
begin
    process(clk, rst_in)
    begin
        if rst_in = '1' then
            chain_r <= "11";          -- async assert
        elsif rising_edge(clk) then
            chain_r <= chain_r(0) & '0';  -- sync deassert
        end if;
    end process;

    rst_out <= chain_r(1);
end Behavioral;