// SPDX-License-Identifier: MIT

package peerinbox

import (
	"context"
	"fmt"

	"github.com/wippyai/runtime/api/boot"
	luaboot "github.com/wippyai/runtime/boot/components/runtime/lua"
)

// Component installs the cross-session inbox delivery module. It holds no
// state: every call opens its own connection and closes it.
func Component() boot.Component {
	return boot.New(boot.P{
		Name: "bee.peerinbox", DependsOn: []boot.Name{luaboot.EngineName},
		Load: func(ctx context.Context) (context.Context, error) {
			code := luaboot.GetCodeManager(ctx)
			if code == nil {
				return ctx, fmt.Errorf("peer inbox delivery requires Lua")
			}
			return ctx, luaboot.AddModules(ctx, code, Module)
		},
	})
}
