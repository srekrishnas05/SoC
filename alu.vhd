library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- ALU with Kogge-Stone adder and barrel shifter
-- ============================================================
-- alu_ctrl:
--   000 = ADD       001 = SUB
--   010 = AND       011 = OR
--   100 = XOR       101 = MUL (Wallace tree, handled in datapath)
--   110 = SHIFT     111 = reserved
--
-- Shift (alu_ctrl=110): operates on input a
--   shift_type: 00=LSL  01=LSR  10=ASR  11=ROR
--   shift_amt : 5-bit immediate from instr[11:7]
--   C flag    : last bit shifted/rotated out
--
-- Flags: N Z C V
--   N/Z: valid for all ops
--   C/V: ADD/SUB carry/overflow; SHIFT sets C to last bit out
-- ============================================================

entity ALU is
    port (
        a, b       : in  std_logic_vector(31 downto 0);
        alu_ctrl   : in  std_logic_vector(2 downto 0);
        shift_type : in  std_logic_vector(1 downto 0);  -- 00=LSL 01=LSR 10=ASR 11=ROR
        shift_amt  : in  std_logic_vector(4 downto 0);  -- from instr[11:7]
        result     : out std_logic_vector(31 downto 0);
        flags      : out std_logic_vector(3 downto 0)   -- N Z C V
    );
end ALU;

architecture Behavioral of ALU is

    function kogge_stone_add (
        a        : std_logic_vector(31 downto 0);
        b        : std_logic_vector(31 downto 0);
        carry_in : std_logic)
        return std_logic_vector is
        variable G : std_logic_vector(31 downto 0);
        variable P : std_logic_vector(31 downto 0);
        type gp_array is array(0 to 5) of std_logic_vector(31 downto 0);
        variable G_s : gp_array;
        variable P_s : gp_array;
        variable stride : integer;
        variable carry  : std_logic_vector(32 downto 0);
        variable sum    : std_logic_vector(32 downto 0);
    begin
        G := a and b;
        P := a xor b;
        G(0) := G(0) or (P(0) and carry_in);
        G_s(0) := G; P_s(0) := P;
        for stage in 0 to 4 loop
            stride := 2 ** stage;
            G_s(stage+1) := G_s(stage);
            P_s(stage+1) := P_s(stage);
            for i in stride to 31 loop
                G_s(stage+1)(i) := G_s(stage)(i) or
                                   (P_s(stage)(i) and G_s(stage)(i - stride));
                P_s(stage+1)(i) := P_s(stage)(i) and P_s(stage)(i - stride);
            end loop;
        end loop;
        carry(0) := carry_in;
        for i in 0 to 31 loop
            carry(i+1) := G_s(5)(i);
        end loop;
        for i in 0 to 31 loop
            sum(i) := P(i) xor carry(i);
        end loop;
        sum(32) := carry(32);
        return sum;
    end function;

    signal N, Z, C, V : std_logic;

begin
    process(all)
        variable res   : std_logic_vector(31 downto 0);
        variable S     : std_logic_vector(32 downto 0);
        variable B_in  : std_logic_vector(31 downto 0);
        variable amt   : integer range 0 to 31;
        variable c_out : std_logic;
    begin
        res   := (others => '0');
        S     := (others => '0');
        B_in  := b;
        N <= '0';
        Z <= '0';
        C <= '0';
        V <= '0';

        if (alu_ctrl = "000") or (alu_ctrl = "001") then
            if alu_ctrl = "001" then
                B_in := not b;
            end if;
            if alu_ctrl = "001" then
                S := kogge_stone_add(a, B_in, '1');
            else
                S := kogge_stone_add(a, B_in, '0');
            end if;
            res := S(31 downto 0);
            C   <= S(32);
            if alu_ctrl = "000" then
                if (a(31) = b(31)) and (res(31) /= a(31)) then V <= '1'; end if;
            else
                if (a(31) /= b(31)) and (res(31) /= a(31)) then V <= '1'; end if;
            end if;

        elsif alu_ctrl = "010" then
            res := a and b;
        elsif alu_ctrl = "011" then
            res := a or b;
        elsif alu_ctrl = "100" then
            res := a xor b;
        elsif alu_ctrl = "101" then
            -- MUL handled externally by Wallace tree in datapath
            res := (others => '0');

        elsif alu_ctrl = "110" then
            -- Barrel shifter - operates on a, amount from shift_amt
            amt   := to_integer(unsigned(shift_amt));
            c_out := '0';

            case shift_type is
                when "00" =>  -- LSL: logical shift left
                    if amt = 0 then
                        res   := a;
                        c_out := '0';
                    else
                        res   := std_logic_vector(shift_left(unsigned(a), amt));
                        c_out := a(32 - amt);  -- last bit shifted out
                    end if;

                when "01" =>  -- LSR: logical shift right
                    if amt = 0 then
                        -- ARM encodes LSR #0 as LSR #32
                        res   := (others => '0');
                        c_out := a(31);
                    else
                        res   := std_logic_vector(shift_right(unsigned(a), amt));
                        c_out := a(amt - 1);  -- last bit shifted out
                    end if;

                when "10" =>  -- ASR: arithmetic shift right (sign extend)
                    if amt = 0 then
                        -- ARM encodes ASR #0 as ASR #32
                        res   := (others => a(31));
                        c_out := a(31);
                    else
                        res   := std_logic_vector(shift_right(signed(a), amt));
                        c_out := a(amt - 1);  -- last bit shifted out
                    end if;

                when "11" =>  -- ROR: rotate right
                    if amt = 0 then
                        -- ARM encodes ROR #0 as RRX (rotate right through carry)
                        -- RRX: C flag becomes bit 31, a shifts right 1
                        -- C_in not available here - treat as ROR #32 (no-op)
                        res   := a;
                        c_out := a(0);
                    else
                        res   := std_logic_vector(
                                    unsigned(a) ror amt);
                        c_out := a(amt - 1);  -- last bit rotated out
                    end if;

                when others =>
                    res   := a;
                    c_out := '0';
            end case;

            C <= c_out;

        else
            res := (others => '0');
        end if;

        N <= res(31);
        if res = x"00000000" then
            Z <= '1';
        end if;
        result <= res;
        flags  <= N & Z & C & V;
    end process;

end Behavioral;