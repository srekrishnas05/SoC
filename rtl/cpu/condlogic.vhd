library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity condlogic is
    port (
        clk : in std_logic;
        cond : in std_logic_vector(3 downto 0);
        flag : in std_logic_vector(3 downto 0); -- 3=N 2=Z 1=C 0=V
        pcsrcin, regwritein, memwritein, nowrite : in std_logic;
        flagwin : in std_logic_vector(3 downto 0);  -- expanded: N Z C V individual enables
        aluflag : in std_logic_vector(3 downto 0);
        pcsrc, regwrite, memwrite : out std_logic;
        uflags : out std_logic_vector(3 downto 0);
        condex_out : out std_logic
        );
end condlogic;

architecture Behavioral of condlogic is
    signal condexs   : std_logic;
    signal flagw     : std_logic_vector(3 downto 0);
    signal uflags_s  : std_logic_vector(3 downto 0) := (others => '0');
begin
    pcsrc      <= pcsrcin and condexs;
    regwrite   <= regwritein and condexs and not(nowrite);
    memwrite   <= memwritein and condexs;
    uflags     <= uflags_s;
    condex_out <= condexs;

    with cond select condexs <=
        flag(2) when "0000",                                     -- EQ
        not(flag(2)) when "0001",                                -- NE
        flag(1) when "0010",                                     -- CS/HS
        not(flag(1)) when "0011",                                -- CC/LO
        flag(3) when "0100",                                     -- MI
        not(flag(3)) when "0101",                                -- PL
        flag(0) when "0110",                                     -- VS
        not(flag(0)) when "0111",                                -- VC
        ((not flag(2)) and flag(1)) when "1000",                 -- HI
        ((not flag(1)) or flag(2)) when "1001",                  -- LS
        (not(flag(3) xor flag(0))) when "1010",                  -- GE
        (flag(3) xor flag(0)) when "1011",                       -- LT
        ((not flag(2)) and (not(flag(3) xor flag(0)))) when "1100", -- GT
        (flag(2) or (flag(3) xor flag(0))) when "1101",          -- LE
        '1' when "1110",                                         -- AL
        '0' when others;

    flagw <= flagwin;

    process(clk)
    begin
        if rising_edge(clk) then
            if flagw(3) = '1' then uflags_s(3) <= aluflag(3); end if;  -- N
            if flagw(2) = '1' then uflags_s(2) <= aluflag(2); end if;  -- Z
            if flagw(1) = '1' then uflags_s(1) <= aluflag(1); end if;  -- C
            if flagw(0) = '1' then uflags_s(0) <= aluflag(0); end if;  -- V
        end if;
    end process;

end Behavioral;