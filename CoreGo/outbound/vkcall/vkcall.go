package vkcall

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"
)

// Config defines the parameters required to connect through a VK Calls TURN/WebRTC relay.
type Config struct {
	CallJoinLink string `json:"call_join_link"` // e.g. "https://vk.com/call/join/call_id"
	RelayAddress string `json:"server"`         // TURN relay server host (e.g. "turn.vk.com")
	RelayPort    uint16 `json:"server_port"`    // TURN relay port (e.g. 3478)
	TurnUsername string `json:"turn_username"`  // Allocated ephemeral TURN credentials
	TurnPassword string `json:"turn_password"`
	SecretKey    string `json:"secret_key"`
}

// Transport encapsulates the STUN/TURN channel allocation and packet tunneling.
type Transport struct {
	config Config
	mu     sync.Mutex
	closed bool
}

// New creates a new VK Call transport handler.
func New(config Config) (*Transport, error) {
	if config.RelayAddress == "" {
		return nil, errors.New("vkcall: relay address is required")
	}
	if config.RelayPort == 0 {
		return nil, errors.New("vkcall: relay port is required")
	}

	return &Transport{
		config: config,
	}, nil
}

// DialContext establishes a stream connection tunneled over the VK Call TURN relay.
func (t *Transport) DialContext(ctx context.Context, network, destination string) (net.Conn, error) {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return nil, errors.New("vkcall transport: closed")
	}
	t.mu.Unlock()

	relayEndpoint := fmt.Sprintf("%s:%d", t.config.RelayAddress, t.config.RelayPort)

	var dialer net.Dialer
	rawConn, err := dialer.DialContext(ctx, "udp", relayEndpoint)
	if err != nil {
		return nil, fmt.Errorf("vkcall: dial relay failed: %w", err)
	}

	// TODO(backend-spec): Implement STUN/TURN allocation and WebRTC DataChannel framing:
	// 1. Send STUN Allocate request (RFC 5766) to relay with MESSAGE-INTEGRITY using config.TurnPassword.
	// 2. Receive TURN Allocate Success response and allocate a ChannelNumber (0x4000).
	// 3. Establish simulated WebRTC DataChannel / SCTP association over DTLS.
	// 4. Return framed net.Conn wrapper handling TURN ChannelData encapsulation.

	return rawConn, nil
}

// DialPacket creates a UDP packet connection encapsulated in TURN ChannelData frames.
func (t *Transport) DialPacket(ctx context.Context, destination string) (net.PacketConn, error) {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return nil, errors.New("vkcall transport: closed")
	}
	t.mu.Unlock()

	relayEndpoint := fmt.Sprintf("%s:%d", t.config.RelayAddress, t.config.RelayPort)
	raddr, err := net.ResolveUDPAddr("udp", relayEndpoint)
	if err != nil {
		return nil, fmt.Errorf("vkcall: resolve relay address failed: %w", err)
	}

	conn, err := net.DialUDP("udp", nil, raddr)
	if err != nil {
		return nil, fmt.Errorf("vkcall: dial UDP relay failed: %w", err)
	}

	// TODO(backend-spec): Packet encapsulation for WebRTC TURN relay:
	// 1. Frame packets with 4-byte TURN ChannelData header:
	//      0                   1                   2                   3
	//      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
	//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	//     |         Channel Number        |            Length             |
	//     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
	// 2. Prepend simulated RTP header or Opus audio frame header to mimic legitimate VK voice data.
	// 3. Enforce MTU ceiling of 1280 to prevent IP fragmentation at intermediate cellular routers.

	return conn, nil
}

// MeasureLatency measures round-trip time to the VK TURN relay server.
func (t *Transport) MeasureLatency(ctx context.Context) (time.Duration, error) {
	start := time.Now()
	relayEndpoint := fmt.Sprintf("%s:%d", t.config.RelayAddress, t.config.RelayPort)

	var dialer net.Dialer
	conn, err := dialer.DialContext(ctx, "udp", relayEndpoint)
	if err != nil {
		return 0, err
	}
	_ = conn.Close()

	return time.Since(start), nil
}

// Close terminates the transport and cleans up channel allocations.
func (t *Transport) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.closed = true
	return nil
}
