library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity grad_mag is
      port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        grad_start : in  std_logic;
    
        --Signal koji govori Control Modulu da je obrada gotova
        grad_done  : out std_logic;
    
        --Port B za citanje
        ram_enb    : out std_logic;
        ram_addrb  : out std_logic_vector(15 downto 0);
        ram_doutb  : in  std_logic_vector(7 downto 0); 
    
        --Port A za upis
        ram_wea    : out std_logic;
        ram_addra  : out std_logic_vector(15 downto 0);
        ram_dina   : out std_logic_vector(7 downto 0);
    
        --Signali za debug i tb
        wr_pulse   : out std_logic;
        wr_data    : out std_logic_vector(7 downto 0)
      );
end entity;

architecture Behavioral_grad_mag of grad_mag is

      constant IMG_W     : integer := 256; 
      constant MAX_PIX   : unsigned(15 downto 0) := x"FFFF"; -- 65535
      
      constant SOBEL_LAT : integer := 2; 
      constant RAM_LAT   : integer := 1;
      constant SQRT_LAT  : integer := 18; 
      --pojedinacne latencije, uvedene zbog valid signala koji propustamo kroz nas modul
      constant TOTAL_LAT : integer := SOBEL_LAT + RAM_LAT + SQRT_LAT;
      
      signal run : std_logic := '0'; 
      -- kada je run na '1' tada nas sistem radi, aktivira se na impuls signala start
      
      signal addr_rd : unsigned(15 downto 0) := (others=>'0');
      signal row, col : unsigned(7 downto 0) := (others=>'0'); 
    
      --brojac za piksele
      signal pix_cnt  : unsigned(15 downto 0) := (others=>'0'); 
    
      -- lnijski baferi, FIFO 
      type line_t is array (0 to IMG_W-1) of std_logic_vector(7 downto 0);
      signal line1, line2 : line_t := (others=>(others=>'0'));
      
      -- Sobelov Kernel 
      signal t0,t1,t2 : unsigned(7 downto 0) := (others=>'0');
      signal m0,m1,m2 : unsigned(7 downto 0) := (others=>'0');
      signal b0,b1,b2 : unsigned(7 downto 0) := (others=>'0');
      
      --gradijenti
      signal gh, gv      : signed(10 downto 0) := (others=>'0');
      signal gh_r, gv_r : signed(10 downto 0) := (others=>'0');
      
      -- registar za upis normalizovane vrednosti
      signal gsq_norm_r : std_logic_vector(15 downto 0) := (others=>'0');
      
      -- valid_pixel nam govori da li je trenutni piksel racunljiv
      signal valid_pixel : std_logic := '0'; 
      -- pajplajn za valid signal
      signal valid_pipe  : std_logic_vector(TOTAL_LAT downto 0) := (others=>'0'); 
      signal run_pipe    : std_logic_vector(TOTAL_LAT downto 0) := (others=>'0');
          
      signal sqrt_out  : std_logic_vector(15 downto 0); 
      signal sqrt_vout : std_logic; 

