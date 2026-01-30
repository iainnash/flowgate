package models

import (
	"encoding/json"
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
	AutoAcceptIn  *int                   `json:"autoAcceptIn,omitempty"`  // seconds
	AutoAcceptAt  *int64                 `json:"autoAcceptAt,omitempty"`  // milliseconds
}

// HookInput is the input from Claude Code hook
type HookInput struct {
	SessionID     string                 `json:"session_id"`
	ToolName      string                 `json:"tool_name"`
	ToolInput     map[string]interface{} `json:"tool_input"`
	HookEventName string                 `json:"hook_event_name"`
	CWD           string                 `json:"cwd"`
}

// Decision represents a resolution decision
type Decision struct {
	Decision     string                 `json:"decision"` // "allow" | "deny" | "ask"
	Reason       *string                `json:"reason,omitempty"`
	UpdatedInput map[string]interface{} `json:"updatedInput,omitempty"`
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
	return d.Decision == "allow" || d.Decision == "deny" || d.Decision == "ask"
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
