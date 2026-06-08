library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: ALU barrel shifter
-- ============================================================
-- Tests LSL, LSR, ASR, ROR with:
--   - Basic shifts
--   - C flag (last bit shifted out)
--   - N and Z flags
--   - Boundary: shift by 1 and 31
--   - Special ARM #0 encodings (LSR#0=LSR#32, ASR#0=ASR#32)
--   - ADD/SUB unaffected (shift ports ignored)
-- ============================================================

entity tb_alu_shift is
end tb_alu_shift;

architecture Behavioral of tb_alu_shift is

    signal a          : std_logic_vector(31 downto 0) := (others => '0');
    signal b          : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_ctrl   : std_logic_vector(2 downto 0)  := "110";
    signal shift_type : std_logic_vector(1 downto 0)  := "00";
    signal shift_amt  : std_logic_vector(4 downto 0)  := (others => '0');
    signal result     : std_logic_vector(31 downto 0);
    signal flags      : std_logic_vector(3 downto 0);

    alias flag_N : std_logic is flags(3);
    alias flag_Z : std_logic is flags(2);
    alias flag_C : std_logic is flags(1);
    alias flag_V : std_logic is flags(0);

    component ALU port(
        a, b       : in  std_logic_vector(31 downto 0);
        alu_ctrl   : in  std_logic_vector(2 downto 0);
        shift_type : in  std_logic_vector(1 downto 0);
        shift_amt  : in  std_logic_vector(4 downto 0);
        result     : out std_logic_vector(31 downto 0);
        flags      : out std_logic_vector(3 downto 0));
    end component;

    procedure check(condition : in boolean; name : in string) is
    begin
        if condition then
            report "PASS [" & name & "]" severity note;
        else
            report "FAIL [" & name & "]" severity error;
        end if;
    end procedure;

