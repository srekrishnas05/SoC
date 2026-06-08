library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- Wallace Tree Multiplier
-- ============================================================
-- 3-stage pipeline:
--   Stage 1: Partial product generation (sign-magnitude)
--   Stage 2: CSA tree reduction to 2 rows
--   Stage 3: Final Kogge-Stone CPA, negate if signed negative
--
-- signed_mode=0: unsigned multiply
-- signed_mode=1: signed multiply (sign-magnitude method)
--   - Extract absolute values, multiply unsigned
--   - Negate result in stage 3 if signs of inputs differ
--
-- Lower 32 bits returned (MUL instruction)
-- ============================================================

entity wallace_multiplier is
    port (
        clk         : in  std_logic;
        a           : in  std_logic_vector(31 downto 0);
        b           : in  std_logic_vector(31 downto 0);
        signed_mode : in  std_logic;
        start       : in  std_logic;
        busy        : out std_logic;
        valid       : out std_logic;
        result_lo   : out std_logic_vector(31 downto 0)
    );
end wallace_multiplier;

architecture Behavioral of wallace_multiplier is

    -- --------------------------------------------------------
    -- Kogge-Stone adder (64-bit version for final CPA)
    -- --------------------------------------------------------
    function kogge_stone_64 (
        a        : std_logic_vector(63 downto 0);
        b        : std_logic_vector(63 downto 0);
        carry_in : std_logic)
        return std_logic_vector is

        variable G : std_logic_vector(63 downto 0);
        variable P : std_logic_vector(63 downto 0);
        type gp_array is array(0 to 6) of std_logic_vector(63 downto 0);
        variable G_s : gp_array;
        variable P_s : gp_array;
        variable stride : integer;
        variable carry  : std_logic_vector(64 downto 0);
        variable sum    : std_logic_vector(64 downto 0);
    begin
        G := a and b;
        P := a xor b;
        G(0) := G(0) or (P(0) and carry_in);
        G_s(0) := G;
        P_s(0) := P;
        for stage in 0 to 5 loop
            stride := 2 ** stage;
            G_s(stage+1) := G_s(stage);
            P_s(stage+1) := P_s(stage);
            for i in stride to 63 loop
                G_s(stage+1)(i) := G_s(stage)(i) or
                                   (P_s(stage)(i) and G_s(stage)(i - stride));
                P_s(stage+1)(i) := P_s(stage)(i) and P_s(stage)(i - stride);
            end loop;
        end loop;
        carry(0) := carry_in;
        for i in 0 to 63 loop
            carry(i+1) := G_s(6)(i);
        end loop;
        for i in 0 to 63 loop
            sum(i) := P(i) xor carry(i);
        end loop;
        sum(64) := carry(64);
        return sum;
    end function;

    -- --------------------------------------------------------
    -- Carry Save Adder: reduces 3 rows to 2
    -- --------------------------------------------------------
    procedure csa_64 (
        a      : in  std_logic_vector(63 downto 0);
        b      : in  std_logic_vector(63 downto 0);
        c      : in  std_logic_vector(63 downto 0);
        s      : out std_logic_vector(63 downto 0);
        cout   : out std_logic_vector(63 downto 0)) is
        variable carries : std_logic_vector(63 downto 0);
    begin
        s        := a xor b xor c;
        carries  := (a and b) or (b and c) or (a and c);
        cout     := carries(62 downto 0) & '0';
    end procedure;

    -- --------------------------------------------------------
    -- Pipeline stage registers
    -- --------------------------------------------------------
    type pp_array is array(0 to 31) of std_logic_vector(63 downto 0);
    signal pp_s1         : pp_array;
    signal s1_valid      : std_logic := '0';
    signal s1_result_neg : std_logic := '0';

    signal csa_sum       : std_logic_vector(63 downto 0) := (others => '0');
    signal csa_carry     : std_logic_vector(63 downto 0) := (others => '0');
    signal s2_valid      : std_logic := '0';
    signal s2_result_neg : std_logic := '0';

    signal s3_valid      : std_logic := '0';
    signal s3_result     : std_logic_vector(31 downto 0) := (others => '0');

    signal busy_cnt      : unsigned(1 downto 0) := (others => '0');

