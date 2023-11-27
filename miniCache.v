`timescale 1ns/100ps
// cache 模块
module cache();
parameter size = 64;		// cache size
parameter index_size = 6;	// index size
reg [31:0] cache [0:size - 1]; //registers for the data in cache
reg [11 - index_size:0] tag_array [0:size - 1]; // for all tags in cache
reg valid_array [0:size - 1]; //0 - there is no data 1 - there is data
reg dirty_array [0:size - 1]; //0 - not change    1 - need wirte to ram
initial
	begin: initialization
		integer i;
		for (i = 0; i < size; i = i + 1)
		begin
			valid_array[i] = 1'b0;
            dirty_array[i] = 1'b0;
			tag_array[i] = 6'b000000;
		end
	end

endmodule

// ram 模块
module ram();

parameter size = 4096; //size of a ram in bits

reg [31:0] ram [0:size-1]; //data matrix for ram

endmodule


// cache和ram的顶层模块
module cache_and_ram(
	input [31:0] address,			// 地址结构：保留位（20bit）+ tag（6bit） + index（b6it）（注：每个存储单元是4B，且cache块大小也是4B，因此没有cache块内offset）
	input [31:0] data,
	input clk,
	input mode,	// 1:write  0:read
	output [31:0] out
);
parameter size = 64;		// cache size
parameter index_size = 6;	// index size

// previous values
reg [31:0] prev_address, prev_data;  // prev_add的高20位全为0
reg prev_mode;
reg [31:0] temp_out;

reg [index_size - 1:0] index;	// index是6位，直接映射方式，
reg [11 - index_size:0] tag;	// for keeping tag of current address

ram ram();
cache cache();
// 初试化
initial
	begin
		index = 0;
		tag = 0;
		prev_address = 0;
		prev_data = 0;
		prev_mode = 0;
	end
// 检测clk上升沿
always @(posedge clk)
begin
	// 检查读写是否发生变化
	if (prev_address != address || prev_data != data || prev_mode != mode)
		begin
			prev_address = address % ram.size; // 赋值为address低12位,高位补0
			prev_data = data;  // prev_data的设计意义，考虑一种情况：连续两次对同一地址进行写操作
			prev_mode = mode;
			
			tag = prev_address >> cache.index_size;	// tag是prev_address的低12位的高6位
			index = address % cache.size; 		// index赋值为address的低6位
				
			if (mode == 1) // 写  写回+写分配，不写ram，把数据拿到cache后再写，替换的时候脏位为1则写回ram
				begin
                    // 如果要写的数据在cache中，就不需要写ram
                    if(cache.valid_array[index] == 1 && cache.tag_array[index] == tag) 
                    begin
                        cache.cache[index] = data;      //更新数据
                        cache.dirty_array[index] = 1;   // 脏位设为1
                    end
                    else
                        begin
                            // 数据不在cache中,先从ram中取出来放到cache中，再向cache中写
                            if(cache.valid_array[index] == 1 && cache.tag_array[index]!= tag && cache.dirty_array[index] == 1)
                                begin
                                    //待写入位置已有其他数据且脏位是1，需要写回ram
                                    ram.ram[{cache.tag_array[index],index}] = cache.cache[index];
                                end
                            else
                                begin
                                    cache.valid_array[index] = 1;
                                    cache.dirty_array[index] = 1;
							        cache.tag_array[index] = tag;
							        cache.cache[index] = data;      // 写入新数据
                                end
				        end
                        
                end
			else // read
				begin
					// 发现要读的数据不在cache中，要先把数据从ram搬到cache
					if (cache.valid_array[index] != 1 || cache.tag_array[index] != tag)
						begin
                            // 待写入位置已有其他数据且脏位是1，需要写回ram
                            if(cache.valid_array[index] == 1 && cache.tag_array[index]!= tag && cache.dirty_array[index] == 1)
                                begin
                                    
                                    ram.ram[{cache.tag_array[index],index}] = cache.cache[index];
                                end
							cache.valid_array[index] = 1;
							cache.tag_array[index] = tag;
                            cache.dirty_array[index] =0; // read:0
							cache.cache[index] = ram.ram[prev_address];
						end
					// read data
					temp_out = cache.cache[index];
				end
		end
end

assign out = (mode == 1'b1) ? 32'hxxxxxxxx:temp_out;

endmodule 



// 测试
module testbench;

reg [31:0] address, data;
reg mode, clk;
wire [31:0] out;

cache_and_ram tb(
	.address(address),
	.data(data),
	.mode(mode),
	.clk(clk),
	.out(out)
);

initial
begin
	clk = 1'b1;
	
	address = 32'b00000000000000000000000000000000;			// 0        //cache miss,cache.cache[0] = 14528,ram.ram[0]=non
	data =    32'b00000000000000000011100011000000;			// 14528
	mode = 1'b1;
	
	#10
	address = 32'b10100111111001011111101111011100;			// 2816867292 % size = 3036  cache miss cache.cache[28] = 526421 ram.ram[3036]=non
	data =    32'b00000000000010000000100001010101;			// 526421
	mode = 1'b1;
	
	#10
	address = 32'b00000000000011110100011111010001;			// 1001425 % size = 2001   cache miss   cache.cache[17] = 25369366  ram.ram[2001]=non
	data =    32'b00000001100000110001101100010110;			// 25369366
	mode = 1'b1;

	#10
	address = 32'b10100111111001011111101111011100;			// 2816867292 % size = 3036   cache hit  cache.cache[28] =689  ram.ram[3036]=non  cache.dirty[28] = 1
	data =    32'b00000000000000000000001010110001;			// 2b1  689
	mode = 1'b1;

	#10
	address = 32'b00000000000011110100011111010001;			// 1001425 % size = 2001   cache hit   cache.cache[17] = 14528  ram.ram[2001]=non
	data =    32'b00000000000000000011100011000000;			// 14528
	mode = 1'b1;

	#10
	address = 32'b00000000000011110100011111010001;			// 47d1 % size = 2001   cache hit      read value should be 14528
	data =    32'b00000000000000000000000000000000;			// 0
	mode = 1'b0;
	
	#10
	address = 32'b10100111111001011111101111011100;			// fbdc % size = 3036  cache hit     read value should be 2b1
	data =    32'b00000000000000000000000000000000;			// 0
	mode = 1'b0;
		
	#10
	address = 32'b10100111111001011111101001011100;			// 2,816,866,908 % size = 2652  cache miss.  but cache.dirty[28] = 1 .so need writeBack，ram.ram[3036]= 689
	data =    32'b00000000000000000000000110100010;			// 01a2      cache.cache[28] = 418
	mode = 1'b1;                                            // 观察out的值是否是x

    	// #10
	// address = 32'b10100111111001011111101001011100;			// A7E5 fa5c % size = 2652  cache hit     read value should be 418
	// data =    32'b00000000000000000000000000000000;			// 0
	// mode = 1'b0;                                            // 观察是否是01a2
    
    	#10
    	address = 32'b10100111111001011111101111011100;			// 2816867292 % size = 3036  cache miss   write allocate  read value should be ram.ram[3036] =02b1
	data =    32'b00000000000000000000000000000000;			// 0
	mode = 1'b0;                                            //观察读出的值是否是02b1
end

initial
$monitor("address = %d data = %d mode = %d out = %d", address % 4096, data, mode, out);

always #2 clk = ~clk;

endmodule 