begin

    dut : ALU port map(
        a          => a,
        b          => b,
        alu_ctrl   => alu_ctrl,
        shift_type => shift_type,
        shift_amt  => shift_amt,
        result     => result,
        flags      => flags);

    process
    begin
        alu_ctrl <= "110";  -- SHIFT for all tests below
        wait for 2 ns;

        -- ========================================================
        -- LSL tests (shift_type = "00")
        -- ========================================================
        shift_type <= "00";

        -- T1: LSL basic - 1 << 4 = 16
        a <= x"00000001"; shift_amt <= "00100"; wait for 2 ns;
        check(result = x"00000010", "T1: LSL 1<<4 = 16");
        check(flag_C = '0',         "T1: LSL C=0 (no bit shifted out)");
        check(flag_N = '0',         "T1: LSL N=0");
        check(flag_Z = '0',         "T1: LSL Z=0");

        -- T2: LSL C flag - bit shifted off the top
        -- 0x80000001 << 1: MSB shifts out → C=1, result=0x00000002
        a <= x"80000001"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"00000002", "T2: LSL C flag result");
        check(flag_C = '1',         "T2: LSL C=1 (MSB shifted out)");

        -- T3: LSL by 1 - 0xFFFFFFFF << 1
        a <= x"FFFFFFFF"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"FFFFFFFE", "T3: LSL 0xFFFFFFFF<<1");
        check(flag_C = '1',         "T3: LSL C=1");
        check(flag_N = '1',         "T3: LSL N=1");

        -- T4: LSL by 31 - 1 << 31 = 0x80000000
        a <= x"00000001"; shift_amt <= "11111"; wait for 2 ns;
        check(result = x"80000000", "T4: LSL 1<<31");
        check(flag_N = '1',         "T4: LSL N=1 (MSB set)");
        check(flag_C = '0',         "T4: LSL C=0");

        -- T5: LSL zero result - 0 << anything = 0
        a <= x"00000000"; shift_amt <= "01010"; wait for 2 ns;
        check(result = x"00000000", "T5: LSL 0<<10 = 0");
        check(flag_Z = '1',         "T5: LSL Z=1");

        -- T6: LSL N flag - result has MSB set
        a <= x"00000001"; shift_amt <= "11111"; wait for 2 ns;
        check(flag_N = '1',         "T6: LSL N=1 when bit 31 set");

        -- ========================================================
        -- LSR tests (shift_type = "01")
        -- ========================================================
        shift_type <= "01";

        -- T7: LSR basic - 0x10 >> 4 = 1
        a <= x"00000010"; shift_amt <= "00100"; wait for 2 ns;
        check(result = x"00000001", "T7: LSR 0x10>>4 = 1");
        check(flag_C = '0',         "T7: LSR C=0");
        check(flag_N = '0',         "T7: LSR N=0 (zero fills MSB)");

        -- T8: LSR C flag - last bit shifted out
        -- 0x00000003 >> 1: bit 0 is last out → C=1, result=1
        a <= x"00000003"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"00000001", "T8: LSR 3>>1 = 1");
        check(flag_C = '1',         "T8: LSR C=1 (bit 0 shifted out)");

        -- T9: LSR no sign extension
        -- 0x80000000 >> 1 = 0x40000000 (not 0xC0000000)
        a <= x"80000000"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"40000000", "T9: LSR no sign extend");
        check(flag_N = '0',         "T9: LSR N=0 (zero fill from MSB)");

        -- T10: LSR by 31 - 0xFFFFFFFF >> 31 = 1
        a <= x"FFFFFFFF"; shift_amt <= "11111"; wait for 2 ns;
        check(result = x"00000001", "T10: LSR 0xFFFFFFFF>>31 = 1");
        check(flag_C = '1',         "T10: LSR C=1 (bit 30 was 1)");

        -- T11: LSR #0 special - ARM encodes as LSR #32
        -- result = 0, C = a[31]
        a <= x"80000000"; shift_amt <= "00000"; wait for 2 ns;
        check(result = x"00000000", "T11: LSR #0 = LSR #32 result=0");
        check(flag_C = '1',         "T11: LSR #0 C=a[31]=1");
        check(flag_Z = '1',         "T11: LSR #0 Z=1");

        -- ========================================================
        -- ASR tests (shift_type = "10")
        -- ========================================================
        shift_type <= "10";

        -- T12: ASR positive - 0x00000010 >> 4 = 1 (same as LSR)
        a <= x"00000010"; shift_amt <= "00100"; wait for 2 ns;
        check(result = x"00000001", "T12: ASR positive 0x10>>4 = 1");
        check(flag_N = '0',         "T12: ASR positive N=0");

        -- T13: ASR negative - sign extends
        -- 0x80000000 >> 1 = 0xC0000000
        a <= x"80000000"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"C0000000", "T13: ASR negative sign extends");
        check(flag_N = '1',         "T13: ASR N=1");

        -- T14: ASR negative large shift
        -- 0x80000000 >> 4 = 0xF8000000
        a <= x"80000000"; shift_amt <= "00100"; wait for 2 ns;
        check(result = x"F8000000", "T14: ASR 0x80000000>>4 = 0xF8000000");
        check(flag_N = '1',         "T14: ASR N=1");

        -- T15: ASR C flag
        -- 0xFFFFFFF3 >> 2: bits [1:0]="11", last bit out = bit 1 = 1
        a <= x"FFFFFFF3"; shift_amt <= "00010"; wait for 2 ns;
        check(flag_C = '1',         "T15: ASR C=1 (bit 1 was 1)");

        -- T16: ASR #0 special - ARM encodes as ASR #32
        -- Negative: all sign bits, C = a[31]
        a <= x"80000000"; shift_amt <= "00000"; wait for 2 ns;
        check(result = x"FFFFFFFF", "T16: ASR #0 = ASR #32 all sign bits");
        check(flag_C = '1',         "T16: ASR #0 C=a[31]=1");
        check(flag_N = '1',         "T16: ASR #0 N=1");

        -- T17: ASR #0 positive - C=0, result=0
        a <= x"7FFFFFFF"; shift_amt <= "00000"; wait for 2 ns;
        check(result = x"00000000", "T17: ASR #0 positive = 0");
        check(flag_C = '0',         "T17: ASR #0 positive C=a[31]=0");
        check(flag_Z = '1',         "T17: ASR #0 positive Z=1");

        -- ========================================================
        -- ROR tests (shift_type = "11")
        -- ========================================================
        shift_type <= "11";

        -- T18: ROR basic
        -- 0x00000001 ROR 1: bit 0 rotates to bit 31 = 0x80000000
        a <= x"00000001"; shift_amt <= "00001"; wait for 2 ns;
        check(result = x"80000000", "T18: ROR 1 ror 1 = 0x80000000");
        check(flag_C = '1',         "T18: ROR C=1 (bit 0 rotated out)");
        check(flag_N = '1',         "T18: ROR N=1");

        -- T19: ROR by 4
        -- 0x12345678 ROR 4 = 0x81234567
        a <= x"12345678"; shift_amt <= "00100"; wait for 2 ns;
        check(result = x"81234567", "T19: ROR 0x12345678 ror 4");
        check(flag_N = '1',         "T19: ROR N=1");

        -- T20: ROR C flag - last bit rotated out
        -- 0x00000006 ROR 2: bits[1:0]="10", last out = bit 1 = 1
        a <= x"00000006"; shift_amt <= "00010"; wait for 2 ns;
        check(result = x"80000001", "T20: ROR 0x6 ror 2 = 0x80000001");
        check(flag_C = '1',         "T20: ROR C=1 (bit 1 was 1)");

        -- T21: ROR by 32 is identity - check result unchanged
        a <= x"DEADBEEF"; shift_amt <= "11111"; wait for 2 ns;
        -- ROR by 31: 0xDEADBEEF ror 31
        -- = (0xDEADBEEF >> 31) | (0xDEADBEEF << 1)
        -- = 0x00000001 | 0xBD57DDDE = 0xBD57DDDF
        check(result = x"BD5B7DDF", "T21: ROR 0xDEADBEEF ror 31");

        -- ========================================================
        -- Verify ADD still works with shift ports present
        -- ========================================================
        alu_ctrl   <= "000";
        shift_type <= "11";   -- should be ignored for ADD
        shift_amt  <= "11111"; -- should be ignored for ADD
        a <= x"00000005"; b <= x"00000003"; wait for 2 ns;
        check(result = x"00000008", "T22: ADD unaffected by shift ports");
        check(flag_C = '0',         "T22: ADD C correct");

        report "=== ALU shifter testbench complete ===" severity note;
        wait;
    end process;

end Behavioral;