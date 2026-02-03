package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"github.com/iain/claude-prompt-ui/handlers"
	"github.com/iain/claude-prompt-ui/middleware"
	"github.com/iain/claude-prompt-ui/models"
	"github.com/iain/claude-prompt-ui/queue"
	"github.com/rs/cors"
)

var (
	host      = "127.0.0.1"
	port      = getEnv("PORT", "8888")
	verbose   = getEnv("VERBOSE", "") == "true" || getEnv("VERBOSE", "") == "1"
	authToken = "" // Will be loaded/generated
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// Allow no origin (direct WebSocket clients)
		if origin == "" {
			return true
		}
		// Allow file:// origins (native app WebView)
		if strings.HasPrefix(origin, "file://") {
			return true
		}
		// Parse origin URL and check hostname
		u, err := url.Parse(origin)
		if err != nil {
			log.Printf("[WARN] WebSocket origin parse error: %s", origin)
			return false
		}
		hostname := u.Hostname()
		allowed := hostname == "localhost" || hostname == "127.0.0.1"
		if !allowed {
			log.Printf("[WARN] WebSocket origin rejected: %s (hostname: %s)", origin, hostname)
		}
		return allowed
	},
}

func getTokenPath() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Fatal("Cannot determine home directory")
	}
	return filepath.Join(homeDir, ".claude-prompt-ui", "token")
}

func ensureTokenExists() string {
	tokenPath := getTokenPath()

	// Create directory if it doesn't exist
	dir := filepath.Dir(tokenPath)
	if err := os.MkdirAll(dir, 0700); err != nil {
		log.Fatal("Cannot create token directory:", err)
	}

	// Check if token file exists
	if data, err := os.ReadFile(tokenPath); err == nil {
		token := strings.TrimSpace(string(data))
		if token != "" {
			return token
		}
	}

	// Generate new token
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		log.Fatal("Cannot generate token:", err)
	}
	token := base64.URLEncoding.EncodeToString(tokenBytes)

	// Save token with restricted permissions (0600 - owner read/write only)
	if err := os.WriteFile(tokenPath, []byte(token), 0600); err != nil {
		log.Fatal("Cannot save token:", err)
	}

	logInfo("Generated new authentication token at: %s", tokenPath)
	return token
}

func main() {
	// Load or generate authentication token
	authToken = ensureTokenExists()
	logInfo("Authentication enabled")
	// Create queue
	q := queue.New(verbose)

	// Create WebSocket hub
	hub := handlers.NewHub(q, verbose)

	// Set up queue callbacks to broadcast to clients
	q.SetCallbacks(&queue.Callbacks{
		OnPromptAdded: func(prompt *models.Prompt) {
			hub.Broadcast("prompt:new", map[string]interface{}{
				"prompt": prompt,
			})
		},
		OnPromptResolved: func(id string, autoAccepted bool) {
			hub.Broadcast("prompt:resolved", map[string]interface{}{
				"id":           id,
				"autoAccepted": autoAccepted,
			})
		},
		OnPromptUpdated: func(prompt *models.Prompt) {
			hub.Broadcast("prompt:updated", map[string]interface{}{
				"prompt": prompt,
			})
		},
	})

	// Start hub
	go hub.Run()

	// Create router
	r := mux.NewRouter()

	// Protected routes
	authMw := middleware.AuthMiddleware(authToken)
	r.Handle("/api/prompt", authMw(http.HandlerFunc(makePromptHandler(q)))).Methods("POST")
	r.Handle("/ws", authMw(http.HandlerFunc(makeWebSocketHandler(hub)))).Methods("GET")

	// Public routes (no auth needed)
	r.HandleFunc("/api/health", healthHandler).Methods("GET")

	// Serve static files if public directory exists
	publicDir := findPublicDir()
	if publicDir != "" {
		logInfo("Serving static files from: %s", publicDir)
		fs := http.FileServer(http.Dir(publicDir))
		r.PathPrefix("/").Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Try to serve file, fallback to index.html for SPA
			path := filepath.Join(publicDir, r.URL.Path)
			if _, err := os.Stat(path); os.IsNotExist(err) {
				http.ServeFile(w, r, filepath.Join(publicDir, "index.html"))
				return
			}
			fs.ServeHTTP(w, r)
		}))
	}

	// CORS
	c := cors.New(cors.Options{
		AllowedOrigins:   []string{"http://localhost:*", "http://127.0.0.1:*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"*"},
		AllowCredentials: true,
	})

	handler := c.Handler(r)

	// Start server
	addr := fmt.Sprintf("%s:%s", host, port)
	logInfo("Server starting at http://%s", addr)
	logInfo("WebSocket at ws://%s/ws", addr)

	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatal(err)
	}
}

// makePromptHandler creates the hook endpoint handler
func makePromptHandler(q *queue.Queue) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		logVerbose("POST /api/prompt")

		var input models.HookInput
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			logVerbose("Invalid hook input: %v", err)
			http.Error(w, "Invalid hook input", http.StatusBadRequest)
			return
		}

		// Normalize field names (support both camelCase and snake_case)
		input.Normalize()

		// Validate required fields
		if input.SessionID == "" || input.ToolName == "" || input.HookEventName == "" || input.CWD == "" {
			logVerbose("Missing required fields")
			http.Error(w, "Missing required fields", http.StatusBadRequest)
			return
		}

		logVerbose("Processing: %s (session: %s)", input.ToolName, input.SessionID)

		// This blocks until resolved
		decision, err := q.Add(&input)
		if err != nil {
			logVerbose("Error processing prompt: %v", err)
			http.Error(w, "Failed to process prompt", http.StatusInternalServerError)
			return
		}

		logVerbose("Decision: %s", decision.Decision)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(decision)
	}
}

// makeWebSocketHandler creates the WebSocket endpoint handler
func makeWebSocketHandler(hub *handlers.Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("WebSocket upgrade error:", err)
			return
		}

		client := hub.NewClient(conn)
		hub.RegisterClient(client)

		go client.Write()
		go client.Read()
	}
}

// healthHandler returns server health status
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "ok",
		"time":   time.Now().Unix(),
	})
}

// findPublicDir locates the public directory
func findPublicDir() string {
	// Check current directory (when running from go-server/)
	if _, err := os.Stat("public"); err == nil {
		return "public"
	}

	// Check go-server subdirectory (when running from project root)
	if _, err := os.Stat("go-server/public"); err == nil {
		return "go-server/public"
	}

	// Check ui build output (alternative location)
	if _, err := os.Stat("ui/dist"); err == nil {
		return "ui/dist"
	}

	return ""
}

// Helper functions
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func logInfo(format string, args ...interface{}) {
	log.Printf("[INFO] "+format, args...)
}

func logVerbose(format string, args ...interface{}) {
	if verbose {
		log.Printf("[%s] %s", time.Now().Format(time.RFC3339), fmt.Sprintf(format, args...))
	}
}
