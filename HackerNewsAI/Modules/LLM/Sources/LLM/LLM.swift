// LLM Module - HackerNewsAI
// Copyright 2026

// AnyLanguageModel provides the Anthropic backend and its own session abstraction.
// It is NOT re-exported: the on-device path talks to FoundationModels directly
// (see FoundationModelRuntime.swift) and AnyLanguageModel declares colliding
// names (LanguageModelSession/SystemLanguageModel/GenerationOptions), so we keep
// imports plain to avoid ambiguity.
import AnyLanguageModel

// MLX frameworks for the local-model backend
#if os(macOS) && canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif
