library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: mmio_bus
-- ============================================================
-- Tests:
--  1. DMEM write  : mem_we=1, all p*_we=0, mem_addr/wdata correct
--  2. DMEM read   : rdata = mem_rdata, mem_we=0
--  3. DMEM boundary: top of region (0x0001FFFC) still decodes to dmem
--  4. P0 write    : p0_we=1 only, p0_addr correct
--  5. P0 read     : rdata = p0_rdata
--  6. P1 write    : p1_we=1 only
--  7. P2 write    : p2_we=1 only
--  8. P3 write    : p3_we=1 only
--  9. Unmapped write : all we=0
-- 10. Unmapped read  : rdata=0
-- ============================================================

entity tb_mmio_bus is
end tb_mmio_bus;

architecture Behavioral of tb_mmio_bus is

    -- DUT ports
    signal clk       : std_logic := '0';
    signal addr      : std_logic_vector(31 downto 0) := (others => '0');
    signal wdata     : std_logic_vector(31 downto 0) := (others => '0');
    signal we        : std_logic := '0';
    signal rdata     : std_logic_vector(31 downto 0);

    signal mem_addr  : std_logic_vector(31 downto 0);
    signal mem_wdata : std_logic_vector(31 downto 0);
    signal mem_we    : std_logic;
    signal mem_rdata : std_logic_vector(31 downto 0) := (others => '0');

    signal p0_addr   : std_logic_vector(7 downto 0);
    signal p0_wdata  : std_logic_vector(31 downto 0);
    signal p0_we     : std_logic;
    signal p0_rdata  : std_logic_vector(31 downto 0) := (others => '0');

    signal p1_addr   : std_logic_vector(7 downto 0);
    signal p1_wdata  : std_logic_vector(31 downto 0);
    signal p1_we     : std_logic;
    signal p1_rdata  : std_logic_vector(31 downto 0) := (others => '0');

    signal p2_addr   : std_logic_vector(7 downto 0);
    signal p2_wdata  : std_logic_vector(31 downto 0);
    signal p2_we     : std_logic;
    signal p2_rdata  : std_logic_vector(31 downto 0) := (others => '0');

    signal p3_addr   : std_logic_vector(7 downto 0);
    signal p3_wdata  : std_logic_vector(31 downto 0);
    signal p3_we     : std_logic;
    signal p3_rdata  : std_logic_vector(31 downto 0) := (others => '0');

    signal test_num  : integer := 0;
    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

    component mmio_bus port(
        clk       : in  std_logic;
        addr      : in  std_logic_vector(31 downto 0);
        wdata     : in  std_logic_vector(31 downto 0);
        we        : in  std_logic;
        rdata     : out std_logic_vector(31 downto 0);
        mem_addr  : out std_logic_vector(31 downto 0);
        mem_wdata : out std_logic_vector(31 downto 0);
        mem_we    : out std_logic;
        mem_rdata : in  std_logic_vector(31 downto 0);
        p0_addr   : out std_logic_vector(7 downto 0);
        p0_wdata  : out std_logic_vector(31 downto 0);
        p0_we     : out std_logic;
        p0_rdata  : in  std_logic_vector(31 downto 0);
        p1_addr   : out std_logic_vector(7 downto 0);
        p1_wdata  : out std_logic_vector(31 downto 0);
        p1_we     : out std_logic;
        p1_rdata  : in  std_logic_vector(31 downto 0);
        p2_addr   : out std_logic_vector(7 downto 0);
        p2_wdata  : out std_logic_vector(31 downto 0);
        p2_we     : out std_logic;
        p2_rdata  : in  std_logic_vector(31 downto 0);
        p3_addr   : out std_logic_vector(7 downto 0);
        p3_wdata  : out std_logic_vector(31 downto 0);
        p3_we     : out std_logic;
        p3_rdata  : in  std_logic_vector(31 downto 0));
    end component;

    -- Helper: assert a condition, print pass/fail
    procedure check(
        condition : in boolean;
        name      : in string) is
    begin
        if condition then
            report "PASS [" & name & "]" severity note;
        else
            report "FAIL [" & name & "]" severity error;
        end if;
    end procedure;

