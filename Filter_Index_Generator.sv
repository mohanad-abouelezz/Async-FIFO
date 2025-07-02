module Filter_Index_Generator
#( 
    parameter S_WIDTH = 6,
    parameter R_WIDTH = 4,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,
    parameter i_WIDTH = 3,
    parameter M_WIDTH = 10,
    parameter C_WIDTH = 10
) (
    input clk,
    input reset,
    input start,
    input await,
    
    output reg busy,
    output reg done,
    
    input [M_WIDTH - 1:0] filter_base,
    input [C_WIDTH - 1:0] channel_base,
    
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t, 

    output reg [p_WIDTH + t_WIDTH - 1:0] filter_index,
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    output reg [R_WIDTH - 1:0] row_index,
    output reg [S_WIDTH - 1:0] col_index
);
    
    typedef enum {IDLE, LOOPING, DONE} state_type;
    state_type state_nxt, state_crnt;
    
    logic [S_WIDTH - 1:0] S_nxt, S_crnt;
    logic [R_WIDTH - 1:0] R_nxt, R_crnt;
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;
    
    // Intermediate signals for additions
    wire [M_WIDTH - 1:0] sum_fb_pc;
    wire [M_WIDTH - 1:0] sum_tp_ic;
    wire [C_WIDTH - 1:0] sum_rq_ic;
    wire [M_WIDTH - 1:0] filter_index_res;
    wire [C_WIDTH - 1:0] channel_base_add;


    // Intermediate signals for multiplications
    wire [p_WIDTH + t_WIDTH - 1:0] t_mul_p;
    wire [q_WIDTH + r_WIDTH - 1:0] r_mul_q;

    always_ff @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            S_crnt <= 0;
            R_crnt <= 0;
            p_crnt <= 0;
            q_crnt <= 0;
            r_crnt <= 0;
            t_crnt <= 0;
            i_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            S_crnt <= S_nxt;
            R_crnt <= R_nxt;
            p_crnt <= p_nxt;
            q_crnt <= q_nxt;
            r_crnt <= r_nxt;
            t_crnt <= t_nxt;
            i_crnt <= i_nxt;
        end
    end
    
    always_comb begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        S_nxt = S_crnt;
        R_nxt = R_crnt;
        p_nxt = p_crnt;
        q_nxt = q_crnt;
        r_nxt = r_crnt;
        t_nxt = t_crnt;
        i_nxt = i_crnt;
        
        case(state_crnt)
            IDLE:
            begin
                S_nxt = 0;
                R_nxt = 0;
                p_nxt = 0;
                q_nxt = 0;
                r_nxt = 0;
                t_nxt = 0;
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
                            if (r_crnt == r - 1) begin
                                if (R_crnt == R - 1) begin
                                    if (p_crnt == p - 4) begin 
                                        if (q_crnt == q - 1) begin
                                            if (S_crnt == S - 1) begin 
                                                state_nxt = DONE;
                                                S_nxt = 0;
                                                R_nxt = 0;
                                                p_nxt = 0;
                                                q_nxt = 0;
                                                r_nxt = 0;
                                                t_nxt = 0;
                                                i_nxt = 0;
                                            end else begin
                                                S_nxt = S_crnt + 1;
                                                R_nxt = 0;
                                                p_nxt = 0;
                                                q_nxt = 0;
                                                r_nxt = 0;
                                                t_nxt = 0;
                                                i_nxt = 0;
                                            end
                                        end else begin
                                            q_nxt = q_crnt + 1;
                                            R_nxt = 0;
                                            p_nxt = 0;
                                            r_nxt = 0;
                                            t_nxt = 0;
                                            i_nxt = 0;
                                        end
                                    end else begin
                                        p_nxt = p_crnt + 4;
                                        R_nxt = 0;
                                        r_nxt = 0;
                                        t_nxt = 0;
                                        i_nxt = 0;
                                    end
                                end else begin
                                    R_nxt = R_crnt + 1;
                                    r_nxt = 0;
                                    t_nxt = 0;
                                    i_nxt = 0;
                                end
                            end else begin
                                r_nxt = r_crnt + 1;
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

    // Instantiation of multipliers for the multiplication operations
    unsigned_wallace_tree_multiplier #(
        .in1_width(t_WIDTH),
        .in2_width(p_WIDTH)
    ) mul_t_p (
        .in1(t_crnt),
        .in2(p),
        .out(t_mul_p)
    );

    unsigned_wallace_tree_multiplier #(
        .in1_width(r_WIDTH),
        .in2_width(q_WIDTH)
    ) mul_r_q (
        .in1(r_crnt),
        .in2(q),
        .out(r_mul_q)
    );

    // Instantiation of adders for each addition operation
    cla #(
        .width(M_WIDTH)
    ) cla_add_fb_pc (
        .x(filter_base),
        .y({{(M_WIDTH-p_WIDTH){1'b0}}, p_crnt}), // Zero extend p_crnt to match width
        .sum(sum_fb_pc)
    );

    cla #(
        .width(M_WIDTH)
    ) cla_add_fp_pc_ic (
        .x(sum_fb_pc),
        .y({{(M_WIDTH-i_WIDTH){1'b0}}, i_crnt}), // Zero extend i_crnt to match width
        .sum(filter_index_res)
    );

    cla #(
        .width(M_WIDTH)
    ) cla_add_fp_pc_ic_tp (
        .x(filter_index_res),
        .y({{(M_WIDTH-(t_WIDTH + p_WIDTH)){1'b0}}, t_mul_p}), // Zero extend i_crnt to match width
        .sum(sum_tp_ic)
    );

    cla #(
        .width(C_WIDTH)
    ) cla_add_cb_qc (
        .x(channel_base),
        .y({{(C_WIDTH-q_WIDTH){1'b0}}, q_crnt}), // Zero extend q_crnt to match width
        .sum(channel_base_add)
    );

    cla #(
        .width(C_WIDTH)
    ) cla_add_cb_qc_rq (
        .x(channel_base_add),
        .y({{(C_WIDTH-(r_WIDTH + q_WIDTH)){1'b0}}, r_mul_q}), // Zero extend q_crnt to match width
        .sum(sum_rq_ic)
    );


    always_ff @(posedge clk) begin
        filter_index <= sum_tp_ic; // Final index after addition
        channel_index <= sum_rq_ic; // Channel index after addition
        row_index <= R_crnt;
        col_index <= S_crnt;
    end
    
endmodule
