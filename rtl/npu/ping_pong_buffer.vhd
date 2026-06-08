library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Ping-Pong Buffer
-- ============================================================
-- Two SRAM banks plus a 1-bit selector. While one bank is
-- being consumed (read), the other is being produced (written).
--
--   swap = '1'  : flip the producer/consumer assignment
--   bank_sel_r  : 0 -> write bank0, read bank1
--                 1 -> write bank1, read bank0
--
-- Bank selector initialized to '0' at elaboration.
-- ============================================================

entity ping_pong_buffer is
    generic (
        DATA_WIDTH : positive := 8;
        DEPTH      : positive := 1024
    );
    port (
        clk   : in  std_logic;
        swap  : in  std_logic;
        we    : in  std_logic;
        waddr : in  natural range 0 to DEPTH - 1;
        wdata : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
        raddr : in  natural range 0 to DEPTH - 1;
        rdata : out std_logic_vector(DATA_WIDTH - 1 downto 0)
    );
end ping_pong_buffer;

architecture Behavioral of ping_pong_buffer is

    signal bank_sel_r : std_logic := '0';
    signal we_bank0_s : std_logic;
    signal we_bank1_s : std_logic;
    signal rdata0_s   : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal rdata1_s   : std_logic_vector(DATA_WIDTH - 1 downto 0);

    component sram_1r1w
        generic (
            DATA_WIDTH : positive := 8;
            DEPTH      : positive := 1024);
        port (
            clk   : in  std_logic;
            we    : in  std_logic;
            waddr : in  natural range 0 to DEPTH - 1;
            wdata : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
            raddr : in  natural range 0 to DEPTH - 1;
            rdata : out std_logic_vector(DATA_WIDTH - 1 downto 0));
    end component;

begin

    -- --------------------------------------------------------
    -- Bank selector
    -- --------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if swap = '1' then
                bank_sel_r <= not bank_sel_r;
            end if;
        end if;
    end process;

    we_bank0_s <= we when bank_sel_r = '1' else '0';
    we_bank1_s <= we when bank_sel_r = '0' else '0';

    -- --------------------------------------------------------
    -- Two physical SRAM banks
    -- --------------------------------------------------------
    u_bank0 : sram_1r1w
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            DEPTH      => DEPTH)
        port map (
            clk   => clk,
            we    => we_bank0_s,
            waddr => waddr,
            wdata => wdata,
            raddr => raddr,
            rdata => rdata0_s);

    u_bank1 : sram_1r1w
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            DEPTH      => DEPTH)
        port map (
            clk   => clk,
            we    => we_bank1_s,
            waddr => waddr,
            wdata => wdata,
            raddr => raddr,
            rdata => rdata1_s);

    rdata <= rdata1_s when bank_sel_r = '1' else rdata0_s;

end Behavioral;