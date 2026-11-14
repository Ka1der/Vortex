package proprietary

import (
	"context"
	"crypto/cipher"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"
)

// Config defines the connection and cryptographic parameters for the Proprietary protocol.
type Config struct {
	Address         string            `json:"server"`
	Port            uint16            `json:"server_port"`
	SecretKey       string            `json:"secret_key"`
	ObfuscationMode string            `json:"obfuscation_mode"` // "udp-mask", "tls-mimic", "raw"
	ExtraParams     map[string]string `json:"extra"`
}

// Outbound implements the outbound adapter for the Vortex proprietary protocol.
type Outbound struct {
	config Config
	aead   cipher.AEAD
	mu     sync.Mutex
	closed bool
}

// New creates a new proprietary outbound handler from configuration.
func New(config Config) (*Outbound, error) {
	if config.Address == "" {
		return nil, errors.New("proprietary outbound: server address is required")
	}
	if config.Port == 0 {
		return nil, errors.New("proprietary outbound: server port is required")
	}
	if config.SecretKey == "" {
		return nil, errors.New("proprietary outbound: secret key is required")
	}

	outbound := &Outbound{
		config: config,
	}

	// TODO(backend-spec): Derive cryptographic key using HKDF-SHA256 from config.SecretKey.
	// For example:
	//   salt := []byte("vortex-proprietary-proto-v1")
	//   key := hkdf.New(sha256.New, []byte(config.SecretKey), salt, nil)
	//   block, _ := chacha20poly1305.New(derivedKey)
	//   outbound.aead = block

	return outbound, nil
}

// Dial establishes a TCP stream connection through the proprietary tunnel.
func (o *Outbound) Dial(ctx context.Context, network, destination string) (net.Conn, error) {
	o.mu.Lock()
	if o.closed {
		o.mu.Unlock()
		return nil, errors.New("proprietary outbound: closed")
	}
	o.mu.Unlock()

	serverEndpoint := fmt.Sprintf("%s:%d", o.config.Address, o.config.Port)

	var dialer net.Dialer
	rawConn, err := dialer.DialContext(ctx, "tcp", serverEndpoint)
	if err != nil {
		return nil, fmt.Errorf("proprietary outbound dial failed: %w", err)
	}

	// TODO(backend-spec): Perform client handshake and capability exchange:
	// 1. Send encrypted handshake containing destination address, protocol version, and timestamp.
	// 2. Read server challenge/acknowledgement.
	// 3. Wrap connection in obfuscated stream framing (apply ObfuscationMode: udp-mask, tls-mimic).
	return rawConn, nil
}

// DialPacket establishes a UDP packet connection through the proprietary tunnel.
func (o *Outbound) DialPacket(ctx context.Context, destination string) (net.PacketConn, error) {
	o.mu.Lock()
	if o.closed {
		o.mu.Unlock()
		return nil, errors.New("proprietary outbound: closed")
	}
	o.mu.Unlock()

	serverEndpoint := fmt.Sprintf("%s:%d", o.config.Address, o.config.Port)

	// Resolve server address for UDP
	raddr, err := net.ResolveUDPAddr("udp", serverEndpoint)
	if err != nil {
		return nil, fmt.Errorf("proprietary outbound resolve UDP failed: %w", err)
	}

	conn, err := net.DialUDP("udp", nil, raddr)
	if err != nil {
		return nil, fmt.Errorf("proprietary outbound dial UDP failed: %w", err)
	}

	// TODO(backend-spec): Wrap net.UDPConn with packet framing and padding:
	// 1. Prepend obfuscation header (entropy-balanced mask to bypass heuristic DPI analyzers).
	// 2. Add randomized padding (0 to 64 bytes) to prevent packet size fingerprinting.
	// 3. Encrypt payload using ChaCha20-Poly1305 or AES-256-GCM.
	return conn, nil
}

// MeasureLatency measures TCP handshake round-trip latency to the server.
func (o *Outbound) MeasureLatency(ctx context.Context) (time.Duration, error) {
	start := time.Now()
	serverEndpoint := fmt.Sprintf("%s:%d", o.config.Address, o.config.Port)

	var dialer net.Dialer
	conn, err := dialer.DialContext(ctx, "tcp", serverEndpoint)
	if err != nil {
		return 0, err
	}
	_ = conn.Close()

	return time.Since(start), nil
}

// Close terminates active connections and releases resources.
func (o *Outbound) Close() error {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.closed = true
	return nil
}
