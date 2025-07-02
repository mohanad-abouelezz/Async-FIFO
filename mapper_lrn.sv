//*********************************************************************************\\
/*  DATE: 2025-05-02
    Mapper LRN module with both functional correctness and positive slack
    Fixed: Write address generation, r_enable control, pipelining hazards
*/
//*********************************************************************************\\

module mapper_lrn #(
    parameter N_WIDTH = 2,
    parameter M_WIDTH = 10,
    parameter E_WIDTH = 6,
    parameter F_WIDTH = 6,
    parameter V_WIDTH = 2,
    parameter ADDR_BUS_WIDTH = 20,
    parameter DATA_WIDTH = 16,
    parameter ROW_MAJOR = 1
)(
    input  logic                             core_clk,
    input  logic                             reset,
    input  logic                             start_normalization,
    input  logic [N_WIDTH-1:0]               dim4,
    input  logic [M_WIDTH-1:0]               dim3,
    input  logic [E_WIDTH-1:0]               dim2,
    input  logic [F_WIDTH-1:0]               dim1,
    input  logic [V_WIDTH-1:0]               padding_num,
    input  logic                             normalized_window,
    input  logic                             full_flag,
    input  logic                             div_out_valid,
    output logic [ADDR_BUS_WIDTH-1:0]        r_addr,
    output logic                             r_enable,
    output logic [ADDR_BUS_WIDTH-1:0]        w_addr,
    output logic                             w_enable,
    output logic                             normalized_layer
);

    typedef enum logic [2:0] {
        IDLE, READ, PROCESS, WRITE, WAIT
    } state_t;
    
    state_t current_state, next_state;

    logic [N_WIDTH-1:0] idx4_w, idx4_r;
    logic [M_WIDTH-1:0] idx3_w, idx3_r;
    logic [E_WIDTH-1:0] idx2_w, idx2_r;
    logic [F_WIDTH-1:0] idx1_w, idx1_r;

    logic [E_WIDTH-1:0] padded_dim2;
    logic [F_WIDTH-1:0] padded_dim1;

    assign padded_dim2 = dim2 + (2 * padding_num);
    assign padded_dim1 = dim1 + (2 * padding_num);

    logic [F_WIDTH+E_WIDTH+M_WIDTH-1:0] normalized_pixels_count;

    // Address Calculation
    logic [ADDR_BUS_WIDTH-1:0] r_addr_temp, w_addr_temp;

    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        case(current_state)
            IDLE:    if (start_normalization) next_state = READ;
            READ:    if (full_flag) next_state = PROCESS;
            PROCESS: if (normalized_layer) next_state = IDLE;
                     else if (div_out_valid) next_state = WRITE;
                     else if (normalized_window) next_state = WAIT;
            WRITE:   if (!normalized_window) next_state = PROCESS;
            WAIT:    next_state = READ;
        endcase
    end

    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            idx1_r <= 0; idx2_r <= 0; idx3_r <= 0; idx4_r <= 0;
            idx1_w <= 0; idx2_w <= 0; idx3_w <= 0; idx4_w <= 0;
            r_enable <= 0; w_enable <= 0; normalized_layer <= 0;
            normalized_pixels_count <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    idx1_r <= 0; idx2_r <= 0; idx3_r <= 0; idx4_r <= 0;
                    idx1_w <= 0; idx2_w <= 0; idx3_w <= 0; idx4_w <= 0;
                    r_enable <= 0; w_enable <= 0; normalized_layer <= 0;
                    normalized_pixels_count <= 0;
                    if (next_state == READ) r_enable <= 1;
                end
                READ: begin
                    w_enable <= 0;
                    if (idx3_r == dim3-1) r_enable <= 0;
                    if (r_enable) begin
                        if (idx4_r == dim4-1) begin
                            idx4_r <= 0;
                            if (idx3_r == dim3-1) begin
                                idx3_r <= 0;
                                if (idx2_r == dim2-1) begin
                                    idx2_r <= 0;
                                    if (idx1_r == dim1-1) begin
                                        idx1_r <= 0;
                                    end else idx1_r <= idx1_r + 1;
                                end else idx2_r <= idx2_r + 1;
                            end else idx3_r <= idx3_r + 1;
                        end else idx4_r <= idx4_r + 1;
                    end
                end
                PROCESS: begin
                    r_enable <= 0;
                    normalized_layer <= 0;
                    if (div_out_valid) begin
                        w_enable <= 1;
                        normalized_pixels_count <= normalized_pixels_count + 1;
                    end
                end
                WRITE: begin
                    r_enable <= 0;
                    w_enable <= 0;
                    if (w_enable) begin
                        if (idx4_w == dim4-1) begin
                            idx4_w <= 0;
                            if (idx3_w == dim3-1) begin
                                idx3_w <= 0;
                                if (idx2_w == dim2-1) begin
                                    idx2_w <= 0;
                                    if (idx1_w == dim1-1) begin
                                        idx1_w <= 0;
                                    end else idx1_w <= idx1_w + 1;
                                end else idx2_w <= idx2_w + 1;
                            end else idx3_w <= idx3_w + 1;
                        end else idx4_w <= idx4_w + 1;
                    end
                    if (normalized_pixels_count == dim1 * dim2 * dim3 * dim4) begin
                        normalized_pixels_count <= 0;
                        normalized_layer <= 1;
                    end
                end
                WAIT: begin
                    if(next_state == IDLE) r_enable <= 0;
                    else                   r_enable <= 1;
                    normalized_layer <= 0;
                end
            endcase
        end
    end

    assign r_addr = idx1_r + dim1 * (idx2_r + dim2 * (idx3_r + dim3 * idx4_r));
    assign w_addr = (idx1_w + padding_num) + padded_dim1 *
                    ((idx2_w + padding_num) + padded_dim2 *
                    (idx3_w + dim3 * idx4_w));

endmodule
