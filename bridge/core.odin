package bridge

import mu "vendor:microui"

muContext: mu.Context

UpdateContext :: struct {
	dt:        f64,
	muContext: ^mu.Context,
}
