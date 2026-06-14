library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity sched_ram is
    generic (
        DEPTH : natural := 65536;
        WIDTH : natural := 136
    );
    port (
        clk   : in  std_logic;

        -- Write port (tile_planner)
        we    : in  std_logic;
        waddr : in  std_logic_vector(15 downto 0);
        wdata : in  std_logic_vector(WIDTH - 1 downto 0);

        -- Read port (dispatch_fsm)
        re    : in  std_logic;
        raddr : in  std_logic_vector(15 downto 0);
        rdata : out std_logic_vector(WIDTH - 1 downto 0)
    );
end sched_ram;

architecture Behavioral of sched_ram is

    type mem_t is array (0 to DEPTH - 1) of
        std_logic_vector(WIDTH - 1 downto 0);
    signal mem_r : mem_t := (others => (others => '0'));

    signal rdata_r : std_logic_vector(WIDTH - 1 downto 0) :=
        (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                mem_r(to_integer(unsigned(waddr))) <= wdata;
            end if;
            if re = '1' then
                rdata_r <= mem_r(to_integer(unsigned(raddr)));
            end if;
        end if;
    end process;

    rdata <= rdata_r;

end Behavioral;