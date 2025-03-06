//
//  ChatNonStreamModel.swift
//  MCPClientChat
//
//  Created by James Rochabrun on 3/3/25.
//

import Foundation
import MCPSwiftWrapper

@MainActor
@Observable
/// Handle a chat conversation without stream for Anthropic
final class AnthropicNonStreamManager: ChatManager {

  // MARK: Lifecycle

  init(service: AnthropicService) {
    self.service = service
  }

  // MARK: Internal

  /// Messages sent from the user or received from Claude
  var messages: [ChatMessage] = []

  /// Error message if something goes wrong
  var errorMessage = ""

  /// Loading state indicator
  var isLoading = false

  /// Returns true if Claude is still processing a response
  var isProcessing: Bool {
    isLoading
  }

  func updateClient(_ client: MCPClient) {
    mcpClient = client
  }

  /// Send a new message to Claude and get the complete response
  func send(message: ChatMessage) {
    messages.append(message)
    processUserMessage(prompt: message.text)
  }

  /// Cancel the current processing task
  func stop() {
    task?.cancel()
    task = nil
    isLoading = false
  }

  /// Clear the conversation
  func clearConversation() {
    messages.removeAll()
    anthropicMessages.removeAll()
    errorMessage = ""
    isLoading = false
    task?.cancel()
    task = nil
  }

  // MARK: Private

  /// Service to communicate with Anthropic API
  private let service: AnthropicService

  /// Message history for Claude's context
   private var anthropicMessages: [AnthropicMessage] = []

  /// Current task handling Claude API request
  private var task: Task<Void, Never>? = nil

  private var mcpClient: MCPClient?

  private func processUserMessage(prompt: String) {
    guard let mcpClient else {
      fatalError("Client not initialized")
    }
    // Add a placeholder for Claude's response
    messages.append(ChatMessage(text: "", role: .assistant, isWaitingForFirstText: true))

    // Add user message to history
    anthropicMessages.append(AnthropicMessage(
      role: .user,
      content: .text(prompt)))

    task = Task {
      do {
        isLoading = true

        // Get available tools from MCP
        let tools = try await mcpClient.anthropicTools()

        // Send request and process response
        try await continueConversation(tools: tools)

        isLoading = false
      } catch {
        errorMessage = "\(error)"

        // Update UI to show error
        if var last = messages.popLast() {
          last.isWaitingForFirstText = false
          last.text = "Sorry, there was an error: \(error.localizedDescription)"
          messages.append(last)
        }

        isLoading = false
      }
    }
  }

  private func continueConversation(tools: [AnthropicTool]) async throws {
    let parameters = AnthropicParameters(
      model: .claude37Sonnet,
      messages: anthropicMessages,
      maxTokens: 10000,
      tools: tools)

    // Make non-streaming request to Claude
    let message = try await service.createMessage(parameters)

    // Process all content elements with a for loop
    for contentItem in message.content {
      switch contentItem {
      case .text(let text, _):
        // Update the UI with the response
        if var last = messages.popLast() {
          last.isWaitingForFirstText = false
          last.text = text
          messages.append(last)
        }

        // Add assistant response to history
        anthropicMessages.append(AnthropicMessage(
          role: .assistant,
          content: .text(text)))

      case .toolUse(let tool):
        print("Tool use detected - Name: \(tool.name), ID: \(tool.id)")

        // Update UI to show tool use
        if var last = messages.popLast() {
          last.isWaitingForFirstText = false
          last.text += "\n Using tool: \(tool.name)..."
          messages.append(last)
        }

        // Add the assistant message with tool use to message history
        anthropicMessages.append(AnthropicMessage(
          role: .assistant,
          content: .list([.toolUse(tool.id, tool.name, tool.input)])))

        // Call tool via MCP
        let toolResponse = await mcpClient?.anthropicCallTool(name: tool.name, input: tool.input, debug: true)
        print("Tool response: \(String(describing: toolResponse))")

        // Add tool result to conversation
        if let toolResult = toolResponse {
          // Add the assistant message with tool result
          anthropicMessages.append(AnthropicMessage(
            role: .user,
            content: .list([.toolResult(tool.id, toolResult)])))

          // Now get a new response with the tool result
          try await continueConversation(tools: tools)
        } else {
          // Handle tool failure
          if var last = messages.popLast() {
            last.isWaitingForFirstText = false
            last.text = "There was an error using the tool \(tool.name)."
            messages.append(last)
          }
        }

      case .thinking:
        break
      }
    }
  }
}
