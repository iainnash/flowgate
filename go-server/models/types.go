package models

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// PromptAcceptType defines how a prompt should be accepted
type PromptAcceptType string

const (
	AcceptTypeAutoAccept  PromptAcceptType = "auto-accept"
	AcceptTypeAcceptAfter PromptAcceptType = "accept-after"
	AcceptTypeManual      PromptAcceptType = "manual"
)

// Prompt represents a tool use prompt waiting for user decision
type Prompt struct {
	ID            string                 `json:"id"`
	SessionID     string                 `json:"sessionId"`
	ToolName      string                 `json:"toolName"`
	ToolInput     map[string]interface{} `json:"toolInput"`
	HookEventName string                 `json:"hookEventName"`
	CWD           string                 `json:"cwd"`
	CreatedAt     int64                  `json:"createdAt"` // milliseconds
	AcceptType    PromptAcceptType       `json:"acceptType"`
	AutoAcceptIn  *int                   `json:"autoAcceptIn,omitempty"` // seconds
	AutoAcceptAt  *int64                 `json:"autoAcceptAt,omitempty"` // milliseconds
}

// HookInput is the input from Claude Code hook
// Supports both camelCase (from Go hook) and snake_case (from TS hook) for compatibility
type HookInput struct {
	SessionID     string                 `json:"sessionId"`
	ToolName      string                 `json:"toolName"`
	ToolInput     map[string]interface{} `json:"toolInput"`
	HookEventName string                 `json:"hookEventName"`
	CWD           string                 `json:"cwd"`

	// Legacy snake_case support
	SessionIDSnake     string                 `json:"session_id"`
	ToolNameSnake      string                 `json:"tool_name"`
	ToolInputSnake     map[string]interface{} `json:"tool_input"`
	HookEventNameSnake string                 `json:"hook_event_name"`
}

// Normalize ensures fields are populated from either naming convention
func (h *HookInput) Normalize() {
	if h.SessionID == "" && h.SessionIDSnake != "" {
		h.SessionID = h.SessionIDSnake
	}
	if h.ToolName == "" && h.ToolNameSnake != "" {
		h.ToolName = h.ToolNameSnake
	}
	if h.ToolInput == nil && h.ToolInputSnake != nil {
		h.ToolInput = h.ToolInputSnake
	}
	if h.HookEventName == "" && h.HookEventNameSnake != "" {
		h.HookEventName = h.HookEventNameSnake
	}
}

// Decision represents a PreToolUse resolution decision.
type Decision struct {
	Decision          string                 `json:"decision"` // "allow" | "deny" | "ask" | "defer"
	Reason            *string                `json:"reason,omitempty"`
	UpdatedInput      map[string]interface{} `json:"updatedInput,omitempty"`
	AdditionalContext *string                `json:"additionalContext,omitempty"`
}

// RuleAction defines what action to take for a prompt
type RuleAction struct {
	Type    string `json:"type"` // "manual" | "auto-accept" | "accept-after"
	Seconds int    `json:"seconds,omitempty"`
}

// Settings contains user preferences
type Settings struct {
	Rules  []Rule         `json:"rules"`
	Native NativeSettings `json:"native"`
}

// Rule defines a matching rule for tools
type Rule struct {
	Name       string     `json:"name"`
	ToolName   string     `json:"toolName"`
	Category   string     `json:"category,omitempty"`
	Pattern    string     `json:"pattern,omitempty"`
	Action     RuleAction `json:"action"`
	Enabled    bool       `json:"enabled"`
	MatchCount int        `json:"matchCount"`
}

// NativeSettings are settings for native desktop app
type NativeSettings struct {
	ShowAutoAccept   bool `json:"showAutoAccept"`
	EnableAnimations bool `json:"enableAnimations"`
}

// WebSocket message types
type WSMessage struct {
	Type string `json:"type"`
	// Use interface{} for flexible message content
	Payload interface{} `json:",inline"`
}

// Specific message payloads
type WSPromptNew struct {
	Type   string  `json:"type"`
	Prompt *Prompt `json:"prompt"`
}

type WSPromptResolved struct {
	Type         string `json:"type"`
	ID           string `json:"id"`
	AutoAccepted bool   `json:"autoAccepted"`
}

type WSPromptUpdated struct {
	Type   string  `json:"type"`
	Prompt *Prompt `json:"prompt"`
}

type WSPromptsList struct {
	Type    string    `json:"type"`
	Prompts []*Prompt `json:"prompts"`
}

type WSPauseChanged struct {
	Type     string `json:"type"`
	IsPaused bool   `json:"isPaused"`
}

type WSSettingsUpdated struct {
	Type     string    `json:"type"`
	Settings *Settings `json:"settings"`
}

// Helper to check if a decision is valid
func (d *Decision) IsValid() bool {
	return d.Decision == "allow" || d.Decision == "deny" || d.Decision == "ask" || d.Decision == "defer"
}

// Helper to create default settings
func DefaultSettings() *Settings {
	return &Settings{
		Rules: []Rule{},
		Native: NativeSettings{
			ShowAutoAccept:   true,
			EnableAnimations: true,
		},
	}
}

// Helper to marshal WebSocket messages
func MarshalWSMessage(msgType string, payload interface{}) ([]byte, error) {
	// Create a map to ensure type field comes first
	msg := map[string]interface{}{
		"type": msgType,
	}

	// Add payload fields
	if payload != nil {
		payloadBytes, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}

		var payloadMap map[string]interface{}
		if err := json.Unmarshal(payloadBytes, &payloadMap); err != nil {
			return nil, err
		}

		for k, v := range payloadMap {
			msg[k] = v
		}
	}

	return json.Marshal(msg)
}

// GetCurrentTimeMillis returns current time in milliseconds
func GetCurrentTimeMillis() int64 {
	return time.Now().UnixMilli()
}

// GetSettingsPath returns the path to the settings file
func GetSettingsPath() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(homeDir, ".flowgate", "settings.json")
}

// GetLegacySettingsPath returns the pre-Flowgate settings path.
func GetLegacySettingsPath() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(homeDir, ".claude-prompt-ui", "settings.json")
}

// LoadSettings loads settings from disk, returns default if not found
func LoadSettings() *Settings {
	path := GetSettingsPath()
	if path == "" {
		return DefaultSettings()
	}

	data, err := os.ReadFile(path)
	if err != nil {
		legacyPath := GetLegacySettingsPath()
		if legacyPath == "" {
			return DefaultSettings()
		}
		data, err = os.ReadFile(legacyPath)
		if err != nil {
			// File doesn't exist or can't be read, return defaults
			return DefaultSettings()
		}
	}

	var settings Settings
	if err := json.Unmarshal(data, &settings); err != nil {
		return DefaultSettings()
	}

	return &settings
}

// SaveSettings saves settings to disk
func SaveSettings(settings *Settings) error {
	path := GetSettingsPath()
	if path == "" {
		return nil
	}

	// Ensure directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}
