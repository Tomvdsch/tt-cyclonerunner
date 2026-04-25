module tt_um_tomvdsch_cyclonerunner (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire core_rst_n = rst_n & ena;

    wire gamepad_is_present;
    wire gamepad_b;
    wire gamepad_y;
    wire gamepad_select;
    wire gamepad_start;
    wire gamepad_up;
    wire gamepad_down;
    wire gamepad_left;
    wire gamepad_right;
    wire gamepad_a;
    wire gamepad_x;
    wire gamepad_l;
    wire gamepad_r;

    gamepad_pmod_single gamepad (
        .rst_n      (core_rst_n),
        .clk        (clk),
        .pmod_data  (ui_in[6]),
        .pmod_clk   (ui_in[5]),
        .pmod_latch (ui_in[4]),

        .is_present (gamepad_is_present),
        .b          (gamepad_b),
        .y          (gamepad_y),
        .select     (gamepad_select),
        .start      (gamepad_start),
        .up         (gamepad_up),
        .down       (gamepad_down),
        .left       (gamepad_left),
        .right      (gamepad_right),
        .a          (gamepad_a),
        .x          (gamepad_x),
        .l          (gamepad_l),
        .r          (gamepad_r)
    );

    wire jump_btn  = gamepad_a | gamepad_b | gamepad_up;
    wire duck_btn  = gamepad_down | gamepad_y;
    wire start_btn = gamepad_start | gamepad_select;

    wire [9:0] pix_x;
    wire [9:0] pix_y;
    wire       visible;
    wire       hsync;
    wire       vsync;
    wire       frame_tick;

    wire [6:0] player_y;
    wire       ducking;
    wire       game_over;

    wire [8:0] obs0_x;
    wire [8:0] obs1_x;
    wire [1:0] obs0_type;
    wire [1:0] obs1_type;

    wire [7:0] cloud_x;
    wire [6:0] cloud_y;

    wire [5:0] rgb;
    wire       audio_pwm;

    vga_timing u_vga_timing (
        .clk        (clk),
        .rst_n      (core_rst_n),
        .pix_x      (pix_x),
        .pix_y      (pix_y),
        .visible    (visible),
        .hsync      (hsync),
        .vsync      (vsync),
        .frame_tick (frame_tick)
    );

    game_state u_game_state (
        .clk        (clk),
        .rst_n      (core_rst_n),
        .frame_tick (frame_tick),
        .jump_btn   (jump_btn),
        .duck_btn   (duck_btn),
        .start_btn  (start_btn),

        .player_y   (player_y),
        .ducking    (ducking),
        .game_over  (game_over),

        .obs0_x     (obs0_x),
        .obs1_x     (obs1_x),
        .obs0_type  (obs0_type),
        .obs1_type  (obs1_type),

        .cloud_x    (cloud_x),
        .cloud_y    (cloud_y)
    );

    renderer u_renderer (
        .clk       (clk),
        .rst_n     (core_rst_n),
        .pix_x     (pix_x),
        .pix_y     (pix_y),
        .visible   (visible),

        .game_over (game_over),

        .player_y  (player_y),
        .ducking   (ducking),

        .obs0_x    (obs0_x),
        .obs1_x    (obs1_x),
        .obs0_type (obs0_type),
        .obs1_type (obs1_type),

        .cloud_x   (cloud_x),
        .cloud_y   (cloud_y),

        .rgb       (rgb)
    );

    audio_engine u_audio_engine (
        .clk        (clk),
        .rst_n      (core_rst_n),
        .frame_tick (frame_tick),
        .game_over  (game_over),
        .audio_pwm  (audio_pwm)
    );

    assign uo_out[0] = rgb[5];
    assign uo_out[1] = rgb[3];
    assign uo_out[2] = rgb[1];
    assign uo_out[3] = vsync;
    assign uo_out[4] = rgb[4];
    assign uo_out[5] = rgb[2];
    assign uo_out[6] = rgb[0];
    assign uo_out[7] = hsync;
    assign uio_out = {audio_pwm, 7'b0000000};
    assign uio_oe  = 8'b10000000;

    wire unused = &{
        uio_in,
        ui_in[3:0],
        ui_in[7],
        gamepad_is_present,
        gamepad_left,
        gamepad_right,
        gamepad_x,
        gamepad_l,
        gamepad_r,
        1'b0
    };

endmodule


module gamepad_pmod_single (
    input  wire rst_n,
    input  wire clk,
    input  wire pmod_data,
    input  wire pmod_clk,
    input  wire pmod_latch,

    output wire is_present,
    output wire b,
    output wire y,
    output wire select,
    output wire start,
    output wire up,
    output wire down,
    output wire left,
    output wire right,
    output wire a,
    output wire x,
    output wire l,
    output wire r
);

    reg [1:0] data_sync;
    reg [1:0] clk_sync;
    reg [1:0] latch_sync;

    reg clk_last;
    reg latch_last;

    reg [11:0] shift_reg;
    reg [11:0] buttons;

    wire clk_rise   = clk_sync[1] & ~clk_last;
    wire latch_rise = latch_sync[1] & ~latch_last;
    wire empty      = buttons == 12'hfff;

    always @(posedge clk) begin
        if (!rst_n) begin
            data_sync  <= 2'b00;
            clk_sync   <= 2'b00;
            latch_sync <= 2'b00;
        end else begin
            data_sync  <= {data_sync[0], pmod_data};
            clk_sync   <= {clk_sync[0], pmod_clk};
            latch_sync <= {latch_sync[0], pmod_latch};
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            clk_last   <= 1'b0;
            latch_last <= 1'b0;
            shift_reg  <= 12'hfff;
            buttons    <= 12'hfff;
        end else begin
            clk_last   <= clk_sync[1];
            latch_last <= latch_sync[1];

            if (clk_rise)
                shift_reg <= {shift_reg[10:0], data_sync[1]};

            if (latch_rise)
                buttons <= shift_reg;
        end
    end

    assign is_present = !empty;

    assign {b, y, select, start, up, down, left, right, a, x, l, r} =
        empty ? 12'b000000000000 : buttons;

endmodule


module vga_timing (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [9:0] pix_x,
    output reg  [9:0] pix_y,
    output wire       visible,
    output wire       hsync,
    output wire       vsync,
    output wire       frame_tick
);

    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = 10'd800;

    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = 10'd525;

    assign visible = (pix_x < H_VISIBLE) && (pix_y < V_VISIBLE);

    assign hsync = ~((pix_x >= H_VISIBLE + H_FRONT) &&
                     (pix_x <  H_VISIBLE + H_FRONT + H_SYNC));

    assign vsync = ~((pix_y >= V_VISIBLE + V_FRONT) &&
                     (pix_y <  V_VISIBLE + V_FRONT + V_SYNC));

    assign frame_tick = (pix_x == H_TOTAL - 10'd1) &&
                        (pix_y == V_TOTAL - 10'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_x <= 10'd0;
            pix_y <= 10'd0;
        end else if (pix_x == H_TOTAL - 10'd1) begin
            pix_x <= 10'd0;

            if (pix_y == V_TOTAL - 10'd1)
                pix_y <= 10'd0;
            else
                pix_y <= pix_y + 10'd1;
        end else begin
            pix_x <= pix_x + 10'd1;
        end
    end

endmodule


module game_state (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,
    input  wire       jump_btn,
    input  wire       duck_btn,
    input  wire       start_btn,

    output reg  [6:0] player_y,
    output wire       ducking,
    output wire       game_over,

    output reg  [8:0] obs0_x,
    output reg  [8:0] obs1_x,
    output reg  [1:0] obs0_type, //0 = small rock, 1 = big rock, 2 = bird
    output reg  [1:0] obs1_type,

    output reg  [7:0] cloud_x,
    output reg  [6:0] cloud_y
);

    localparam [1:0] S_WAIT      = 2'd0;
    localparam [1:0] S_RUN       = 2'd1;
    localparam [1:0] S_GAME_OVER = 2'd2;

    localparam [6:0] GROUND_Y   = 7'd84;
    localparam [6:0] JUMP_BOOST = 7'd6;

    localparam signed [7:0] JUMP_VY = -8'sd5;

    localparam [8:0] OBS0_START = 9'd180;
    localparam [8:0] OBS1_START = 9'd255;
    localparam [8:0] SPAWN_X    = 9'd180;
    localparam [8:0] MIN_GAP    = 9'd35;
    localparam [8:0] SPEED_X    = 9'd2;
    localparam [8:0] DESPAWN_X  = 9'd2;

    reg [1:0] state;

    reg signed [7:0] player_vy;
    reg [7:0] lfsr;

    reg jump_prev;
    reg start_prev;

    reg grav_tick;
    reg [1:0] cloud_tick;

    wire jump_edge  = jump_btn && !jump_prev;
    wire start_edge = start_btn && !start_prev;

    assign game_over = state == S_GAME_OVER;
    assign ducking = (state == S_RUN) && duck_btn && (player_y == GROUND_Y);

    function [1:0] rand_type;
        input [1:0] bits;
        begin
            case (bits)
                2'b01: rand_type = 2'd1;
                2'b10: rand_type = 2'd2;
                default: rand_type = 2'd0;
            endcase
        end
    endfunction

    function [8:0] spawn_after;
        input [8:0] other_x;
        input [4:0] rnd;

        reg [8:0] candidate;
        reg [8:0] gap;

        begin
            gap = MIN_GAP + {3'd0, rnd, 1'b0};
            candidate = other_x + gap;

            if (candidate < SPAWN_X)
                spawn_after = SPAWN_X + {3'd0, rnd, 1'b0};
            else
                spawn_after = candidate;
        end
    endfunction

    task reset_run;
        begin
            player_y  <= GROUND_Y;
            player_vy <= 8'sd0;

            obs0_x    <= OBS0_START;
            obs1_x    <= OBS1_START;
            obs0_type <= rand_type(lfsr[1:0]);
            obs1_type <= rand_type(lfsr[5:4]);

            cloud_x   <= 8'd140;
            cloud_y   <= 7'd16;
        end
    endtask

    wire [8:0] player_left  = 9'd20;
    wire [8:0] player_right = 9'd28;

    wire [6:0] player_top    = ducking ? player_y + 7'd8 : player_y;
    wire [6:0] player_bottom = player_y + 7'd16;

    wire [8:0] obs0_width = (obs0_type == 2'd2) ? 9'd10 :
                            (obs0_type == 2'd1) ? 9'd8  :
                                                   9'd6;

    wire [8:0] obs1_width = (obs1_type == 2'd2) ? 9'd10 :
                            (obs1_type == 2'd1) ? 9'd8  :
                                                   9'd6;

    wire [6:0] obs0_top = (obs0_type == 2'd1) ? 7'd80 :
                          (obs0_type == 2'd2) ? 7'd90 :
                                                 7'd93;

    wire [6:0] obs1_top = (obs1_type == 2'd1) ? 7'd80 :
                          (obs1_type == 2'd2) ? 7'd90 :
                                                 7'd93;

    wire [6:0] obs0_bottom = (obs0_type == 2'd1) ? 7'd86 : 7'd100;
    wire [6:0] obs1_bottom = (obs1_type == 2'd1) ? 7'd86 : 7'd100;

    wire [8:0] obs0_right = obs0_x + obs0_width;
    wire [8:0] obs1_right = obs1_x + obs1_width;

    wire hit_obs0 =
        (player_left   < obs0_right) &&
        (player_right  > obs0_x) &&
        (player_top    < obs0_bottom) &&
        (player_bottom > obs0_top);

    wire hit_obs1 =
        (player_left   < obs1_right) &&
        (player_right  > obs1_x) &&
        (player_top    < obs1_bottom) &&
        (player_bottom > obs1_top);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_WAIT;

            player_y   <= GROUND_Y;
            player_vy  <= 8'sd0;

            obs0_x     <= OBS0_START;
            obs1_x     <= OBS1_START;
            obs0_type  <= 2'd0;
            obs1_type  <= 2'd1;

            cloud_x    <= 8'd140;
            cloud_y    <= 7'd16;

            lfsr       <= 8'hA5;

            jump_prev  <= 1'b0;
            start_prev <= 1'b0;

            grav_tick  <= 1'b0;
            cloud_tick <= 2'd0;
        end else if (frame_tick) begin
            jump_prev  <= jump_btn;
            start_prev <= start_btn;

            grav_tick  <= ~grav_tick;
            cloud_tick <= cloud_tick + 2'd1;

            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

            case (state)
                S_WAIT: begin
                    if (start_edge) begin
                        state <= S_RUN;
                        reset_run;
                    end
                end

                S_GAME_OVER: begin
                    if (start_edge) begin
                        state <= S_RUN;
                        reset_run;
                    end
                end

                default: begin
                    if (start_edge) begin
                        state <= S_RUN;
                        reset_run;
                    end else if (hit_obs0 || hit_obs1) begin
                        state     <= S_GAME_OVER;
                        player_vy <= 8'sd0;
                    end else begin
                        if (cloud_tick == 2'd0) begin
                            if (cloud_x == 8'd0) begin
                                cloud_x <= 8'd190 + {4'b0000, lfsr[3:0]};
                                cloud_y <= 7'd8 + {lfsr[6:4], 2'b00};
                            end else begin
                                cloud_x <= cloud_x - 8'd1;
                            end
                        end

                        if ((obs0_x <= DESPAWN_X) && (obs1_x <= DESPAWN_X)) begin
                            obs0_x    <= OBS0_START + {5'd0, lfsr[3:0]};
                            obs1_x    <= OBS1_START + {5'd0, lfsr[7:4]};
                            obs0_type <= rand_type(lfsr[1:0]);
                            obs1_type <= rand_type(lfsr[5:4]);
                        end else begin
                            if (obs0_x <= DESPAWN_X) begin
                                obs0_x    <= spawn_after(obs1_x, lfsr[4:0]);
                                obs0_type <= rand_type(lfsr[1:0]);
                            end else begin
                                obs0_x <= obs0_x - SPEED_X;
                            end

                            if (obs1_x <= DESPAWN_X) begin
                                obs1_x    <= spawn_after(obs0_x, lfsr[7:3]);
                                obs1_type <= rand_type(lfsr[5:4]);
                            end else begin
                                obs1_x <= obs1_x - SPEED_X;
                            end
                        end

                        if (jump_edge && (player_y == GROUND_Y)) begin
                            player_y  <= GROUND_Y - JUMP_BOOST;
                            player_vy <= JUMP_VY;
                        end else if ((player_y != GROUND_Y) || (player_vy != 8'sd0)) begin
                            if (player_vy[7]) begin
                                player_y <= player_y - (~player_vy + 8'd1);

                                if (grav_tick)
                                    player_vy <= player_vy + 8'sd1;
                            end else begin
                                if (player_y + player_vy[6:0] >= GROUND_Y) begin
                                    player_y  <= GROUND_Y;
                                    player_vy <= 8'sd0;
                                end else begin
                                    player_y <= player_y + player_vy[6:0];

                                    if (grav_tick)
                                        player_vy <= player_vy + 8'sd1;
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule


module renderer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [9:0] pix_x,
    input  wire [9:0] pix_y,
    input  wire       visible,

    input  wire       game_over,

    input  wire [6:0] player_y,
    input  wire       ducking,

    input  wire [8:0] obs0_x,
    input  wire [8:0] obs1_x,
    input  wire [1:0] obs0_type,
    input  wire [1:0] obs1_type,

    input  wire [7:0] cloud_x,
    input  wire [6:0] cloud_y,

    output reg  [5:0] rgb
);

    wire [7:0] sx  = pix_x[9:2];
    wire [8:0] sx9 = {1'b0, pix_x[9:2]};
    wire [6:0] sy  = pix_y[8:2];

    wire [6:0] player_top = ducking ? player_y + 7'd8 : player_y;
    wire [6:0] player_h   = ducking ? 7'd8 : 7'd16;

    wire player =
        (sx >= 8'd20) &&
        (sx <  8'd28) &&
        (sy >= player_top + 7'd1) &&
        (sy <  player_top + player_h - 7'd1);

    wire player_leg_l =
        (sx >= 8'd20) &&
        (sx <  8'd23) &&
        (sy == player_top + player_h - 7'd1);

    wire player_leg_r =
        (sx >= 8'd25) &&
        (sx <  8'd28) &&
        (sy == player_top + player_h - 7'd1);

    wire player_head =
        (sx >= 8'd21) &&
        (sx <  8'd27) &&
        (sy >= player_top) &&
        (sy <  player_top + 7'd1);

    wire player_eye =
        (sx >= 8'd22) &&
        (sx <  8'd26) &&
        (sy >= player_top + 7'd2) &&
        (sy <  player_top + 7'd6);

    wire player_iris =
        (sx >= 8'd23) &&
        (sx <  8'd25) &&
        (sy >= player_top + 7'd3) &&
        (sy <  player_top + 7'd5);

    wire [8:0] obs0_dx = sx9 - obs0_x;
    wire [8:0] obs1_dx = sx9 - obs1_x;

    wire obs0_near = (sx9 >= obs0_x) && (obs0_dx < 9'd10);
    wire obs1_near = (sx9 >= obs1_x) && (obs1_dx < 9'd10);

    function obstacle_pixel;
        input [1:0] typ;
        input [3:0] dx;
        input [6:0] y;

        begin
            case (typ)
                2'd0: begin
                    obstacle_pixel =
                        ((dx < 4'd6) && (y >= 7'd94) && (y < 7'd100)) ||
                        ((dx >= 4'd1) && (dx < 4'd5) && (y == 7'd93));
                end

                2'd1: begin
                    obstacle_pixel =
                        ((dx >= 4'd2) && (dx < 4'd6) && (y >= 7'd80) && (y < 7'd84)) ||
                        ((dx >= 4'd1) && (dx < 4'd7) && (y >= 7'd84) && (y < 7'd86)) ||
                        ((dx < 4'd2) && (y >= 7'd81) && (y < 7'd83)) ||
                        ((dx >= 4'd6) && (dx < 4'd8) && (y >= 7'd82) && (y < 7'd84));
                end

                default: begin
                    obstacle_pixel =
                        ((dx < 4'd10) && (y >= 7'd92) && (y < 7'd100)) ||
                        ((dx >= 4'd2) && (dx < 4'd8) && (y >= 7'd90) && (y < 7'd92));
                end
            endcase
        end
    endfunction

    wire obs0_pixel = obs0_near && obstacle_pixel(obs0_type, obs0_dx[3:0], sy);
    wire obs1_pixel = obs1_near && obstacle_pixel(obs1_type, obs1_dx[3:0], sy);

    wire obs_small = ((obs0_type == 2'd0) && obs0_pixel) ||
                     ((obs1_type == 2'd0) && obs1_pixel);

    wire obs_bird = ((obs0_type == 2'd1) && obs0_pixel) ||
                    ((obs1_type == 2'd1) && obs1_pixel);

    wire obs_big = ((obs0_type == 2'd2) && obs0_pixel) ||
                   ((obs1_type == 2'd2) && obs1_pixel);

    wire cloud =
        (
            ((sx >= cloud_x)        && (sx < cloud_x + 8'd30) && (sy >= cloud_y + 7'd2) && (sy < cloud_y + 7'd10)) ||
            ((sx >= cloud_x + 8'd4) && (sx < cloud_x + 8'd26) && (sy >= cloud_y)        && (sy < cloud_y + 7'd12))
        );

    reg [3:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= 4'd0;
        else
            counter <= counter + 4'd1;
    end

    wire ground       = counter[3] ? ((sy >= 7'd100) && (sy < 7'd103))
                                   : ((sy >= 7'd100) && (sy < 7'd104));

    wire under_ground = counter[3] ? (sy >= 7'd103)
                                   : (sy >= 7'd104);

    wire game_over_border =
        game_over &&
        (
            (sx < 8'd3) ||
            (sx >= 8'd157) ||
            (sy < 7'd3) ||
            (sy >= 7'd117)
        );

    always @* begin
        rgb = 6'b000000;

        if (visible && game_over_border)
            rgb = 6'b110000;
        else if (visible && player_iris)
            rgb = 6'b000000;
        else if (visible && (cloud || player_eye))
            rgb = 6'b111111;
        else if (visible && obs_small)
            rgb = 6'b101010;
        else if (visible && obs_big)
            rgb = 6'b010101;
        else if (visible && obs_bird)
            rgb = 6'b000000;
        else if (visible && (player || player_head || player_leg_l || player_leg_r))
            rgb = 6'b100000;
        else if (visible && ground)
            rgb = 6'b000100;
        else if (visible && under_ground)
            rgb = 6'b100100;
        else if (visible)
            rgb = 6'b011011;
    end

endmodule

module audio_engine (
    input  wire clk,
    input  wire rst_n,
    input  wire frame_tick,
    input  wire game_over,
    output reg  audio_pwm
);

    localparam [4:0]  PRESCALE_MAX = 5'd24; 
    localparam [12:0] H_REST = 13'd0;
    localparam [12:0] H_A2   = 13'd4545;
    localparam [12:0] H_B2   = 13'd4050;
    localparam [12:0] H_C3   = 13'd3822;
    localparam [2:0] STEP_FRAMES = 3'd7;

    reg [4:0]  prescale_cnt;
    reg [2:0]  frame_div;
    reg [2:0]  idx;
    reg        game_prev;
    reg        game_beep;
    reg        rand_bit;
    reg [12:0] tone_cnt;
    reg [12:0] half_period;

    always @* begin
        if (game_beep) begin
            half_period = H_A2;
        end else begin
            case (idx)
                3'd0: half_period = H_A2;
                3'd1: half_period = H_REST;
                3'd2: half_period = rand_bit ? H_B2 : H_A2;
                3'd3: half_period = H_A2;
                3'd4: half_period = H_REST;
                3'd5: half_period = H_C3;
                3'd6: half_period = rand_bit ? H_A2 : H_B2;
                default: half_period = H_REST;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale_cnt <= 5'd0;
            idx          <= 3'd0;
            frame_div    <= 3'd0;
            game_prev    <= 1'b0;
            game_beep    <= 1'b0;
            rand_bit     <= 1'b0;
            tone_cnt     <= 13'd0;
            audio_pwm    <= 1'b0;
        end else begin
            game_prev <= game_over;

            if (game_over && !game_prev) begin
                game_beep <= 1'b1;
                frame_div <= 3'd0;
                tone_cnt  <= 13'd0;
                audio_pwm <= 1'b0;
            end

            if (frame_tick) begin
                if (frame_div == STEP_FRAMES - 3'd1) begin
                    frame_div <= 3'd0;
                    rand_bit  <= rand_bit ^ idx[0] ^ game_over;

                    if (game_beep)
                        game_beep <= 1'b0;
                    else if (!game_over)
                        idx <= idx + 3'd1;
                end else begin
                    frame_div <= frame_div + 3'd1;
                end
            end

            if (prescale_cnt == PRESCALE_MAX) begin
                prescale_cnt <= 5'd0;

                if ((half_period == H_REST) || (game_over && !game_beep)) begin
                    tone_cnt  <= 13'd0;
                    audio_pwm <= 1'b0;
                end else if (tone_cnt >= half_period) begin
                    tone_cnt  <= 13'd0;
                    audio_pwm <= ~audio_pwm;
                end else begin
                    tone_cnt <= tone_cnt + 13'd1;
                end
            end else begin
                prescale_cnt <= prescale_cnt + 5'd1;
            end
        end
    end

endmodule
