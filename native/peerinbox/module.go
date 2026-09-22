// SPDX-License-Identifier: MIT

// Package peerinbox is the one transport the Lua surface cannot express: a
// line-delimited JSON write to a managed Claude Code child's cross-session
// inbox, and the read of the status frame that harness answers with.
//
// It carries one message and reports what the harness said about it. It opens
// no store, starts nothing, interprets no thread state, and never retries: a
// second delivery of the same text is a decision the carrier makes against its
// durable queue row, not something this boundary may take on its own.
package peerinbox

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	lua "github.com/wippyai/go-lua"
	luaapi "github.com/wippyai/runtime/api/runtime/lua"
)

const (
	// MaxTextBytes matches the gateway inbox body bound.
	MaxTextBytes = 32768
	// MaxSocketBytes is the Unix socket path limit the harness itself enforces.
	MaxSocketBytes = 103
	MaxTokenBytes  = 4096
	// MaxPathBytes bounds the configuration directory Bee assigned the child.
	MaxPathBytes = 4096
	// MaxSessionBytes bounds one registry file read while finding the key.
	MaxSessionBytes = 65536
	// MaxLineBytes bounds one frame read back from the harness.
	MaxLineBytes      = 1 << 20
	DefaultTimeoutMS  = 2000
	MaxTimeoutMS      = 15000
	statusFrameType   = "peer_message_status"
	authFrameType     = "auth"
	userFrameType     = "user"
)

// Module exposes the boundary as require("peerinbox").
var Module = &luaapi.ModuleDef{
	Name: "peerinbox", Description: "Cross-session inbox delivery to a managed Claude Code child",
	Class: []string{luaapi.ClassIO, luaapi.ClassNondeterministic},
	Build: buildModule,
}

func buildModule() (*lua.LTable, []luaapi.YieldType) {
	module := lua.CreateTable(0, 1)
	module.RawSetString("deliver", lua.LGoFunc(deliver))
	module.Immutable = true
	return module, nil
}

type request struct {
	socket    string
	token     string
	configDir string
	text      string
	messageID string
	timeout   time.Duration
}

// tokenFor finds the inbox key the child published for exactly this socket.
//
// The directory is the one Bee assigned the child, and the socket is the one
// Bee told it to bind, so this reads Bee's own configuration rather than
// trusting a registry it does not own. A session entry naming a different
// socket belongs to a different child and is ignored. The token never leaves
// this boundary: it is read here and written to the connection, never handed
// back to the caller.
func tokenFor(configDir string, socket string) (string, error) {
	if configDir == "" {
		if projected := os.Getenv("CLAUDE_CONFIG_DIR"); projected != "" {
			configDir = projected
		} else {
			home, homeErr := os.UserHomeDir()
			if homeErr != nil {
				return "", fmt.Errorf("no configuration directory and no home: %w", homeErr)
			}
			configDir = filepath.Join(home, ".claude")
		}
	}
	sessions := filepath.Join(configDir, "sessions")
	entries, err := os.ReadDir(sessions)
	if err != nil {
		return "", fmt.Errorf("session registry unavailable: %w", err)
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".json") {
			continue
		}
		raw, readErr := os.ReadFile(filepath.Join(sessions, name))
		if readErr != nil || len(raw) > MaxSessionBytes {
			continue
		}
		var session struct {
			PID                  int64  `json:"pid"`
			MessagingSocketPath  string `json:"messagingSocketPath"`
		}
		if json.Unmarshal(raw, &session) != nil || session.MessagingSocketPath != socket {
			continue
		}
		prefix := strings.TrimSuffix(name, ".json") + "."
		for _, candidate := range entries {
			key := candidate.Name()
			if !strings.HasPrefix(key, prefix) || !strings.HasSuffix(key, ".key") {
				continue
			}
			keyRaw, keyErr := os.ReadFile(filepath.Join(sessions, key))
			if keyErr != nil || len(keyRaw) > MaxSessionBytes {
				continue
			}
			var published struct {
				PeerToken string `json:"peerToken"`
			}
			if json.Unmarshal(keyRaw, &published) != nil || published.PeerToken == "" {
				continue
			}
			return published.PeerToken, nil
		}
		return "", fmt.Errorf("the child published no inbox key for its socket")
	}
	return "", fmt.Errorf("no session in that directory binds this socket")
}

func stringField(table *lua.LTable, name string, limit int, required bool) (string, error) {
	raw := table.RawGetString(name)
	if raw == lua.LNil {
		if required {
			return "", fmt.Errorf("%s is required", name)
		}
		return "", nil
	}
	text, ok := raw.(lua.LString)
	if !ok {
		return "", fmt.Errorf("%s must be a string", name)
	}
	if required && len(text) == 0 {
		return "", fmt.Errorf("%s must not be empty", name)
	}
	if len(text) > limit {
		return "", fmt.Errorf("%s exceeds %d bytes", name, limit)
	}
	return string(text), nil
}