begin

    -- Bus is combinational - clock not used internally, but provide it
    clk <= not clk after 5 ns;

    dut : mmio_bus port map(
        clk       => clk,
        addr      => addr,   wdata    => wdata,   we       => we,
        rdata     => rdata,
        mem_addr  => mem_addr, mem_wdata => mem_wdata, mem_we => mem_we,
        mem_rdata => mem_rdata,
        p0_addr   => p0_addr, p0_wdata => p0_wdata, p0_we => p0_we, p0_rdata => p0_rdata,
        p1_addr   => p1_addr, p1_wdata => p1_wdata, p1_we => p1_we, p1_rdata => p1_rdata,
        p2_addr   => p2_addr, p2_wdata => p2_wdata, p2_we => p2_we, p2_rdata => p2_rdata,
        p3_addr   => p3_addr, p3_wdata => p3_wdata, p3_we => p3_we, p3_rdata => p3_rdata);

    process
    begin
        -- Allow signals to settle
        wait for 2 ns;

        -- --------------------------------------------------------
        -- TEST 1: DMEM write
        -- addr=0x00010004 → dmem region. mem_we must assert.
        -- All peripheral we must stay low.
        -- --------------------------------------------------------
        addr  <= x"00010004";
        wdata <= x"DEADBEEF";
        we    <= '1';
        wait for 2 ns;
        check(mem_we   = '1',           "T1: mem_we asserted for dmem write");
        check(mem_addr  = x"00010004",  "T1: mem_addr correct");
        check(mem_wdata = x"DEADBEEF",  "T1: mem_wdata correct");
        check(p0_we = '0' and p1_we = '0' and
              p2_we = '0' and p3_we = '0',  "T1: no peripheral we asserted");

        -- --------------------------------------------------------
        -- TEST 2: DMEM read
        -- we=0, mem_rdata driven → rdata must return mem_rdata.
        -- --------------------------------------------------------
        addr      <= x"00010008";
        we        <= '0';
        mem_rdata <= x"CAFEBABE";
        wait for 2 ns;
        check(rdata  = x"CAFEBABE",  "T2: rdata from mem_rdata on dmem read");
        check(mem_we = '0',          "T2: mem_we low on read");

        -- --------------------------------------------------------
        -- TEST 3: DMEM upper boundary
        -- 0x0001FFFC is still in dmem region (top 16 bits = 0x0001)
        -- --------------------------------------------------------
        addr  <= x"0001FFFC";
        we    <= '1';
        wdata <= x"12345678";
        wait for 2 ns;
        check(mem_we = '1',  "T3: dmem upper boundary still routes to mem");
        check(p0_we = '0' and p1_we = '0' and
              p2_we = '0' and p3_we = '0',  "T3: no peripheral we at dmem boundary");

        -- --------------------------------------------------------
        -- TEST 4: P0 (IRQ controller) write
        -- 0x40000008 → bits[9:8]="00" → P0
        -- p0_addr should be the low 8 bits = 0x08
        -- --------------------------------------------------------
        addr  <= x"40000008";
        wdata <= x"AABBCCDD";
        we    <= '1';
        wait for 2 ns;
        check(p0_we    = '1',       "T4: p0_we asserted for IRQ write");
        check(p0_addr  = x"08",     "T4: p0_addr correct (low 8 bits)");
        check(p0_wdata = x"AABBCCDD", "T4: p0_wdata correct");
        check(mem_we = '0' and p1_we = '0' and
              p2_we = '0' and p3_we = '0',  "T4: only p0_we asserted");

        -- --------------------------------------------------------
        -- TEST 5: P0 (IRQ controller) read
        -- rdata should come from p0_rdata, not zeros
        -- --------------------------------------------------------
        addr     <= x"40000010";
        we       <= '0';
        p0_rdata <= x"00000001";
        wait for 2 ns;
        check(rdata = x"00000001",  "T5: rdata from p0_rdata on IRQ read");
        check(p0_we = '0',          "T5: p0_we low on read");

        -- --------------------------------------------------------
        -- TEST 6: P1 (UART) write
        -- 0x40000100 → bits[9:8]="01" → P1
        -- --------------------------------------------------------
        addr  <= x"40000100";
        wdata <= x"00000055";
        we    <= '1';
        wait for 2 ns;
        check(p1_we   = '1',        "T6: p1_we asserted for UART write");
        check(p1_addr = x"00",      "T6: p1_addr correct");
        check(p0_we = '0' and p2_we = '0' and
              p3_we = '0' and mem_we = '0',  "T6: only p1_we asserted");

        -- --------------------------------------------------------
        -- TEST 7: P2 (Timer) write
        -- 0x40000204 → bits[9:8]="10" → P2
        -- --------------------------------------------------------
        addr  <= x"40000204";
        wdata <= x"000003E8";  -- 1000 decimal (timer reload value)
        we    <= '1';
        wait for 2 ns;
        check(p2_we   = '1',    "T7: p2_we asserted for Timer write");
        check(p2_addr = x"04",  "T7: p2_addr correct");
        check(p0_we = '0' and p1_we = '0' and
              p3_we = '0' and mem_we = '0',  "T7: only p2_we asserted");

        -- --------------------------------------------------------
        -- TEST 8: P3 (GPIO) write
        -- 0x40000304 → bits[9:8]="11" → P3
        -- --------------------------------------------------------
        addr  <= x"40000304";
        wdata <= x"000000FF";  -- all GPIO pins high
        we    <= '1';
        wait for 2 ns;
        check(p3_we   = '1',    "T8: p3_we asserted for GPIO write");
        check(p3_addr = x"04",  "T8: p3_addr correct");
        check(p0_we = '0' and p1_we = '0' and
              p2_we = '0' and mem_we = '0',  "T8: only p3_we asserted");

        -- --------------------------------------------------------
        -- TEST 9: Unmapped address write
        -- 0x20000000 matches neither DMEM nor MMIO regions
        -- No enables should fire
        -- --------------------------------------------------------
        addr  <= x"20000000";
        wdata <= x"FFFFFFFF";
        we    <= '1';
        wait for 2 ns;
        check(mem_we = '0' and p0_we = '0' and
              p1_we  = '0' and p2_we = '0' and
              p3_we  = '0',  "T9: unmapped write fires no enables");

        -- --------------------------------------------------------
        -- TEST 10: Unmapped address read
        -- rdata must return zero, no enables fire
        -- --------------------------------------------------------
        addr <= x"80000000";
        we   <= '0';
        wait for 2 ns;
        check(rdata  = x"00000000",  "T10: unmapped read returns zero");
        check(mem_we = '0' and p0_we = '0' and
              p1_we  = '0' and p2_we = '0' and
              p3_we  = '0',          "T10: unmapped read fires no enables");

        -- --------------------------------------------------------
        report "=== MMIO bus testbench complete ===" severity note;
        wait;
    end process;

end Behavioral;