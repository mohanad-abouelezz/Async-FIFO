module Ifmap_Index_Generator
#( 
    parameter W_WIDTH = 8,
    parameter H_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter N_WIDTH = 3,
    parameter C_WIDTH = 10,
    parameter D_WIDTH = 8,
    parameter R_WIDTH = 4,
    parameter U_WIDTH = 3,
    parameter e_WIDTH = 8
) (
    input clk,
    input reset,
    input start,
    input await,

    output reg busy,
    output reg done,

    input [N_WIDTH - 1:0] ifmap_base,
    input [C_WIDTH - 1:0] channel_base,

    input [n_WIDTH - 1:0] n,
    input [H_WIDTH - 1:0] H,
    input [W_WIDTH - 1:0] W,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,

    input [R_WIDTH - 1:0] R,
    input [U_WIDTH - 1:0] U,
    input [e_WIDTH - 1:0] e,

    output reg [n_WIDTH - 1:0] ifmap_index,
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    output reg [H_WIDTH - 1:0] row_index,
    output reg [W_WIDTH - 1:0] col_index
);

    typedef enum {IDLE, LOOPING, DONE} state_type;
    state_type state_nxt, state_crnt;

    logic [D_WIDTH - 1: 0] D;
    assign D = (e << (U >> 1)) + R - U;

    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [W_WIDTH - 1:0] W_nxt, W_crnt;
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;
    logic [D_WIDTH - 1:0] D_nxt, D_crnt;
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;
    
    // Intermediate signals for additions
    wire [N_WIDTH - 1:0] sum_ib_nc;
    wire [C_WIDTH - 1:0] sum_cb_qc;
    wire [C_WIDTH - 1:0] sum_rq;

    // Intermediate signals for multiplications
    wire [q_WIDTH + r_WIDTH - 1:0] r_mul_q;

    always_ff @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            n_crnt <= 0;
            W_crnt <= 0;
            q_crnt <= 0;
            D_crnt <= 0;
            r_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            n_crnt <= n_nxt;
            W_crnt <= W_nxt;
            q_crnt <= q_nxt;
            D_crnt <= D_nxt;
            r_crnt <= r_nxt;
        end
    end

    always_comb begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        n_nxt = n_crnt;
        W_nxt = W_crnt;
        q_nxt = q_crnt;
        D_nxt = D_crnt;
        r_nxt = r_crnt;

        case(state_crnt)
            IDLE:
            begin
                n_nxt = 0;
                W_nxt = 0;
                q_nxt = 0;
                D_nxt = 0;
                r_nxt = 0;

                if (start) begin
                    state_nxt = LOOPING;
                end 
            end
            LOOPING:
            begin
               if (!await) begin
                    busy = 1'b1;
                    if (r_crnt == r - 1) begin 
                        if (D_crnt == D - 1) begin 
                            if (q_crnt == q - 1) begin 
                                if (W_crnt == W - 1) begin
                                    if (n_crnt == n - 1) begin
                                        state_nxt = DONE;
                                        n_nxt = 0;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end else begin
                                        n_nxt = n_crnt + 1;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end
                                end else begin
                                    W_nxt = W_crnt + 1;
                                    q_nxt = 0;
                                    D_nxt = 0;
                                    r_nxt = 0;
                                end
                            end else begin
                                q_nxt = q_crnt + 1;
                                D_nxt = 0;
                                r_nxt = 0;
                            end
                        end else begin
                            D_nxt = D_crnt + 1;
                            r_nxt = 0;
                        end
                    end else begin
                        r_nxt = r_crnt + 1; 
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

    // Instantiation of the multiplier for the multiplication operation
    unsigned_wallace_tree_multiplier #(
        .in1_width(r_WIDTH),
        .in2_width(q_WIDTH)
    ) mul_r_q_inst (
        .in1(r_crnt),
        .in2(q),
        .out(r_mul_q)
    );

    // Instantiation of adders for each addition operation
    cla #(
        .width(N_WIDTH)
    ) cla_add_ib_nc (
        .x(ifmap_base),
        .y({{(N_WIDTH-n_WIDTH){1'b0}}, n_crnt}), // Zero extend n_crnt to match width
        .sum(sum_ib_nc)
    );

    cla #(
        .width(C_WIDTH)
    ) cla_add_cb_qc (
        .x(channel_base),
        .y({{(C_WIDTH-q_WIDTH){1'b0}}, q_crnt}), // Zero extend q_crnt to match width
        .sum(sum_cb_qc)
    );

    cla #(
        .width(C_WIDTH)
    ) cla_add_cb_qc_rq (
        .x(sum_cb_qc),
        .y({{(C_WIDTH-(q_WIDTH + r_WIDTH)){1'b0}}, r_mul_q}), // Zero extend multiplication result to match width
        .sum(sum_rq)
    );

    always_ff @(posedge clk) begin
        ifmap_index <= sum_ib_nc; // Final index after addition
        channel_index <= sum_rq;  // Channel index after addition
        row_index <= D_crnt;
        col_index <= W_crnt;
    end

endmodule
