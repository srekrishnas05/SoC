library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity sram_1r1w is
    generic (
        DATA_WIDTH : positive := 8;
        DEPTH      : positive := 1024
    );
    port (
        clk   : in  std_logic;
        we    : in  std_logic;
        waddr : in  natural range 0 to DEPTH - 1;
        wdata : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        raddr : in  natural range 0 to DEPTH - 1;
        rdata : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end sram_1r1w;

architecture Behavioral of sram_1r1w is
    type mem_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal mem_r   : mem_t := (others => (others => '0'));
    signal rdata_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem_r(waddr) <= wdata;
            end if;
            rdata_r <= mem_r(raddr);
        end if;
    end process;

    rdata <= rdata_r;

end Behavioral;