func decode(value lua.LValue) (*request, error) {
	table, ok := value.(*lua.LTable)
	if !ok {
		return nil, fmt.Errorf("deliver takes one table")
	}
	socket, err := stringField(table, "socket", MaxSocketBytes, true)
	if err != nil {
		return nil, err
	}
	token, err := stringField(table, "token", MaxTokenBytes, false)
	if err != nil {
		return nil, err
	}
	configDir, err := stringField(table, "config_dir", MaxPathBytes, false)
	if err != nil {
		return nil, err
	}

	text, err := stringField(table, "text", MaxTextBytes, true)
	if err != nil {
		return nil, err
	}
	messageID, err := stringField(table, "message_id", 160, false)
	if err != nil {
		return nil, err
	}
	timeout := time.Duration(DefaultTimeoutMS) * time.Millisecond
	if raw := table.RawGetString("timeout_ms"); raw != lua.LNil {
		number, ok := raw.(lua.LNumber)
		if !ok || number < 1 || number > MaxTimeoutMS {
			return nil, fmt.Errorf("timeout_ms must be between 1 and %d", MaxTimeoutMS)
		}
		timeout = time.Duration(number) * time.Millisecond
	}
	return &request{socket: socket, token: token, configDir: configDir, text: text, messageID: messageID, timeout: timeout}, nil
}

// answer is what the carrier settles its queue row on: accepted only when the
// harness itself said the message reached its session.
type answer struct {
	Accepted bool   `json:"accepted"`
	Status   string `json:"status"`
	Detail   string `json:"detail,omitempty"`
}

func result(state *lua.LState, value answer) int {
	table := lua.CreateTable(0, 3)
	table.RawSetString("accepted", lua.LBool(value.Accepted))
	table.RawSetString("status", lua.LString(value.Status))
	if value.Detail != "" {
		table.RawSetString("detail", lua.LString(value.Detail))
	}
	state.Push(table)
	return 1
}

func refuse(state *lua.LState, status string, detail string) int {
	return result(state, answer{Accepted: false, Status: status, Detail: detail})
}

func deliver(state *lua.LState) int {
	call, err := decode(state.Get(1))
	if err != nil {
		return refuse(state, "invalid", err.Error())
	}
	// A socket that is not a socket is a configuration fault, not a refusal by
	// the recipient; say so distinctly.
	info, statErr := os.Stat(call.socket)
	if statErr != nil {
		return refuse(state, "unreachable", statErr.Error())
	}
	if info.Mode()&os.ModeSocket == 0 {
		return refuse(state, "unreachable", "path is not a socket")
	}
	token := call.token
	if token == "" {
		published, tokenErr := tokenFor(call.configDir, call.socket)
		if tokenErr != nil {
			return refuse(state, "unreachable", tokenErr.Error())
		}
		token = published
	}
	deadline := time.Now().Add(call.timeout)
	connection, dialErr := net.DialTimeout("unix", call.socket, call.timeout)
	if dialErr != nil {
		return refuse(state, "unreachable", dialErr.Error())
	}
	defer func() { _ = connection.Close() }()
	if err := connection.SetDeadline(deadline); err != nil {
		return refuse(state, "unreachable", err.Error())
	}

	auth, _ := json.Marshal(map[string]string{"type": authFrameType, "token": token})
	message := map[string]any{"role": "user", "content": call.text}
	frame := map[string]any{"type": userFrameType, "message": message}
	if call.messageID != "" {
		frame["msg_id"] = call.messageID
	}
	user, marshalErr := json.Marshal(frame)
	if marshalErr != nil {
		return refuse(state, "invalid", marshalErr.Error())
	}
	if _, err := connection.Write(append(auth, '\n')); err != nil {
		return refuse(state, "unreachable", err.Error())
	}
	if _, err := connection.Write(append(user, '\n')); err != nil {
		// The auth line landed and the message may not have; the carrier's
		// dispatch intent already recorded that bytes could have left.
		return refuse(state, "uncertain", err.Error())
	}

	// The harness answers a status frame when it has one. Silence is not a
	// refusal and not an acceptance: it is uncertainty, and the caller must
	// treat it as such.
	reader := bufio.NewReaderSize(connection, 4096)
	for {
		line, readErr := reader.ReadString('\n')
		if len(line) > MaxLineBytes {
			return refuse(state, "uncertain", "status frame exceeded the line bound")
		}
		if trimmed := trimFrame(line); trimmed != "" {
			var decoded map[string]any
			if json.Unmarshal([]byte(trimmed), &decoded) == nil {
				if kind, _ := decoded["type"].(string); kind == statusFrameType {
					return status(state, decoded)
				}
			}
		}
		if readErr != nil {
			return refuse(state, "uncertain", "no status frame: "+readErr.Error())
		}
		if time.Now().After(deadline) {
			return refuse(state, "uncertain", "no status frame before the deadline")
		}
	}
}

func trimFrame(line string) string {
	for len(line) > 0 && (line[len(line)-1] == '\n' || line[len(line)-1] == '\r') {
		line = line[:len(line)-1]
	}
	return line
}

// status maps the harness's own words onto the queue's outcomes. Anything the
// frame does not say is left unsaid rather than guessed.
func status(state *lua.LState, frame map[string]any) int {
	if dropped, ok := frame["drop_reason"].(string); ok && dropped != "" {
		return refuse(state, "refused", dropped)
	}
	if held, ok := frame["wereHeld"].(bool); ok && held {
		return refuse(state, "held", "the recipient user must approve the message")
	}
	if held, ok := frame["wasHeld"].(bool); ok && held {
		return refuse(state, "held", "the recipient user must approve the message")
	}
	if dropped, ok := frame["dropped"].(bool); ok && dropped {
		return refuse(state, "refused", "the recipient dropped the message at its inbox")
	}
	raw, marshalErr := json.Marshal(frame)
	if marshalErr != nil {
		return result(state, answer{Accepted: true, Status: "delivered"})
	}
	return result(state, answer{Accepted: true, Status: "delivered", Detail: string(raw)})
}
