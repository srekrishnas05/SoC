library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Testbench: ALU Kogge-Stone adder verification
-- ============================================================
-- Tests ADD and SUB thoroughly:
--   1.  ADD: basic positive
--   2.  ADD: zero result (Z flag)
--   3.  ADD: carry out (C flag)
--   4.  ADD: signed overflow positive (V flag)
--   5.  ADD: signed overflow negative (V flag)
--   6.  ADD: max unsigned + 1 (carry, zero result)
--   7.  ADD: N flag (negative result)
--   8.  SUB: basic positive
--   9.  SUB: zero result (a == b)
--   10. SUB: borrow (C flag behavior for SUB)
--   11. SUB: signed overflow (V flag)
--   12. SUB: N flag
--   13. AND/OR/XOR: basic sanity (not the focus but verify not broken)
-- ============================================================

entity tb_alu_ks is
end tb_alu_ks;

architecture Behavioral of tb_alu_ks is

    signal a        : std_logic_vector(31 downto 0) := (others => '0');
    signal b        : std_logic_vector(31 downto 0) := (others => '0');
    signal alu_ctrl : std_logic_vector(2 downto 0)  := (others => '0');
    signal result   : std_logic_vector(31 downto 0);
    signal flags    : std_logic_vector(3 downto 0);  -- N Z C V

    alias flag_N : std_logic is flags(3);
    alias flag_Z : std_logic is flags(2);
    alias flag_C : std_logic is flags(1);
    alias flag_V : std_logic is flags(0);

    component ALU port(
        a, b     : in  std_logic_vector(31 downto 0);
        alu_ctrl : in  std_logic_vector(2 downto 0);
        result   : out std_logic_vector(31 downto 0);
        flags    : out std_logic_vector(3 downto 0));
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
        a        => a,
        b        => b,
        alu_ctrl => alu_ctrl,
        result   => result,
        flags    => flags);

    process
    begin
        wait for 5 ns;  -- combinational - just let signals settle

        -- --------------------------------------------------------
        -- TEST 1: ADD basic
        -- 3 + 5 = 8, no flags
        -- --------------------------------------------------------
        alu_ctrl <= "000";
        a <= x"00000003";
        b <= x"00000005";
        wait for 5 ns;
        check(result  = x"00000008", "T1: ADD 3+5 result");
        check(flag_N  = '0',         "T1: ADD 3+5 N=0");
        check(flag_Z  = '0',         "T1: ADD 3+5 Z=0");
        check(flag_C  = '0',         "T1: ADD 3+5 C=0");
        check(flag_V  = '0',         "T1: ADD 3+5 V=0");

        -- --------------------------------------------------------
        -- TEST 2: ADD zero result
        -- 0 + 0 = 0, Z flag
        -- --------------------------------------------------------
        a <= x"00000000";
        b <= x"00000000";
        wait for 5 ns;
        check(result = x"00000000", "T2: ADD 0+0 result");
        check(flag_Z = '1',         "T2: ADD 0+0 Z=1");
        check(flag_C = '0',         "T2: ADD 0+0 C=0");

        -- --------------------------------------------------------
        -- TEST 3: ADD carry out
        -- 0xFFFFFFFF + 1 = 0x100000000, result=0, C=1, Z=1
        -- --------------------------------------------------------
        a <= x"FFFFFFFF";
        b <= x"00000001";
        wait for 5 ns;
        check(result = x"00000000", "T3: ADD max+1 result wraps to 0");
        check(flag_Z = '1',         "T3: ADD max+1 Z=1");
        check(flag_C = '1',         "T3: ADD max+1 C=1");
        check(flag_V = '0',         "T3: ADD max+1 V=0 (unsigned overflow, not signed)");

        -- --------------------------------------------------------
        -- TEST 4: ADD signed overflow - positive + positive = negative
        -- 0x7FFFFFFF + 1 = 0x80000000 (INT_MAX + 1 wraps to INT_MIN)
        -- --------------------------------------------------------
        a <= x"7FFFFFFF";
        b <= x"00000001";
        wait for 5 ns;
        check(result = x"80000000", "T4: ADD INT_MAX+1 result");
        check(flag_N = '1',         "T4: ADD INT_MAX+1 N=1 (looks negative)");
        check(flag_Z = '0',         "T4: ADD INT_MAX+1 Z=0");
        check(flag_C = '0',         "T4: ADD INT_MAX+1 C=0");
        check(flag_V = '1',         "T4: ADD INT_MAX+1 V=1 (signed overflow)");

        -- --------------------------------------------------------
        -- TEST 5: ADD signed overflow - negative + negative = positive
        -- 0x80000000 + 0x80000000 = 0x100000000, result=0
        -- Both negative, result zero - V=1 (should be negative)
        -- --------------------------------------------------------
        a <= x"80000000";
        b <= x"80000000";
        wait for 5 ns;
        check(result = x"00000000", "T5: ADD neg+neg overflow result");
        check(flag_C = '1',         "T5: ADD neg+neg C=1 (unsigned carry)");
        check(flag_V = '1',         "T5: ADD neg+neg V=1 (signed overflow)");
        check(flag_Z = '1',         "T5: ADD neg+neg Z=1");

        -- --------------------------------------------------------
        -- TEST 6: ADD N flag
        -- 1 + 0x80000000 = 0x80000001 - negative result
        -- --------------------------------------------------------
        a <= x"00000001";
        b <= x"80000000";
        wait for 5 ns;
        check(result = x"80000001", "T6: ADD N flag result");
        check(flag_N = '1',         "T6: ADD N=1");
        check(flag_V = '0',         "T6: ADD V=0 (pos+neg cannot overflow)");

        -- --------------------------------------------------------
        -- TEST 7: SUB basic
        -- 10 - 3 = 7, no flags
        -- ARM SUB: C=1 means no borrow (result >= 0)
        -- --------------------------------------------------------
        alu_ctrl <= "001";
        a <= x"0000000A";
        b <= x"00000003";
        wait for 5 ns;
        check(result = x"00000007", "T7: SUB 10-3 result");
        check(flag_N = '0',         "T7: SUB 10-3 N=0");
        check(flag_Z = '0',         "T7: SUB 10-3 Z=0");
        check(flag_C = '1',         "T7: SUB 10-3 C=1 (no borrow)");
        check(flag_V = '0',         "T7: SUB 10-3 V=0");

        -- --------------------------------------------------------
        -- TEST 8: SUB zero result (a == b)
        -- 5 - 5 = 0, Z=1, C=1 (no borrow)
        -- --------------------------------------------------------
        a <= x"00000005";
        b <= x"00000005";
        wait for 5 ns;
        check(result = x"00000000", "T8: SUB a==b result");
        check(flag_Z = '1',         "T8: SUB a==b Z=1");
        check(flag_C = '1',         "T8: SUB a==b C=1 (no borrow)");
        check(flag_V = '0',         "T8: SUB a==b V=0");

        -- --------------------------------------------------------
        -- TEST 9: SUB borrow (a < b unsigned)
        -- 3 - 5: borrows, C=0 (borrow occurred)
        -- --------------------------------------------------------
        a <= x"00000003";
        b <= x"00000005";
        wait for 5 ns;
        check(result = x"FFFFFFFE", "T9: SUB borrow result (3-5)");
        check(flag_N = '1',         "T9: SUB borrow N=1");
        check(flag_C = '0',         "T9: SUB borrow C=0 (borrow occurred)");

        -- --------------------------------------------------------
        -- TEST 10: SUB signed overflow - positive - negative = negative
        -- 0x7FFFFFFF - 0xFFFFFFFF = 0x7FFFFFFF - (-1) = overflow
        -- --------------------------------------------------------
        a <= x"7FFFFFFF";
        b <= x"FFFFFFFF";
        wait for 5 ns;
        check(result = x"80000000", "T10: SUB signed overflow result");
        check(flag_V = '1',         "T10: SUB signed overflow V=1");
        check(flag_N = '1',         "T10: SUB signed overflow N=1");

        -- --------------------------------------------------------
        -- TEST 11: SUB N flag
        -- 0 - 1 = -1 = 0xFFFFFFFF
        -- --------------------------------------------------------
        a <= x"00000000";
        b <= x"00000001";
        wait for 5 ns;
        check(result = x"FFFFFFFF", "T11: SUB 0-1 result");
        check(flag_N = '1',         "T11: SUB 0-1 N=1");
        check(flag_C = '0',         "T11: SUB 0-1 C=0 (borrow)");

        -- --------------------------------------------------------
        -- TEST 12: AND sanity
        -- --------------------------------------------------------
        alu_ctrl <= "010";
        a <= x"FF00FF00";
        b <= x"0F0F0F0F";
        wait for 5 ns;
        check(result = x"0F000F00", "T12: AND result");
        check(flag_C = '0',         "T12: AND C=0");
        check(flag_V = '0',         "T12: AND V=0");

        -- --------------------------------------------------------
        -- TEST 13: OR sanity
        -- --------------------------------------------------------
        alu_ctrl <= "011";
        a <= x"FF00FF00";
        b <= x"0F0F0F0F";
        wait for 5 ns;
        check(result = x"FF0FFF0F", "T13: OR result");

        -- --------------------------------------------------------
        -- TEST 14: XOR sanity
        -- --------------------------------------------------------
        alu_ctrl <= "100";
        a <= x"FFFFFFFF";
        b <= x"FFFFFFFF";
        wait for 5 ns;
        check(result = x"00000000", "T14: XOR same inputs = 0");
        check(flag_Z = '1',         "T14: XOR Z=1");

        -- --------------------------------------------------------
        -- TEST 15: Kogge-Stone carry chain stress
        -- All-ones propagate: 0xAAAAAAAA + 0x55555555 = 0xFFFFFFFF
        -- No carry out, no overflow
        -- --------------------------------------------------------
        alu_ctrl <= "000";
        a <= x"AAAAAAAA";
        b <= x"55555555";
        wait for 5 ns;
        check(result = x"FFFFFFFF", "T15: KS carry chain 0xAAAA+0x5555");
        check(flag_C = '0',         "T15: KS no carry out");
        check(flag_N = '1',         "T15: KS N=1 (MSB set)");
        check(flag_V = '0',         "T15: KS V=0");

        -- --------------------------------------------------------
        -- TEST 16: Kogge-Stone all carries propagate
        -- 0x55555555 + 0x55555555 = 0xAAAAAAAA
        -- --------------------------------------------------------
        a <= x"55555555";
        b <= x"55555555";
        wait for 5 ns;
        check(result = x"AAAAAAAA", "T16: KS 0x5555+0x5555");
        check(flag_C = '0',         "T16: KS C=0");
        check(flag_N = '1',         "T16: KS N=1");
        check(flag_V = '1',         "T16: KS V=1 (pos+pos=neg overflow)");

        report "=== ALU Kogge-Stone testbench complete ===" severity note;
        wait;
    end process;

end Behavioral;