library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;

entity async_fifo is
    generic (
        DATA_W : natural := 32;
        DEPTH  : natural := 16   -- must be power of 2
    );
    port (
        -- Write port
        wr_clk  : in  std_logic;
        wr_rst  : in  std_logic;
        wr_en   : in  std_logic;
        wr_data : in  std_logic_vector(DATA_W - 1 downto 0);
        full    : out std_logic;

        -- Read port
        rd_clk  : in  std_logic;
        rd_rst  : in  std_logic;
        rd_en   : in  std_logic;
        rd_data : out std_logic_vector(DATA_W - 1 downto 0);
        empty   : out std_logic
    );
end async_fifo;

architecture Behavioral of async_fifo is

    constant ADDR_W : natural := 0;  -- will be overridden by clog2 logic below

    function local_clog2(n : positive) return natural is
        variable v : natural := n - 1;
        variable r : natural := 0;
    begin
        while v > 0 loop v := v / 2; r := r + 1; end loop;
        return r;
    end function;

    constant AW : natural := local_clog2(DEPTH);

    type mem_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_W - 1 downto 0);
    signal mem_r : mem_t := (others => (others => '0'));

    signal wptr_bin_r  : unsigned(AW downto 0) := (others => '0');
    signal wptr_gray_r : std_logic_vector(AW downto 0) := (others => '0');

    signal rptr_bin_r  : unsigned(AW downto 0) := (others => '0');
    signal rptr_gray_r : std_logic_vector(AW downto 0) := (others => '0');

    signal wptr_gray_sync : std_logic_vector(AW downto 0);  -- in rd domain
    signal rptr_gray_sync : std_logic_vector(AW downto 0);  -- in wr domain

    signal full_s  : std_logic;
    signal empty_s : std_logic;

    function to_gray(b : unsigned) return std_logic_vector is
    begin
        return std_logic_vector(b xor ('0' & b(b'high downto 1)));
    end function;

    function from_gray(g : std_logic_vector) return unsigned is
        variable b : unsigned(g'range) := (others => '0');
    begin
        b(g'high) := g(g'high);
        for i in g'high - 1 downto 0 loop
            b(i) := b(i + 1) xor g(i);
        end loop;
        return b;
    end function;

begin

    wptr_sync_gen : for i in 0 to AW generate
        u_wsync : entity work.cdc_sync
            generic map (STAGES => 2)
            port map (
                dst_clk => rd_clk,
                d_in    => wptr_gray_r(i),
                d_out   => wptr_gray_sync(i));
    end generate;

    rptr_sync_gen : for i in 0 to AW generate
        u_rsync : entity work.cdc_sync
            generic map (STAGES => 2)
            port map (
                dst_clk => wr_clk,
                d_in    => rptr_gray_r(i),
                d_out   => rptr_gray_sync(i));
    end generate;

    process(wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_rst = '1' then
                wptr_bin_r  <= (others => '0');
                wptr_gray_r <= (others => '0');
            elsif wr_en = '1' and full_s = '0' then
                mem_r(to_integer(wptr_bin_r(AW - 1 downto 0))) <= wr_data;
                wptr_bin_r  <= wptr_bin_r + 1;
                wptr_gray_r <= to_gray(wptr_bin_r + 1);
            end if;
        end if;
    end process;

    full_s <= '1' when
        (wptr_gray_r(AW)     /= rptr_gray_sync(AW))     and
        (wptr_gray_r(AW - 1) /= rptr_gray_sync(AW - 1)) and
        (wptr_gray_r(AW - 2 downto 0) = rptr_gray_sync(AW - 2 downto 0))
        else '0';

    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_rst = '1' then
                rptr_bin_r  <= (others => '0');
                rptr_gray_r <= (others => '0');
            elsif rd_en = '1' and empty_s = '0' then
                rd_data    <= mem_r(to_integer(rptr_bin_r(AW - 1 downto 0)));
                rptr_bin_r  <= rptr_bin_r + 1;
                rptr_gray_r <= to_gray(rptr_bin_r + 1);
            end if;
        end if;
    end process;

    empty_s <= '1' when rptr_gray_r = wptr_gray_sync else '0';

    full  <= full_s;
    empty <= empty_s;

end Behavioral;