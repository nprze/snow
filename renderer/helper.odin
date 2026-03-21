package renderer

import fmt "core:fmt"
import os "core:os"
import d3d12 "vendor:directx/d3d12"

check :: proc(res: d3d12.HRESULT, message: string) {
	if (res >= 0) {
		return
	}
	fmt.printf("%v. Error code: %0x\n", message, u32(res))
	os.exit(-1)
}

read_file :: proc(path: string) -> cstring {
	data_slice, ok := os.read_entire_file(path)
	if !ok {
		panic("Failed to read file")
	}
	data := make([]u8, len(data_slice) + 1)
	copy(data, data_slice)
	data[len(data_slice)] = 0
	return cstring(&data[0])
}
