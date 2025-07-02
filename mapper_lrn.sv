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

    // Internal counters and state
    logic [N_WIDTH-1:0] idx4_r, idx4_w, next_idx4_w;
    logic [M_WIDTH-1:0] idx3_r, idx3_w, next_idx3_w;
    logic [E_WIDTH-1:0] idx2_r, idx2_w, next_idx2_w;
    logic [F_WIDTH-1:0] idx1_r, idx1_w, next_idx1_w;

    logic idx1_max, idx2_max, idx3_max, idx4_max;
    logic increment_indices_w, delay_write;

    logic [E_WIDTH-1:0] padded_dim2;
    logic [F_WIDTH-1:0] padded_dim1;

    logic [(F_WIDTH + E_WIDTH + M_WIDTH) - 1:0] normalized_pixels_count;

    // Padded dimensions
    always_comb begin
        padded_dim2 = dim2 + (2 * padding_num);
        padded_dim1 = dim1 + (2 * padding_num);
    end

    // Index boundary checks
    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            idx1_max <= 0;
            idx2_max <= 0;
            idx3_max <= 0;
            idx4_max <= 0;
        end else begin
            idx1_max <= (idx1_w == dim1-1);
            idx2_max <= (idx2_w == dim2-1);
            idx3_max <= (idx3_w == dim3-1);
            idx4_max <= (idx4_w == dim4-1);
        end
    end

    // Next write indices generation (combinational)
    always_comb begin
        next_idx1_w = idx1_w;
        next_idx2_w = idx2_w;
        next_idx3_w = idx3_w;
        next_idx4_w = idx4_w;

        if (idx4_max) begin
            next_idx4_w = 0;
            if (idx3_max) begin
                next_idx3_w = 0;
                if (idx2_max) begin
                    next_idx2_w = 0;
                    if (idx1_max) begin
                        next_idx1_w = 0;
                    end else next_idx1_w = idx1_w + 1;
                end else next_idx2_w = idx2_w + 1;
            end else next_idx3_w = idx3_w + 1;
        end else next_idx4_w = idx4_w + 1;
    end

    // Multiplier blocks for address computation
    logic [F_WIDTH + E_WIDTH - 1:0] r_temp_1, r_temp_2;
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1:0] r_temp_3, r_temp_4;
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH - 1:0] r_temp_5;
    logic [ADDR_BUS_WIDTH-1:0] r_addr_temp;

    logic [V_WIDTH + E_WIDTH - 1:0] w_temp_1;
    logic [V_WIDTH + F_WIDTH - 1:0] w_temp_2;
    logic [E_WIDTH + V_WIDTH + F_WIDTH - 1:0] w_temp_3;
    logic [F_WIDTH + E_WIDTH - 1:0] w_temp_4;
    logic [F_WIDTH + E_WIDTH + M_WIDTH - 1:0] w_temp_5, w_temp_6;
    logic [F_WIDTH + E_WIDTH + M_WIDTH + N_WIDTH - 1:0] w_temp_7;
    logic [ADDR_BUS_WIDTH-1:0] w_addr_temp;

    // Instantiate your multiplier/adder modules here (not shown)
    // Replace with behavioral computation for now
    always_comb begin
        r_temp_1 = idx1_r * dim2;
        r_temp_2 = dim1 * dim2;
        r_temp_3 = r_temp_2 * idx3_r;
        r_temp_4 = r_temp_2 * dim3;
        r_temp_5 = r_temp_4 * idx4_r;
        r_addr_temp = r_temp_5 + r_temp_3 + r_temp_1 + idx2_r;

        w_temp_1 = padding_num + idx2_w;
        w_temp_2 = padding_num + idx1_w;
        w_temp_3 = padded_dim2 * w_temp_2;
        w_temp_4 = padded_dim1 * padded_dim2;
        w_temp_5 = w_temp_4 * idx3_w;
        w_temp_6 = w_temp_4 * dim3;
        w_temp_7 = w_temp_6 * idx4_w;
        w_addr_temp = w_temp_7 + w_temp_5 + w_temp_3 + w_temp_1;
    end

    assign r_addr = r_addr_temp;
    assign w_addr = w_addr_temp;

    // FSM states
    typedef enum logic [2:0] {IDLE, READ, PROCESS, WRITE, WAIT} state_t;
    state_t current_state, next_state;

    always_ff @(posedge core_clk or posedge reset) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        case (current_state)
            IDLE    : next_state = start_normalization ? READ : IDLE;
            READ    : next_state = full_flag ? PROCESS : READ;
            PROCESS : next_state = (normalized_layer ? IDLE : (div_out_valid ? WRITE : (normalized_window ? WAIT : PROCESS)));
            WRITE   : next_state = normalized_window ? WRITE : PROCESS;
            WAIT    : next_state = READ;
            default : next_state = IDLE;
        endcase
    end

    // FSM outputs
    always_ff @(posedge core_clk or posedge reset) begin
        if (reset) begin
            idx1_r <= 0; idx2_r <= 0; idx3_r <= 0; idx4_r <= 0;
            idx1_w <= 0; idx2_w <= 0; idx3_w <= 0; idx4_w <= 0;
            w_enable <= 0; r_enable <= 0;
            normalized_layer <= 0;
            normalized_pixels_count <= 0;
            increment_indices_w <= 0;
            delay_write <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    idx1_r <= 0; idx2_r <= 0; idx3_r <= 0; idx4_r <= 0;
                    idx1_w <= 0; idx2_w <= 0; idx3_w <= 0; idx4_w <= 0;
                    w_enable <= 0; r_enable <= 0;
                    normalized_pixels_count <= 0;
                    normalized_layer <= 0;
                    increment_indices_w <= 0;
                    delay_write <= 0;
                    if(next_state == READ) r_enable <= 1;
                end

                READ: begin 
                    if (idx3_r == dim3-1) r_enable <= 0;
                    w_enable <= 0;
                if(r_enable) begin
                    if (idx4_r == dim4 - 1) begin
                        idx4_r <= 0;
                        if (idx3_r == dim3 - 1) begin
                            idx3_r <= 0;
                            if (idx2_r == dim2 - 1) begin
                                idx2_r <= 0;
                                if (idx1_r == dim1 - 1)
                                    idx1_r <= 0;
                                else
                                    idx1_r <= idx1_r + 1;
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
                        delay_write <= 1;
                        normalized_pixels_count <= normalized_pixels_count + 1;
                    end else begin
                        w_enable <= 0;
                        delay_write <= 0;
                    end
                end

                WRITE: begin
                    r_enable <= 0;
                    w_enable <= 0;
                    if (delay_write) begin
                        // update indices AFTER writing
                        idx1_w <= next_idx1_w;
                        idx2_w <= next_idx2_w;
                        idx3_w <= next_idx3_w;
                        idx4_w <= next_idx4_w;
                        delay_write <= 0;
                    end

                    if (normalized_pixels_count == dim1 * dim2 * dim3 * dim4) begin
                        normalized_pixels_count <= 0;
                        normalized_layer <= 1;
                    end
                end

                WAIT: begin
                    r_enable <= 1;
                    w_enable <= 0;
                    normalized_layer <= 0;
                end
            endcase
        end
    end

endmodule
