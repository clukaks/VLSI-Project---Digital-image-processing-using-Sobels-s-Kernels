library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sqrt is
  generic (
    G_IN_BW    : natural := 16;
    G_OUT_BW   : natural := 16;
    G_OUT_FRAC : natural := 8
  );
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    d_in      : in  std_logic_vector(G_IN_BW-1 downto 0);
    valid_in  : in  std_logic;
    d_out     : out std_logic_vector(G_OUT_BW-1 downto 0);
    valid_out : out std_logic
  );
end sqrt;

architecture Behavioral_sqrt_seq of sqrt is

  constant C_RAD_W : natural := 2*G_OUT_BW; 
  constant C_REM_W : natural := C_RAD_W + 2;  

  type t_state is (stIdle, stLoad, stRun, stDone);
  signal state_reg, next_state: t_state := stIdle;

  signal d_in_reg: unsigned(G_IN_BW-1 downto 0) := (others => '0');

  signal radicand: unsigned(C_RAD_W-1 downto 0) := (others => '0');
  signal radicand_orig: unsigned(C_RAD_W-1 downto 0) := (others => '0');
 --cuvamo originalnu vrednost, kako bi je kasnije iskoristili za pravilan ispis rezultata
  signal rem_reg: unsigned(C_REM_W-1 downto 0) := (others => '0'); 
 
  signal root_reg: unsigned(G_OUT_BW-1 downto 0) := (others => '0');
--brojac nasih iteracija
  signal iter_cnt: integer range 0 to G_OUT_BW-1 := 0;
--izlazni registri u koje smestamo obradjeni podatak pre nego sto ga posaljemo na izlaz
  signal d_out_r: std_logic_vector(G_OUT_BW-1 downto 0) := (others => '0');
  signal v_out_r: std_logic := '0';

begin
  d_out <= d_out_r;
  valid_out <= v_out_r;
  
  STATE_TRANSITION: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        state_reg <= stIdle;
      else
        state_reg <= next_state;
      end if;
    end if;
  end process STATE_TRANSITION;

  NEXT_STATE_LOGIC : process(state_reg, valid_in, iter_cnt) is
  begin
    next_state <= state_reg;

    case state_reg is
      when stIdle =>
        if valid_in = '1' then
          next_state <= stLoad;
        end if;

      when stLoad =>
        next_state <= stRun;

      when stRun =>
        if iter_cnt = G_OUT_BW-1 then
          next_state <= stDone;
        end if;

      when stDone =>
        next_state <= stIdle;
    end case;
  end process NEXT_STATE_LOGIC;
--izvrsavanje Sobelovog algoritma
  DATAPATH : process(clk) is
    variable next2: unsigned(1 downto 0);
    variable rem_v: unsigned(C_REM_W-1 downto 0);
    variable trial: unsigned(C_REM_W-1 downto 0);
    variable root_v: unsigned(G_OUT_BW-1 downto 0);
  begin
    if rising_edge(clk) then
      if reset = '1' then
        d_in_reg       <= (others => '0');
        radicand       <= (others => '0');
        radicand_orig  <= (others => '0');
        rem_reg        <= (others => '0');
        root_reg       <= (others => '0');
        iter_cnt       <= 0;
        d_out_r        <= (others => '0');
        v_out_r        <= '0';
      else
        v_out_r <= '0';
        case state_reg is

          when stIdle =>
            if valid_in = '1' then
              d_in_reg <= unsigned(d_in);
            end if;

          when stLoad =>
            radicand_orig <= shift_left(resize(d_in_reg, C_RAD_W), 2*G_OUT_FRAC);
            radicand <= shift_left(resize(d_in_reg, C_RAD_W), 2*G_OUT_FRAC);
            rem_reg <= (others => '0');
            root_reg <= (others => '0');
            iter_cnt <= 0;

          when stRun =>
            next2 := radicand(C_RAD_W-1 downto C_RAD_W-2);
            radicand <= radicand(C_RAD_W-3 downto 0) & "00";

            rem_v := shift_left(rem_reg, 2);
            rem_v(1 downto 0) := next2;

            trial  := resize(shift_left(root_reg, 2), C_REM_W) + 1;
            root_v := shift_left(root_reg, 1);

            if rem_v >= trial then
              rem_reg <= rem_v - trial;
              root_reg <= root_v + 1;
            else
              rem_reg <= rem_v;
              root_reg <= root_v;
            end if;

            iter_cnt <= iter_cnt + 1;

          when stDone =>
            if (resize(root_reg, C_RAD_W) * resize(root_reg, C_RAD_W)) > radicand_orig then
                d_out_r <= std_logic_vector(root_reg - 1);
            else
                d_out_r <= std_logic_vector(root_reg);
            end if;
            v_out_r <= '1';
        end case;
      end if;
    end if;
  end process DATAPATH;

end architecture Behavioral_sqrt_seq;