begin
      ram_enb   <= run;
      ram_addrb <= std_logic_vector(addr_rd);
      
      -- Logika za kontrolu citanja
      RUN_CONTROL: process(clk) is
      begin
        if rising_edge(clk) then
          if reset='1' then
            run <= '0';
          elsif grad_start='1' then
            run <= '1';
          elsif addr_rd = MAX_PIX then 
            run <= '0';
          end if;
        end if;
      end process RUN_CONTROL;
      
      RAM_READ: process(clk)
      begin
        if rising_edge(clk) then
          if reset='1' then
            addr_rd <= (others=>'0');
            row <= (others=>'0');
            col <= (others=>'0');
          elsif run='1' then
            if addr_rd < MAX_PIX then
                addr_rd <= addr_rd + 1;
                if col = 255 then  --prolaz po kolonama
                  col <= (others=>'0');
                  row <= row + 1;
                else
                  col <= col + 1;
                end if;
            end if;
          end if;
        end if;
      end process RAM_READ;
     
      LINE_BUFFERS: process(clk)
      begin
        if rising_edge(clk) then
          if reset='1' or run='0' then
            t0 <= (others=>'0'); t1 <= (others=>'0'); t2 <= (others=>'0');
            m0 <= (others=>'0'); m1 <= (others=>'0'); m2 <= (others=>'0');
            b0 <= (others=>'0'); b1 <= (others=>'0'); b2 <= (others=>'0');
            --vracamo sve na 0
          else
          --kretanje kroz FIFO
            line2(to_integer(col)) <= line1(to_integer(col));
            line1(to_integer(col)) <= ram_doutb;
            
            -- formiranje 3x3 Sobelove matrice
            t2 <= t1; t1 <= t0; t0 <= unsigned(line2(to_integer(col)));
            m2 <= m1; m1 <= m0; m0 <= unsigned(line1(to_integer(col)));
            b2 <= b1; b1 <= b0; b0 <= unsigned(ram_doutb);
          end if;
        end if;
      end process LINE_BUFFERS;
    
      SOBEL: process(run,row,col,t0,t1,t2,m0,m1,m2,b0,b1,b2) is
        variable gh_v, gv_v : signed(10 downto 0);
        begin
            if run='1' and row>=2 and col>=2 then 
                valid_pixel <= '1';
            else
                valid_pixel <= '0';
            end if;
            --proveravamo da li posmatramo piksel koji je na ivici slike, i ako je to slucaj, to je nevalidan piskel
            
            gh_v := resize(signed('0'&b0),11) - resize(signed('0'&b2),11)
                  + shift_left(resize(signed('0'&m0),11) - resize(signed('0'&m2),11),1)
                  + resize(signed('0'&t0),11) - resize(signed('0'&t2),11);
          
            gv_v := resize(signed('0'&t0),11)
                  + shift_left(resize(signed('0'&t1),11),1)
                  + resize(signed('0'&t2),11)- (resize(signed('0'&b0),11)
                  + shift_left(resize(signed('0'&b1),11),1)+ resize(signed('0'&b2),11));
            
            gh <= gh_v;
            gv <= gv_v;
      end process SOBEL;
      
       GH_GV_REG: process(clk)
       begin
            if rising_edge(clk) then
                gh_r <= gh; 
                gv_r <= gv;
            end if;
        end process GH_GV_REG;
    
        NORMALIZATION: process(clk)
            variable gsq_v : unsigned(21 downto 0);
        begin
            if rising_edge(clk) then
                gsq_v := unsigned(abs(gh_r))*unsigned(abs(gh_r)) +
                         unsigned(abs(gv_r))*unsigned(abs(gv_r));
                gsq_norm_r <= std_logic_vector(resize(shift_right(gsq_v,6),16));
            end if;
        end process NORMALIZATION;
    
     --pipeline proces za valid i za run zbog ivicnih piksela koji nisu valdini i kasnjenja kroz modul
     --Mem_write bi da nema pajplajna pao na nulu i upis bi stao, kasnjenja su uticala da imamo pipeline i za run
      DELAY_PROC: process(clk)
      begin
        if rising_edge(clk) then
          if reset='1' then
            valid_pipe <= (others=>'0');
            run_pipe <= (others=>'0');
          else
            valid_pipe(0) <= valid_pixel;
            run_pipe(0) <= run;
            for i in 1 to TOTAL_LAT loop
              valid_pipe(i) <= valid_pipe(i-1);
              run_pipe(i) <= run_pipe(i-1);
            end loop;
          end if;
        end if;
      end process DELAY_PROC;
    
      SQRT: entity work.sqrt_pipelined
        port map (
          clk        => clk,
          reset      => reset,
          d_in       => gsq_norm_r,
          valid_in   => valid_pipe(RAM_LAT+SOBEL_LAT), 
          d_out      => sqrt_out,
          valid_out => sqrt_vout
        );
    
      MEM_WRITE: process(clk) is
        variable tmp : unsigned(8 downto 0);
      begin
        if rising_edge(clk) then
          ram_wea <= '0';
          grad_done <= '0';
          wr_pulse <= '0'; 
    
          if reset='1' then
                pix_cnt <= (others=>'0'); 
          
          elsif run_pipe(TOTAL_LAT)='1' then 
                ram_wea   <= '1';
                wr_pulse  <= '1'; 
            
            ram_addra <= std_logic_vector(pix_cnt);
            
            if valid_pipe(TOTAL_LAT)='1' and sqrt_vout='1' then
                    tmp := resize(unsigned(sqrt_out(15 downto 8)),9);
                    if sqrt_out(7)='1' then tmp := tmp + 1; end if; 
                
                    ram_dina <= std_logic_vector(tmp(7 downto 0));
                    wr_data  <= std_logic_vector(tmp(7 downto 0)); 
            else
                    --za piksele koji nisu valdini upisujem crne u obradjenoj slici da bi i ona bila 256x256
                    ram_dina <= (others=>'0');
                    wr_data  <= (others=>'0'); 
            end if;
            
            pix_cnt  <= pix_cnt + 1;
            
            --kada smo dosli do poslednjeg piksela aktiviramo signal grad_done, koji control_modulu kaze da moze da krene slanje
            if pix_cnt = MAX_PIX then
                grad_done <= '1';
            end if;
          end if;
    
        end if;
      end process MEM_WRITE;

end architecture Behavioral_grad_mag;