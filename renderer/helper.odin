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
