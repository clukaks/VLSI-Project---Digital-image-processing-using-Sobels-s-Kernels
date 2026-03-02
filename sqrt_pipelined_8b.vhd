library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sqrt_pipelined is
  generic (
    G_IN_BW: natural := 16;
    G_OUT_BW: natural := 16;
    G_OUT_FRAC: natural := 8
  );
  port (
    clk:      in  std_logic;
    reset:    in  std_logic;
    d_in:     in  std_logic_vector(G_IN_BW-1 downto 0);
    valid_in: in  std_logic;
    d_out:     out std_logic_vector(G_OUT_BW-1 downto 0);
    valid_out: out std_logic
  );
end sqrt_pipelined;

architecture Behavioral_sqrt_pipelined of sqrt_pipelined is

  constant C_RAD_W: natural := 2*G_OUT_BW; --sirina radicanda, podatka koji obradjujemo
  constant C_REM_W: natural := C_RAD_W + 2;
  --prosirujemo ostatak, da ne bi doslo do overflowa prilikom siftovanja ulevo
  constant N: natural := G_OUT_BW; --oznacava broj stepeni pajplajna

  type t_rad_arr  is array (0 to N) of unsigned(C_RAD_W-1 downto 0);
  type t_rem_arr  is array (0 to N) of unsigned(C_REM_W-1 downto 0);
  type t_root_arr is array (0 to N) of unsigned(G_OUT_BW-1 downto 0);
  type t_val_arr  is array (0 to N) of std_logic;

  signal rad_pipe       : t_rad_arr;
  signal rem_pipe       : t_rem_arr;
  signal root_pipe      : t_root_arr;
  signal val_pipe       : t_val_arr;
  signal rad_orig_pipe: t_rad_arr;  

begin
  INPUT_PIPELINE_STAGE: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rad_pipe(0) <= (others => '0');
        rem_pipe(0) <= (others => '0');
        root_pipe(0) <= (others => '0');
        rad_orig_pipe(0) <= (others => '0');
        val_pipe(0) <= '0';
      else
        val_pipe(0) <= valid_in;

        if valid_in = '1' then
          rad_pipe(0) <= shift_left(resize(unsigned(d_in), C_RAD_W),2*G_OUT_FRAC);
          rad_orig_pipe(0) <= shift_left(resize(unsigned(d_in), C_RAD_W),2*G_OUT_FRAC);
        end if;

        rem_pipe(0) <= (others => '0');
        root_pipe(0) <= (others => '0');
      end if;
    end if;
  end process INPUT_PIPELINE_STAGE;

--otpetljavanje petlje i formiranje pajplajna
  LOOP_UNROLL : for i in 0 to N-1 generate
    process(clk) is
      variable next2 : unsigned(1 downto 0);
      variable rem_v : unsigned(C_REM_W-1 downto 0);
      variable trial : unsigned(C_REM_W-1 downto 0);
      variable root_v : unsigned(G_OUT_BW-1 downto 0);
    begin
      if rising_edge(clk) then
        if reset = '1' then
          rad_pipe(i+1) <= (others => '0');
          rem_pipe(i+1) <= (others => '0');
          root_pipe(i+1) <= (others => '0');
          rad_orig_pipe(i+1) <= (others => '0');
          val_pipe(i+1) <= '0';
        else
          val_pipe(i+1) <= val_pipe(i);
          rad_orig_pipe(i+1) <= rad_orig_pipe(i);

          next2 := rad_pipe(i)(C_RAD_W-1 downto C_RAD_W-2);
          rad_pipe(i+1) <= rad_pipe(i)(C_RAD_W-3 downto 0) & "00";

          rem_v := shift_left(rem_pipe(i), 2);
          rem_v(1 downto 0) := next2;

          trial := resize(shift_left(root_pipe(i), 2), C_REM_W) + 1;
          root_v := shift_left(root_pipe(i), 1);

          if rem_v >= trial then
            rem_pipe(i+1)  <= rem_v - trial;
            root_pipe(i+1) <= root_v + 1;
          else
            rem_pipe(i+1)  <= rem_v;
            root_pipe(i+1) <= root_v;
          end if;
        end if;
      end if;
    end process;
  end generate LOOP_UNROLL;

  OUTPUT_STAGE: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' then
        d_out <= (others => '0');
        valid_out <= '0';
      else
        valid_out <= val_pipe(N);

        if val_pipe(N) = '1' then
          if (resize(root_pipe(N), C_RAD_W) * resize(root_pipe(N), C_RAD_W)) > rad_orig_pipe(N) then
          --pre ispisa radimo poredjenje, desavalo se da se ispisuje vrednost korena koja se razlikuje za 1
          --uz ovaj uslov se to ne desava
            d_out <= std_logic_vector(root_pipe(N) - 1);
          else
            d_out <= std_logic_vector(root_pipe(N));
          end if;
        end if;
      end if;
    end if;
  end process OUTPUT_STAGE;

end architecture Behavioral_sqrt_pipelined;
