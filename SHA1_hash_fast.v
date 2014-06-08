module SHA1_hash_fast (       
	clk, 		
	nreset, 	
	start_hash,  
	message_addr,	
	message_size, 	
	hash, 	
	done, 		
	port_A_clk,
        port_A_data_in,
        port_A_data_out,
        port_A_addr,
        port_A_we
	);
	
//define endian switch function:
function [31:0] changeEndian;
		input [31:0] value;
		changeEndian = { value[7:0], value[15:8], value[23:16], value[31:24]};
endfunction
		
input	clk;
input	nreset; 
// Initializes the SHA1_hash module

input	start_hash; 
// Tells SHA1_hash to start hashing the given frame

input 	[31:0] message_addr; 
// Starting address of the messagetext frame
// i.e., specifies from where SHA1_hash must read the messagetext frame

input	[31:0] message_size; 
// Length of the message in bytes

output	[159:0] hash; 
// hash results


input   [31:0] port_A_data_out; 
// read data from the dpsram (messagetext)

output  [31:0] port_A_data_in;
// write data to the dpsram (ciphertext)

output  [15:0] port_A_addr;
// address of dpsram being read/written 

output  port_A_clk;
// clock to dpsram (drive this with the input clk) 

output  port_A_we;
// read/write selector for dpsram

output	done; // done is a signal to indicate that hash  is complete

parameter IDLE = 1'b0;
parameter COMPUTE = 1'b1;

integer i;

reg [31:0]		runMD[0:4], currMD[0:4], current_length, word_n, W[0:79], K_t, F_b_c_d, T;
reg [15:0]		read_addr;
reg [6:0]		count_t;
reg [1:0]		init_read;
reg				wen, state;

wire [31:0]		word_read_n, total_length, A, B, C, D, E, W_t_next_no_shift;
wire [15:0]		read_addr_n;
wire [9:0]		zero_pad_length;
wire				stop_read;




/////////ASSIGNMENTS//////////////

//INIT 
//NOTE: I think zero_pad_length is 1 more if this mod is not zero
assign zero_pad_length = 512 - (((8 * message_size) + 65) % 512);
	//size of message + 1 + number of zeros + size of size encoding.
assign total_length = (message_size * 8) + 1 + zero_pad_length + 64;

//READ
assign read_addr_n = ((count_t > 13) & (count_t < 78) | stop_read) ? read_addr : read_addr + 4;
assign stop_read = (current_length == (message_size *8));

//READ/WRITE
assign port_A_addr = read_addr;
assign port_A_clk = clk;
assign word_read_n = changeEndian(port_A_data_out);
assign done = (current_length-32 == total_length) && (state == IDLE);

//WRITE
assign port_A_we = wen;

//COMPUTE:
assign A = currMD[0];
assign B = currMD[1];
assign C = currMD[2];
assign D = currMD[3];
assign E = currMD[4];
assign W_t_next_no_shift = (W[count_t+1-3] ^ W[count_t+1-8] ^ W[count_t+1-14] ^ W[count_t+1-16]);

//OUT
assign hash = {runMD[0],runMD[1],runMD[2],runMD[3],runMD[4]};


always@(*)
begin
	//check which part of the buffer we want to add:
	if(current_length+32 == total_length) begin
		word_n <= (message_size * 8);
	end
	//single bit pad:
	else if((message_size - (current_length)/8 < 4)) begin
		case(message_size % 4)
		0: word_n <= 32'h80000000;
		1: word_n <= word_read_n & 32'hFF000000 | 32'h00800000;
		2: word_n <= word_read_n & 32'hFFFF0000 | 32'h00008000;
		3: word_n <= word_read_n & 32'hFFFFFF00 | 32'h00000080;
		endcase
	end
	// zero bit pads:
	else if(current_length > message_size*8) begin
		word_n <= 32'h00000000;
	end
	//not doing padding, doing reads:
	else begin
		word_n <= word_read_n;
	end
	
	//compute current K_t and F_b_c_d
	if(count_t < 20) begin
		K_t <= 32'h5a827999;
		F_b_c_d <= (B & C) | ((~B) & D);
	end
	else if(count_t < 40) begin
		K_t <= 32'h6ed9eba1;
		F_b_c_d <= B ^ C ^ D;
	end
	else if(count_t < 60) begin
		K_t <= 32'h8f1bbcdc;
		F_b_c_d <= (B & C) | (B & D) | (C & D);
	end
	else begin
		K_t <= 32'hca62c1d6;
		F_b_c_d <= B ^ C ^ D;
	end
	
	//compute value of T
	T <= ((A << 5) | (A >> 27)) + F_b_c_d + W[count_t] + K_t + E;
