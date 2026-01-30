package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"github.com/iain/claude-prompt-ui/handlers"
	"github.com/iain/claude-prompt-ui/models"
	"github.com/iain/claude-prompt-ui/queue"
	"github.com/rs/cors"
)

var (
	host    = "127.0.0.1"
	port    = getEnv("PORT", "8888")
	verbose = getEnv("VERBOSE", "") == "true" || getEnv("VERBOSE", "") == "1"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for now
	},
}

func main() {
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

	// API routes
	r.HandleFunc("/api/prompt", makePromptHandler(q)).Methods("POST")
	r.HandleFunc("/api/health", healthHandler).Methods("GET")
	r.HandleFunc("/ws", makeWebSocketHandler(hub)).Methods("GET")

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
	// Check current directory
	if _, err := os.Stat("public"); err == nil {
		return "public"
	}

	// Check parent directory
	if _, err := os.Stat("../server/public"); err == nil {
		return "../server/public"
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
