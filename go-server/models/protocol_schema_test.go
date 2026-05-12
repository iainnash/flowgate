package models

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
)

type protocolSchema struct {
	Defs map[string]schemaDefinition `json:"$defs"`
}

type schemaDefinition struct {
	Required   []string                          `json:"required"`
	Properties map[string]map[string]interface{} `json:"properties"`
}

func TestProtocolSchemaMatchesGoModels(t *testing.T) {
	schema := loadProtocolSchema(t)

	assertSchemaFields(t, schema, "prompt", Prompt{})
	assertSchemaFields(t, schema, "decision", Decision{})
	assertSchemaFields(t, schema, "ruleAction", RuleAction{})
	assertSchemaFields(t, schema, "rule", Rule{})
	assertSchemaFields(t, schema, "nativeSettings", NativeSettings{})
	assertSchemaFields(t, schema, "settings", Settings{})
}

func loadProtocolSchema(t *testing.T) protocolSchema {
	t.Helper()

	data, err := os.ReadFile("../../shared/protocol.schema.json")
	if err != nil {
		t.Fatalf("read protocol schema: %v", err)
	}

	var schema protocolSchema
	if err := json.Unmarshal(data, &schema); err != nil {
		t.Fatalf("decode protocol schema: %v", err)
	}

	return schema
}

func assertSchemaFields(t *testing.T, schema protocolSchema, definitionName string, model interface{}) {
	t.Helper()

	definition, ok := schema.Defs[definitionName]
	if !ok {
		t.Fatalf("missing schema definition %q", definitionName)
	}

	modelFields := jsonFieldNames(model)
	schemaFields := make(map[string]bool, len(definition.Properties))
	for field := range definition.Properties {
		schemaFields[field] = true
	}

	for field := range modelFields {
		if !schemaFields[field] {
			t.Fatalf("%s schema missing Go JSON field %q", definitionName, field)
		}
	}

	for field := range schemaFields {
		if !modelFields[field] {
			t.Fatalf("%s schema has field %q not present in Go model", definitionName, field)
		}
	}
}

func jsonFieldNames(model interface{}) map[string]bool {
	modelType := reflect.TypeOf(model)
	fields := make(map[string]bool, modelType.NumField())

	for i := 0; i < modelType.NumField(); i++ {
		field := modelType.Field(i)
		tag := field.Tag.Get("json")
		if tag == "-" {
			continue
		}

		name := strings.Split(tag, ",")[0]
		if name == "" {
			name = field.Name
		}
		fields[name] = true
	}

	return fields
}
