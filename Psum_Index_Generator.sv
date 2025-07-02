module Psum_Index_Generator
#( 
    parameter M_WIDTH = 10,
    parameter N_WIDTH = 3,
    parameter E_WIDTH = 6,
    parameter F_WIDTH = 6,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter t_WIDTH = 3,
    parameter i_WIDTH = 3
) (
    input clk,
    input reset,
    input start,
    input await,
    
    output reg busy,
    output reg done,
    
    input [N_WIDTH - 1:0] psum_base,
    input [M_WIDTH - 1:0] channel_base,

    input [F_WIDTH - 1:0] F,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [t_WIDTH - 1:0] t,
    
    output reg [n_WIDTH - 1:0] psum_index,
    output reg [p_WIDTH + t_WIDTH - 1:0] channel_index,
    output reg [E_WIDTH - 1:0] row_index,
    output reg [F_WIDTH - 1:0] col_index
);

    typedef enum {IDLE, LOOPING, DONE} state_type;
    state_type state_nxt, state_crnt;
    
    logic [F_WIDTH - 1:0] F_nxt, F_crnt;
    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;
    logic [E_WIDTH - 1:0] e_nxt, e_crnt;
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;
    
    // Intermediate signals for additions
    wire [N_WIDTH - 1:0] sum_pb_nc;
    wire [M_WIDTH - 1:0] sum_cb_ic;
    wire [M_WIDTH - 1:0] sum_cb_ic_pc_tp;
    wire [M_WIDTH - 1:0] final_channel_index;

    // Intermediate signals for multiplication
    wire [p_WIDTH + t_WIDTH - 1:0] t_mul_p;

    always_ff @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            F_crnt <= 0;
            n_crnt <= 0;
            p_crnt <= 0;
            t_crnt <= 0;
            e_crnt <= 0;
            i_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            F_crnt <= F_nxt;
            n_crnt <= n_nxt;
            p_crnt <= p_nxt;
            t_crnt <= t_nxt;
            e_crnt <= e_nxt;
            i_crnt <= i_nxt;
        end
    end
    
    always_comb begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        F_nxt = F_crnt;
        n_nxt = n_crnt;
        p_nxt = p_crnt;
        t_nxt = t_crnt;
        e_nxt = e_crnt;
        i_nxt = i_crnt;
        
        case(state_crnt)
            IDLE:
            begin
                F_nxt = 0;
                n_nxt = 0;
                p_nxt = 0;
                t_nxt = 0;
                e_nxt = 0;
                i_nxt = 0;
                if (start) begin
                    state_nxt = LOOPING;
                end 
            end
            LOOPING: 
            begin
                if (!await) begin
                    busy = 1'b1;
                    if (i_crnt == 3) begin 
                        if (t_crnt == t - 1) begin
                            if (e_crnt == e - 1) begin
                                if (p_crnt == p - 4) begin
                                    if (F_crnt == F - 1) begin 
                                        if (n_crnt == n - 1) begin 
                                            state_nxt = DONE;
                                            n_nxt = 0;
                                            F_nxt = 0;
                                            p_nxt = 0;
                                            e_nxt = 0;
                                            t_nxt = 0;
                                            i_nxt = 0;
                                        end else begin
                                            n_nxt = n_crnt + 1;
                                            F_nxt = 0;
                                            p_nxt = 0;
                                            e_nxt = 0;
                                            t_nxt = 0;
                                            i_nxt = 0;
                                        end    
                                    end else begin
                                        F_nxt = F_crnt + 1;
                                        p_nxt = 0;
                                        e_nxt = 0;
                                        t_nxt = 0;
                                        i_nxt = 0;
                                    end    
                                end else begin
                                    p_nxt = p_crnt + 4;
                                    e_nxt = 0;
                                    t_nxt = 0;
                                    i_nxt = 0;
                                end
                            end else begin
                                e_nxt = e_crnt + 1;
                                t_nxt = 0;
                                i_nxt = 0;
                            end
                        end else begin
                            t_nxt = t_crnt + 1;
                            i_nxt = 0;
                        end
                    end else begin
                        i_nxt = i_crnt + 1;
                    end
                end
            end
            DONE:
            begin
                done = 1'b1;
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end

    // Instantiation of multiplier for the multiplication operation
    unsigned_wallace_tree_multiplier #(
        .in1_width(t_WIDTH),
        .in2_width(p_WIDTH)
    ) mul_t_p_inst (
        .in1(t_crnt),
        .in2(p),
        .out(t_mul_p)
    );

    // Instantiation of adders for each addition operation
    cla #(
        .width(N_WIDTH)
    ) cla_add_pb_nc (
        .x(psum_base),
        .y({{(N_WIDTH - n_WIDTH){1'b0}}, n_crnt}), // Zero extend n_crnt to match width
        .sum(sum_pb_nc)
    );

    cla #(
        .width(M_WIDTH)
    ) cla_add_cb_ic (
        .x(channel_base),
        .y({{(M_WIDTH - i_WIDTH){1'b0}}, i_crnt}), // Zero extend i_crnt to match width
        .sum(sum_cb_ic)
    );

    cla #(
        .width(M_WIDTH)
    ) cla_add_cb_ic_pc (
        .x(sum_cb_ic),
        .y({{(M_WIDTH - p_WIDTH){1'b0}}, p_crnt}), // Zero extend p_crnt to match width
        .sum(final_channel_index)
    );

    cla #(
        .width(M_WIDTH)
    ) cla_add_cb_ic_pc_tp (
        .x(final_channel_index),
        .y({{(M_WIDTH - (t_WIDTH + p_WIDTH)){1'b0}}, t_mul_p}), // Zero extend p_crnt to match width
        .sum(sum_cb_ic_pc_tp)
    );

    always_ff @(posedge clk) begin
        psum_index    <= sum_pb_nc; // Final index after addition
        channel_index <= sum_cb_ic_pc_tp;  // Channel index after addition
        row_index     <= e_crnt;
        col_index     <= F_crnt;
    end
    endmodule
