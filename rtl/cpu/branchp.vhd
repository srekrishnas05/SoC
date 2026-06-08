library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity branch_predictor is
    port (
        clk            : in  std_logic;

        pc_fetch       : in  std_logic_vector(31 downto 0);
        predict_taken  : out std_logic;
        predict_target : out std_logic_vector(31 downto 0);

        update_en      : in  std_logic;  
        update_pc      : in  std_logic_vector(31 downto 0);
        actual_taken   : in  std_logic;
        actual_target  : in  std_logic_vector(31 downto 0);

        mispredict     : out std_logic
    );
end branch_predictor;

architecture Behavioral of branch_predictor is

    constant TABLE_SIZE : integer := 64;

    type counter_t is array(0 to TABLE_SIZE-1) of std_logic_vector(1 downto 0);
    signal counters : counter_t := (others => "01");  -- init weakly not-taken

    type target_t is array(0 to TABLE_SIZE-1) of std_logic_vector(31 downto 0);
    signal btb : target_t := (others => (others => '0'));

    type pred_pipe_t is array(0 to 2) of std_logic;
    signal pred_pipe : pred_pipe_t := (others => '0');

    signal idx_fetch  : integer range 0 to TABLE_SIZE-1;
    signal idx_update : integer range 0 to TABLE_SIZE-1;
    signal pred_was   : std_logic;  

begin

    idx_fetch  <= to_integer(unsigned(pc_fetch(7 downto 2)));
    idx_update <= to_integer(unsigned(update_pc(7 downto 2)));

    predict_taken  <= counters(idx_fetch)(1);
    predict_target <= btb(idx_fetch);

    process(clk)
    begin
        if rising_edge(clk) then
            pred_pipe(0) <= counters(idx_fetch)(1); 
            pred_pipe(1) <= pred_pipe(0);
            pred_pipe(2) <= pred_pipe(1);
        end if;
    end process;

    pred_was <= pred_pipe(2);  

    mispredict <= update_en and (pred_was xor actual_taken);

    process(clk)
        variable cnt : unsigned(1 downto 0);
    begin
        if rising_edge(clk) then
            if update_en = '1' then
                btb(idx_update) <= actual_target;

                cnt := unsigned(counters(idx_update));
                if actual_taken = '1' then
                    if cnt /= "11" then
                        counters(idx_update) <= std_logic_vector(cnt + 1);
                    end if;
                else
                    if cnt /= "00" then
                        counters(idx_update) <= std_logic_vector(cnt - 1);
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;