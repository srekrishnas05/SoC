library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: wallace_multiplier
-- ============================================================
-- Tests:
--  Unsigned:
--   1.  Basic: 3 x 5 = 15
--   2.  Identity: N x 1 = N
--   3.  Zero: N x 0 = 0
--   4.  Power of 2: 7 x 8 = 56
--   5.  Large: 0xFFFF x 0xFFFF = 0xFFFE0001 (lower 32)
--   6.  Max x 2: 0xFFFFFFFF x 2 = 0xFFFFFFFE (lower 32)
--
--  Signed:
--   7.  Pos x Neg: 3 x (-1) = -3
--   8.  Neg x Neg: (-4) x (-4) = 16
--   9.  Neg x Pos: (-3) x 5 = -15
--   10. Min x (-1): INT_MIN x (-1) = INT_MIN (overflow wraps)
--
--  Timing:
--   11. valid asserts exactly 3 cycles after start
--   12. busy high for exactly 2 cycles after start
--   13. back-to-back: second MUL starts cycle after first completes
-- ============================================================

entity tb_wallace_mul is
end tb_wallace_mul;

architecture Behavioral of tb_wallace_mul is

    signal clk         : std_logic := '0';
    signal a           : std_logic_vector(31 downto 0) := (others => '0');
    signal b           : std_logic_vector(31 downto 0) := (others => '0');
    signal signed_mode : std_logic := '0';
    signal start       : std_logic := '0';
    signal busy        : std_logic;
    signal valid       : std_logic;
    signal result_lo   : std_logic_vector(31 downto 0);

    -- Cycle counter for timing checks
    signal cycle_count : integer := 0;

    component wallace_multiplier port(
        clk         : in  std_logic;
        a           : in  std_logic_vector(31 downto 0);
        b           : in  std_logic_vector(31 downto 0);
        signed_mode : in  std_logic;
        start       : in  std_logic;
        busy        : out std_logic;
        valid       : out std_logic;
        result_lo   : out std_logic_vector(31 downto 0));
    end component;

    procedure check(condition : in boolean; name : in string) is
    begin
        if condition then
            report "PASS [" & name & "]" severity note;
        else
            report "FAIL [" & name & "]" severity error;
        end if;
    end procedure;

    -- Issue one multiply and wait for valid
    -- Returns when valid has pulsed and result is stable
    procedure do_mul(
        signal clk         : in  std_logic;
        signal a_sig       : out std_logic_vector(31 downto 0);
        signal b_sig       : out std_logic_vector(31 downto 0);
        signal smode       : out std_logic;
        signal start_sig   : out std_logic;
        signal valid_sig   : in  std_logic;
        a_val   : in std_logic_vector(31 downto 0);
        b_val   : in std_logic_vector(31 downto 0);
        smode_v : in std_logic) is
    begin
        -- Set operands and assert start for one cycle
        a_sig     <= a_val;
        b_sig     <= b_val;
        smode     <= smode_v;
        start_sig <= '1';
        wait until rising_edge(clk);
        start_sig <= '0';
        -- Wait for valid (3 cycles from start)
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        -- Result now stable on result_lo
        wait for 1 ns;
    end procedure;

