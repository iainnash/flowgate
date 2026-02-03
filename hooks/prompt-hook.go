package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// HookInput is the input from Claude Code hook
type HookInput struct {
	SessionID     string                 `json:"sessionId"`
	ToolName      string                 `json:"toolName"`
	ToolInput     map[string]interface{} `json:"toolInput"`
	HookEventName string                 `json:"hookEventName"`
	CWD           string                 `json:"cwd"`
}

// ServerResponse is the response from the server
type ServerResponse struct {
	Decision     string                 `json:"decision"` // "allow" | "deny" | "ask"
	Reason       *string                `json:"reason,omitempty"`
	UpdatedInput map[string]interface{} `json:"updatedInput,omitempty"`
}

// HookOutput is the output that Claude Code expects
type HookOutput struct {
	HookSpecificOutput HookSpecificOutput `json:"hookSpecificOutput"`
}

type HookSpecificOutput struct {
	HookEventName             string                 `json:"hookEventName"`
	PermissionDecision        string                 `json:"permissionDecision"` // "allow" | "deny" | "ask"
	PermissionDecisionReason  *string                `json:"permissionDecisionReason,omitempty"`
	UpdatedInput              map[string]interface{} `json:"updatedInput,omitempty"`
}

var (
	serverURL = getEnv("CLAUDE_PROMPT_UI_SERVER", "http://127.0.0.1:8888")
	timeoutMS = getEnvInt("CLAUDE_PROMPT_UI_TIMEOUT", 120000)
)

// readTokenFromFile reads auth token from the app directory
func readTokenFromFile() string {
	// Try environment variable first
	if token := os.Getenv("CLAUDE_PROMPT_UI_TOKEN"); token != "" {
		return token
	}

	// Read from ~/.claude-prompt-ui/token
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	tokenPath := filepath.Join(homeDir, ".claude-prompt-ui", "token")
	tokenBytes, err := os.ReadFile(tokenPath)
	if err != nil {
		return ""
	}

	return strings.TrimSpace(string(tokenBytes))
}

func main() {
	// Read stdin
	inputData, err := io.ReadAll(os.Stdin)
	if err != nil {
		fallbackToTerminal("Failed to read stdin")
		return
	}

	// Parse input with snake_case (from Claude Code) and convert to camelCase
	var snakeInput struct {
		SessionID     string                 `json:"session_id"`
		ToolName      string                 `json:"tool_name"`
		ToolInput     map[string]interface{} `json:"tool_input"`
		HookEventName string                 `json:"hook_event_name"`
		CWD           string                 `json:"cwd"`
	}

	if err := json.Unmarshal(inputData, &snakeInput); err != nil {
		fallbackToTerminal("Failed to parse hook input")
		return
	}

	// Convert to camelCase for server
	input := HookInput{
		SessionID:     snakeInput.SessionID,
		ToolName:      snakeInput.ToolName,
		ToolInput:     snakeInput.ToolInput,
		HookEventName: snakeInput.HookEventName,
		CWD:           snakeInput.CWD,
	}

	// Send to server
	decision, err := sendToServer(&input)
	if err != nil {
		// Server is down or unreachable - silently allow to avoid blocking Claude Code
		silentPassthrough()
		return
	}

	// Output decision
	outputDecision(decision)
}

func sendToServer(input *HookInput) (*ServerResponse, error) {
	// Marshal input
	inputJSON, err := json.Marshal(input)
	if err != nil {
		return nil, err
	}

	// Create request
	req, err := http.NewRequest("POST", serverURL+"/api/prompt", bytes.NewBuffer(inputJSON))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")

	// Add auth token from file or environment
	if authToken := readTokenFromFile(); authToken != "" {
		req.Header.Set("Authorization", "Bearer "+authToken)
	}

	// Send request
	client := &http.Client{
		Timeout: time.Duration(timeoutMS) * time.Millisecond,
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("server returned %d", resp.StatusCode)
	}

	// Parse response
	var result ServerResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	return &result, nil
}

func outputDecision(result *ServerResponse) {
	switch result.Decision {
	case "allow":
		output(HookOutput{
			HookSpecificOutput: HookSpecificOutput{
				HookEventName:      "PreToolUse",
				PermissionDecision: "allow",
				UpdatedInput:       result.UpdatedInput,
			},
		})
	case "deny":
		reason := "Denied by user"
		if result.Reason != nil {
			reason = *result.Reason
		}
		output(HookOutput{
			HookSpecificOutput: HookSpecificOutput{
				HookEventName:            "PreToolUse",
				PermissionDecision:       "deny",
				PermissionDecisionReason: &reason,
			},
		})
	default: // "ask"
		fallbackToTerminal("User chose to decide in terminal")
	}
}

func output(data HookOutput) {
	enc := json.NewEncoder(os.Stdout)
	enc.Encode(data)
}

func fallbackToTerminal(reason string) {
	output(HookOutput{
		HookSpecificOutput: HookSpecificOutput{
			HookEventName:            "PreToolUse",
			PermissionDecision:       "ask",
			PermissionDecisionReason: &reason,
		},
	})
}

func silentPassthrough() {
	output(HookOutput{
		HookSpecificOutput: HookSpecificOutput{
			HookEventName:      "PreToolUse",
			PermissionDecision: "allow",
		},
	})
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var result int
		if _, err := fmt.Sscanf(value, "%d", &result); err == nil {
			return result
		}
	}
	return defaultValue
}