begin

    busy      <= '1' when busy_cnt /= "00" else '0';
    valid     <= s3_valid;
    result_lo <= s3_result;

    -- --------------------------------------------------------
    -- STAGE 1: Partial product generation (sign-magnitude)
    -- --------------------------------------------------------
    process(clk)
        variable a_abs   : std_logic_vector(31 downto 0);
        variable b_abs   : std_logic_vector(31 downto 0);
        variable a_ext   : std_logic_vector(63 downto 0);
        variable pp      : pp_array;
        variable res_neg : std_logic;
    begin
        if rising_edge(clk) then
            s1_valid <= start;

            if start = '1' then
                -- Compute absolute values and result sign
                if signed_mode = '1' then
                    res_neg := a(31) xor b(31);
                    if a(31) = '1' then
                        a_abs := std_logic_vector(unsigned(not a) + 1);
                    else
                        a_abs := a;
                    end if;
                    if b(31) = '1' then
                        b_abs := std_logic_vector(unsigned(not b) + 1);
                    else
                        b_abs := b;
                    end if;
                else
                    res_neg := '0';
                    a_abs   := a;
                    b_abs   := b;
                end if;

                s1_result_neg <= res_neg;

                -- Generate partial products: PP[i] = a_abs[i] ? b_abs<<i : 0
                for i in 0 to 31 loop
                    a_ext := (others => '0');
                    if a_abs(i) = '1' then
                        a_ext(i + 31 downto i) := b_abs;
                    end if;
                    pp(i) := a_ext;
                end loop;

                pp_s1 <= pp;
            end if;

            -- Busy counter: high for 2 cycles after start
            if start = '1' then
                busy_cnt <= "10";
            elsif busy_cnt /= "00" then
                busy_cnt <= busy_cnt - 1;
            end if;
        end if;
    end process;

    -- --------------------------------------------------------
    -- STAGE 2: CSA tree reduction to 2 rows
    -- --------------------------------------------------------
    process(clk)
        variable s, c : std_logic_vector(63 downto 0);
        variable r    : pp_array;
        variable n    : integer;
    begin
        if rising_edge(clk) then
            s2_valid      <= s1_valid;
            s2_result_neg <= s1_result_neg;

            if s1_valid = '1' then
                r := pp_s1;
                n := 32;

                while n > 2 loop
                    for grp in 0 to (n/3 - 1) loop
                        csa_64(r(grp*3), r(grp*3+1), r(grp*3+2), s, c);
                        r(grp*2)     := s;
                        r(grp*2 + 1) := c;
                    end loop;
                    case (n mod 3) is
                        when 2 =>
                            r((n/3)*2)     := r((n/3)*3);
                            r((n/3)*2 + 1) := r((n/3)*3 + 1);
                            n := (n/3)*2 + 2;
                        when 1 =>
                            r((n/3)*2) := r((n/3)*3);
                            n := (n/3)*2 + 1;
                        when others =>
                            n := (n/3)*2;
                    end case;
                end loop;

                csa_sum   <= r(0);
                csa_carry <= r(1);
            end if;
        end if;
    end process;

    -- --------------------------------------------------------
    -- STAGE 3: Final CPA + sign correction
    -- --------------------------------------------------------
    process(clk)
        variable final_sum : std_logic_vector(64 downto 0);
        variable lo32      : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            s3_valid <= s2_valid;

            if s2_valid = '1' then
                final_sum := kogge_stone_64(csa_sum, csa_carry, '0');
                lo32      := final_sum(31 downto 0);

                -- Negate lower 32 bits if result should be negative
                -- NOT(x) + 1 = two's complement negation
                if s2_result_neg = '1' then
                    s3_result <= std_logic_vector(unsigned(not lo32) + 1);
                else
                    s3_result <= lo32;
                end if;
            end if;
        end if;
    end process;

end Behavioral;