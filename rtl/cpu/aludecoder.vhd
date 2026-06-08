library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity aludecoder is
    port (
        ALUOp  : in  std_logic;
        funct  : in  std_logic_vector(4 downto 0);
        ALUCO  : out std_logic_vector(2 downto 0);
        Flagw  : out std_logic_vector(3 downto 0);  -- N Z C V individual enables
        nowrite : out std_logic
        );
end aludecoder;

-- ============================================================
-- flagw encoding (4 bits - N Z C V):
--   "0000" = no flags updated
--   "1111" = all flags (ADD, SUB, CMP)
--   "1100" = N and Z only (AND, OR, XOR, MUL)
--   "1110" = N, Z, C (SHIFT - C = last bit out, V preserved)
-- ============================================================

architecture Behavioral of aludecoder is
begin
    process(all)
    begin
        ALUCO   <= "000";
        Flagw   <= "0000";
        nowrite <= '0';

        if ALUOp = '0' then
            ALUCO <= "000";
            Flagw <= "0000";

        elsif ALUOp = '1' then
            case funct(4 downto 1) is
                when "0100" =>          -- ADD
                    ALUCO <= "000";
                    if funct(0) = '1' then Flagw <= "1111"; end if;

                when "0010" =>          -- SUB
                    ALUCO <= "001";
                    if funct(0) = '1' then Flagw <= "1111"; end if;

                when "0000" =>          -- AND
                    ALUCO <= "010";
                    if funct(0) = '1' then Flagw <= "1100"; end if;

                when "1100" =>          -- OR
                    ALUCO <= "011";
                    if funct(0) = '1' then Flagw <= "1100"; end if;

                when "1111" =>          -- XOR
                    ALUCO <= "100";
                    if funct(0) = '1' then Flagw <= "1100"; end if;

                when "1010" =>          -- CMP (SUB, nowrite)
                    ALUCO   <= "001";
                    Flagw   <= "1111";
                    nowrite <= '1';

                when "0001" =>          -- MUL
                    ALUCO <= "101";
                    if funct(0) = '1' then Flagw <= "1100"; end if;

                when "1101" =>          -- SHIFT (MOV with shifted register)
                    ALUCO <= "110";
                    if funct(0) = '1' then Flagw <= "1110"; end if;

                when others =>
                    ALUCO <= "000";
                    Flagw <= "0000";
            end case;
        end if;
    end process;
end Behavioral;