end




//main logic:
always@(posedge clk or negedge nreset)
begin
	if(!nreset) begin
		//reset all registers
		wen <= 1'b0;
		state <=	IDLE;
		current_length <= 32'b0;
		count_t <= 7'b0;
		for(i = 0; i < 5; i = 1 + i) begin
			currMD[i] <= 32'b0;
			runMD[i] <= 32'b0;
		end
		init_read <= 2'b0;
	end
	else begin
		case(state)
			
			IDLE: begin
				if(start_hash) begin
					read_addr <= message_addr[15:0];
					state <= COMPUTE;
					init_read <= 2'b10;
					current_length <= 32'b0;
					
					//initialize to M values:
					runMD[0] <= 32'h67452301;
					runMD[1] <= 32'hefcdab89;
					runMD[2] <= 32'h98badcfe;
					runMD[3] <= 32'h10325476;
					runMD[4] <= 32'hc3d2e1f0;
					
					currMD[0] <= 32'h67452301;
					currMD[1] <= 32'hefcdab89;
					currMD[2] <= 32'h98badcfe;
					currMD[3] <= 32'h10325476;
					currMD[4] <= 32'hc3d2e1f0;
				end
				if(wen) begin
					wen <= 1'b0;
				end
			end
			
			/*
			FIRST_READ: begin
				read_addr <= (words_read > 14) ? read_addr : read_addr_n;
				if(!init_read) begin
					
					//shift data:
					read_hash_data[15] <= word_n;
					for(i = 14; i >= 0; i = i - 1) begin
						read_hash_data[i] <= read_hash_data[i+1];
					end
					words_read <= words_read_n;
					current_length <= current_length + 32; // keep running count of current length
					
					//POTENTIAL HAZARD: this may be either == 15 or == 16
					if(words_read == 15) begin
						state <= COMPUTE; //check if we have filled the buffer
						currMD[0] <= runMD[0];
						currMD[1] <= runMD[1];
						currMD[2] <= runMD[2];
						currMD[3] <= runMD[3];
						currMD[4] <= runMD[4];
						W[0] <= read_hash_data[1];
					end
				end
				else init_read <= 1'b0;
			end*/
			
			COMPUTE: begin
				read_addr <= read_addr_n;
				if(!init_read) begin
					///////////COMPUTE:
					count_t <= (1 + count_t) % 80; //increment count_t
					//compute next W_t:
					if(count_t+1 < 16) begin
						//reads:
						W[count_t+1] <= word_n;
						current_length <= current_length + 32;
					end
					else begin
						W[count_t+1] <= (W_t_next_no_shift << 1) | (W_t_next_no_shift >> 31);
					end

					if(count_t < 79) begin
						//Perform Algorithm:
						currMD[0] <= T;
						currMD[1] <= A;
						currMD[2] <= (B << 30) | (B >> 2);
						currMD[3] <= C;
						currMD[4] <= D;
					end
					else if(count_t == 79) begin
						state <= (current_length == total_length) ? IDLE : COMPUTE;
						runMD[0] <= runMD[0] + T;
						runMD[1] <= runMD[1] + A;
						runMD[2] <= runMD[2] + ((B << 30) | (B >> 2));
						runMD[3] <= runMD[3] + C;
						runMD[4] <= runMD[4] + D;
						
						currMD[0] <= runMD[0] + T;
						currMD[1] <= runMD[1] + A;
						currMD[2] <= runMD[2] + ((B << 30) | (B >> 2));
						currMD[3] <= runMD[3] + C;
						currMD[4] <= runMD[4] + D;
						current_length <= current_length + 32;
						W[0] <= word_n;
					end
				end
				else begin
					init_read <= init_read - 1;
					if(init_read  == 2'b01) begin
						W[0] <= word_n;
						current_length <= current_length + 32;
					end
				end
			end
		
		endcase
	end


end



endmodule