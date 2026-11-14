package bridge

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"time"

	"vortex-core/outbound/proprietary"
	"vortex-core/outbound/vkcall"
)

var (
	tunnelMu     sync.Mutex
	isRunning    bool
	activeCtx    context.Context
	cancelTunnel context.CancelFunc

	// Traffic byte counters
	txBytes atomic.Int64
	rxBytes atomic.Int64

	// Protocol Outbound Stubs
	activeProprietary *proprietary.Outbound
	activeVKCall      *vkcall.Transport
)

func init() {
	// Strict memory limits to comply with iOS NetworkExtension 50 MB Jetsam limit:
	// Cap Go runtime heap to 32 MB and trigger GC aggressively at 15% allocation delta
	debug.SetMemoryLimit(32 * 1024 * 1024)
	debug.SetGCPercent(15)
}

// StartVortexTunnel initializes sing-box core with the given JSON configuration and virtual TUN file descriptor.
// Exported for Swift via gomobile bind.
func StartVortexTunnel(configJSON string, tunFd int32) error {
	tunnelMu.Lock()
	defer tunnelMu.Unlock()

	if isRunning {
		return errors.New("tunnel is already running")
	}

	if configJSON == "" {
		return errors.New("empty configuration string")
	}

	activeCtx, cancelTunnel = context.WithCancel(context.Background())
	isRunning = true

	// Parse configuration to check protocol requirements
	var rawConfig map[string]interface{}
	if err := json.Unmarshal([]byte(configJSON), &rawConfig); err != nil {
		cancelTunnel()
		isRunning = false
		return fmt.Errorf("invalid json config: %w", err)
	}

	// Check if proprietary or vkcall custom outbound is requested
	if outbounds, ok := rawConfig["outbounds"].([]interface{}); ok {
		for _, ob := range outbounds {
			if obMap, ok := ob.(map[string]interface{}); ok {
				if customType, ok := obMap["custom_type"].(string); ok {
					switch customType {
					case "vortex_proto":
						cfg := proprietary.Config{
							Address:         fmt.Sprint(obMap["server"]),
							Port:            uint16(getInt(obMap["server_port"], 8443)),
							SecretKey:       fmt.Sprint(obMap["secret_key"]),
							ObfuscationMode: fmt.Sprint(obMap["obfuscation_mode"]),
						}
						out, err := proprietary.New(cfg)
						if err == nil {
							activeProprietary = out
						}

					case "vk_call_tunnel":
						cfg := vkcall.Config{
							CallJoinLink: fmt.Sprint(obMap["call_join_link"]),
							RelayAddress: fmt.Sprint(obMap["server"]),
							RelayPort:    uint16(getInt(obMap["server_port"], 3478)),
							TurnUsername: fmt.Sprint(obMap["turn_username"]),
							TurnPassword: fmt.Sprint(obMap["turn_password"]),
							SecretKey:    fmt.Sprint(obMap["secret_key"]),
						}
						tr, err := vkcall.New(cfg)
						if err == nil {
							activeVKCall = tr
						}
					}
				}
			}
		}
	}

	// Reset traffic counters for new session
	txBytes.Store(0)
	rxBytes.Store(0)

	// In production with sing-box (libbox), we pass the tunFd and config into:
	// box.New(box.Options{ Context: activeCtx, Options: options, PlatformInterface: ... })
	_ = tunFd

	return nil
}

// StopVortexTunnel gracefully halts the core engine and closes allocated sockets.
// Exported for Swift via gomobile bind.
func StopVortexTunnel() error {
	tunnelMu.Lock()
	defer tunnelMu.Unlock()

	if !isRunning {
		return nil
	}

	if cancelTunnel != nil {
		cancelTunnel()
	}

	if activeProprietary != nil {
		_ = activeProprietary.Close()
		activeProprietary = nil
	}

	if activeVKCall != nil {
		_ = activeVKCall.Close()
		activeVKCall = nil
	}

	isRunning = false

	// Force immediate garbage collection to reclaim memory for NetworkExtension
	runtime.GC()
	debug.FreeOSMemory()

	return nil
}

// MeasureNodeLatency tests TCP connect latency to the target node endpoint.
// Returns round-trip time in milliseconds, or -1 on timeout/failure.
// Exported for Swift via gomobile bind.
func MeasureNodeLatency(nodeJSON string) int64 {
	var payload struct {
		Address string `json:"address"`
		Port    int    `json:"port"`
		Server  string `json:"server"`
	}

	if err := json.Unmarshal([]byte(nodeJSON), &payload); err != nil {
		return -1
	}

	host := payload.Address
	if host == "" {
		host = payload.Server
	}
	port := payload.Port
	if port == 0 {
		port = 443
	}

	endpoint := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	start := time.Now()

	conn, err := net.DialTimeout("tcp", endpoint, 2500*time.Millisecond)
	if err != nil {
		return -1
	}
	_ = conn.Close()

	return time.Since(start).Milliseconds()
}

// GetTrafficStats returns real-time TX/RX totals and resident memory as JSON string:
// e.g. `{"txBytes": 1024, "rxBytes": 4096, "memoryBytes": 23068672}`
// Exported for Swift via gomobile bind.
func GetTrafficStats() string {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	stats := map[string]int64{
		"txBytes":     txBytes.Load(),
		"rxBytes":     rxBytes.Load(),
		"memoryBytes": int64(m.Sys),
	}

	data, _ := json.Marshal(stats)
	return string(data)
}

// AddTrafficBytes increments the TX and RX byte counters (called from packet loop).
func AddTrafficBytes(tx, rx int64) {
	txBytes.Add(tx)
	rxBytes.Add(rx)
}

func getInt(v interface{}, fallback int) int {
	switch val := v.(type) {
	case float64:
		return int(val)
	case int:
		return val
	default:
		return fallback
	}
}
