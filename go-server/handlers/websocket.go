package handlers

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/iain/claude-prompt-ui/models"
	"github.com/iain/claude-prompt-ui/queue"
)

// Hub manages WebSocket connections and broadcasts
type Hub struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	queue      *queue.Queue
	mu         sync.RWMutex
	verbose    bool
	isPaused   bool
}

// Client represents a WebSocket connection
type Client struct {
	hub  *Hub
	conn *websocket.Conn
	send chan []byte
}

// NewHub creates a new WebSocket hub
func NewHub(q *queue.Queue, verbose bool) *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		queue:      q,
		verbose:    verbose,
	}
}

// log prints debug output if verbose mode is enabled
func (h *Hub) log(format string, args ...interface{}) {
	if h.verbose {
		log.Printf("[Hub] "+format, args...)
	}
}

// Run starts the hub's main loop
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			h.log("Client connected - total: %d", len(h.clients))

			// Send initial state
			h.sendToClient(client, "prompts:list", map[string]interface{}{
				"prompts": h.queue.List(),
			})
			h.sendToClient(client, "pause:changed", map[string]interface{}{
				"isPaused": h.isPaused,
			})
			h.sendToClient(client, "settings:updated", map[string]interface{}{
				"settings": h.queue.GetSettings(),
			})

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
			}
			h.mu.Unlock()
			h.log("Client disconnected - total: %d", len(h.clients))

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.send <- message:
				default:
					close(client.send)
					delete(h.clients, client)
				}
			}
			h.mu.RUnlock()
		}
	}
}

// Broadcast sends a message to all connected clients
func (h *Hub) Broadcast(msgType string, payload interface{}) {
	msg, err := models.MarshalWSMessage(msgType, payload)
	if err != nil {
		log.Printf("Error marshaling message: %v", err)
		return
	}
	h.log("Broadcasting: %s to %d clients", msgType, len(h.clients))
	h.broadcast <- msg
}

// sendToClient sends a message to a specific client
func (h *Hub) sendToClient(client *Client, msgType string, payload interface{}) {
	msg, err := models.MarshalWSMessage(msgType, payload)
	if err != nil {
		log.Printf("Error marshaling message: %v", err)
		return
	}
	select {
	case client.send <- msg:
	default:
	}
}

// HandleClientMessage processes incoming WebSocket messages
func (h *Hub) HandleClientMessage(client *Client, messageType int, data []byte) {
	if messageType != websocket.TextMessage {
		return
	}

	var msg map[string]interface{}
	if err := json.Unmarshal(data, &msg); err != nil {
		h.log("Error parsing message: %v", err)
		return
	}

	msgType, ok := msg["type"].(string)
	if !ok {
		h.log("Message missing type field")
		return
	}

	h.log("Received message: %s", msgType)

	switch msgType {
	case "resolve":
		h.handleResolve(msg)

	case "resolve-all":
		h.handleResolveAll(msg)

	case "pause":
		h.handlePauseTimer(msg)

	case "toggle-pause":
		h.handleTogglePause()

	case "togglePause":
		h.handleTogglePause()

	case "updateSettings":
		h.handleUpdateSettings(msg)

	default:
		h.log("Unknown message type: %s", msgType)
	}
}

// handleResolve resolves a prompt
func (h *Hub) handleResolve(msg map[string]interface{}) {
	id, ok := msg["id"].(string)
	if !ok {
		return
	}

	decisionMap, ok := msg["decision"].(map[string]interface{})
	if !ok {
		return
	}

	decision := &models.Decision{}
	decisionJSON, _ := json.Marshal(decisionMap)
	json.Unmarshal(decisionJSON, decision)

	if !decision.IsValid() {
		return
	}

	h.queue.Resolve(id, decision, false)
}

// handleResolveAll resolves all prompts with the same decision
func (h *Hub) handleResolveAll(msg map[string]interface{}) {
	decisionStr, ok := msg["resolveDecision"].(string)
	if !ok {
		h.log("resolve-all missing resolveDecision field")
		return
	}

	decision := &models.Decision{
		Decision: decisionStr,
	}

	if !decision.IsValid() {
		h.log("resolve-all invalid decision: %s", decisionStr)
		return
	}

	// Resolve all pending prompts
	prompts := h.queue.List()
	h.log("Resolving all %d prompts with decision: %s", len(prompts), decisionStr)
	for _, prompt := range prompts {
		h.queue.Resolve(prompt.ID, decision, false)
	}
}

// handlePauseTimer pauses a specific prompt's timer
func (h *Hub) handlePauseTimer(msg map[string]interface{}) {
	// Note: Individual timer pause not yet implemented in queue
	// Could add if needed
	h.log("Individual timer pause not yet implemented")
}

// handleTogglePause toggles global pause state
func (h *Hub) handleTogglePause() {
	h.isPaused = !h.isPaused
	h.queue.SetPaused(h.isPaused)
	h.Broadcast("pause:changed", map[string]interface{}{
		"isPaused": h.isPaused,
	})
}

// handleUpdateSettings updates settings
func (h *Hub) handleUpdateSettings(msg map[string]interface{}) {
	settingsMap, ok := msg["settings"].(map[string]interface{})
	if !ok {
		return
	}

	settings := &models.Settings{}
	settingsJSON, _ := json.Marshal(settingsMap)
	json.Unmarshal(settingsJSON, settings)

	updated := h.queue.UpdateSettings(settings)
	h.Broadcast("settings:updated", map[string]interface{}{
		"settings": updated,
	})
}

// Read pumps messages from the websocket connection to the hub
func (c *Client) Read() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		messageType, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		c.hub.HandleClientMessage(c, messageType, message)
	}
}

// Write pumps messages from the hub to the websocket connection
func (c *Client) Write() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// NewClient creates a new WebSocket client
func (h *Hub) NewClient(conn *websocket.Conn) *Client {
	return &Client{
		hub:  h,
		conn: conn,
		send: make(chan []byte, 256),
	}
}

// RegisterClient registers a new client with the hub
func (h *Hub) RegisterClient(client *Client) {
	h.register <- client
}
