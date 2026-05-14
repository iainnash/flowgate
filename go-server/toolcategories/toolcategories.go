package toolcategories

import (
	_ "embed"
	"encoding/json"
	"strings"
)

//go:embed tool-categories.json
var categoryConfigJSON []byte

type Config struct {
	MCPPrefix     string              `json:"mcpPrefix"`
	CategoryOrder []string            `json:"categoryOrder"`
	Categories    map[string][]string `json:"categories"`
}

var config = mustLoadConfig()

func mustLoadConfig() Config {
	var loaded Config
	if err := json.Unmarshal(categoryConfigJSON, &loaded); err != nil {
		panic(err)
	}
	return loaded
}

// CategoryFor returns the configured category for a Claude Code tool.
func CategoryFor(toolName string) string {
	if strings.HasPrefix(toolName, config.MCPPrefix) {
		return "mcp"
	}

	for _, category := range config.CategoryOrder {
		for _, configuredTool := range config.Categories[category] {
			if configuredTool == toolName {
				return category
			}
		}
	}

	return "other"
}

// ConfiguredCategories returns the embedded tool category config.
func ConfiguredCategories() Config {
	return config
}