begin

    clk <= not clk after 5 ns;

    -- Cycle counter
    process(clk)
    begin
        if rising_edge(clk) then
            cycle_count <= cycle_count + 1;
        end if;
    end process;

    dut : wallace_multiplier port map(
        clk         => clk,
        a           => a,
        b           => b,
        signed_mode => signed_mode,
        start       => start,
        busy        => busy,
        valid       => valid,
        result_lo   => result_lo);

    process
        variable t_start : integer;
    begin
        -- Let reset settle
        wait until rising_edge(clk);
        wait for 1 ns;

        -- --------------------------------------------------------
        -- TEST 1: Unsigned basic - 3 x 5 = 15
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"00000003", x"00000005", '0');
        check(result_lo = x"0000000F", "T1: unsigned 3x5=15");

        -- --------------------------------------------------------
        -- TEST 2: Unsigned identity - 7 x 1 = 7
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"00000007", x"00000001", '0');
        check(result_lo = x"00000007", "T2: unsigned 7x1=7");

        -- --------------------------------------------------------
        -- TEST 3: Unsigned zero - 0xDEADBEEF x 0 = 0
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"DEADBEEF", x"00000000", '0');
        check(result_lo = x"00000000", "T3: unsigned Nx0=0");

        -- --------------------------------------------------------
        -- TEST 4: Unsigned power of 2 - 7 x 8 = 56
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"00000007", x"00000008", '0');
        check(result_lo = x"00000038", "T4: unsigned 7x8=56");

        -- --------------------------------------------------------
        -- TEST 5: Unsigned large - 0xFFFF x 0xFFFF
        -- = 65535 x 65535 = 4294836225 = 0xFFFE0001
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"0000FFFF", x"0000FFFF", '0');
        check(result_lo = x"FFFE0001", "T5: unsigned 0xFFFFx0xFFFF lower32");

        -- --------------------------------------------------------
        -- TEST 6: Unsigned truncation - 0xFFFFFFFF x 2
        -- Full result = 0x1FFFFFFFE, lower 32 = 0xFFFFFFFE
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"FFFFFFFF", x"00000002", '0');
        check(result_lo = x"FFFFFFFE", "T6: unsigned max x 2 truncated");

        -- --------------------------------------------------------
        -- TEST 7: Signed pos x neg - 3 x (-1) = -3
        -- -1 = 0xFFFFFFFF, -3 = 0xFFFFFFFD
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"00000003", x"FFFFFFFF", '1');
        check(result_lo = x"FFFFFFFD", "T7: signed 3x(-1)=-3");

        -- --------------------------------------------------------
        -- TEST 8: Signed neg x neg - (-4) x (-4) = 16
        -- -4 = 0xFFFFFFFC
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"FFFFFFFC", x"FFFFFFFC", '1');
        check(result_lo = x"00000010", "T8: signed (-4)x(-4)=16");

        -- --------------------------------------------------------
        -- TEST 9: Signed neg x pos - (-3) x 5 = -15
        -- -3 = 0xFFFFFFFD, -15 = 0xFFFFFFF1
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"FFFFFFFD", x"00000005", '1');
        check(result_lo = x"FFFFFFF1", "T9: signed (-3)x5=-15");

        -- --------------------------------------------------------
        -- TEST 10: Signed INT_MIN x (-1) - overflow wraps
        -- INT_MIN = 0x80000000 = -2147483648
        -- -INT_MIN overflows back to INT_MIN in 32-bit
        -- Lower 32 of result = 0x80000000
        -- --------------------------------------------------------
        do_mul(clk, a, b, signed_mode, start, valid,
               x"80000000", x"FFFFFFFF", '1');
        check(result_lo = x"80000000", "T10: signed INT_MIN x (-1) wraps");

        -- --------------------------------------------------------
        -- TEST 11: Timing - busy high exactly 2 cycles after start
        -- Issue MUL, check busy goes low after 2 rising edges
        -- --------------------------------------------------------
        a           <= x"00000004";
        b           <= x"00000004";
        signed_mode <= '0';
        start       <= '1';
        wait until rising_edge(clk);
        start <= '0';
        -- Cycle 1 after start: busy should be high
        wait for 1 ns;
        check(busy = '1', "T11a: busy high cycle 1 after start");
        wait until rising_edge(clk);
        -- Cycle 2 after start: busy still high
        wait for 1 ns;
        check(busy = '1', "T11b: busy high cycle 2 after start");
        wait until rising_edge(clk);
        -- Cycle 3 after start: busy should drop, valid should pulse
        wait for 1 ns;
        check(busy  = '0',         "T11c: busy low cycle 3 (result ready)");
        check(valid = '1',         "T11d: valid high cycle 3");
        check(result_lo = x"00000010", "T11e: 4x4=16 timing test result");

        -- --------------------------------------------------------
        -- TEST 12: Back-to-back - second MUL starts after first valid
        -- --------------------------------------------------------
        -- First: 6 x 7 = 42
        do_mul(clk, a, b, signed_mode, start, valid,
               x"00000006", x"00000007", '0');
        check(result_lo = x"0000002A", "T12a: back-to-back first 6x7=42");

        -- Second immediately after: 10 x 10 = 100
        do_mul(clk, a, b, signed_mode, start, valid,
               x"0000000A", x"0000000A", '0');
        check(result_lo = x"00000064", "T12b: back-to-back second 10x10=100");

        report "=== Wallace multiplier testbench complete ===" severity note;
        wait;
    end process;

end Behavioral;