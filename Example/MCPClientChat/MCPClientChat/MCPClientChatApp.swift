//
//  MCPClientChatApp.swift
//  MCPClientChat
//
//  Created by James Rochabrun on 3/3/25.
//

import MCPSwiftWrapper
import SwiftUI

@main
struct MCPClientChatApp: App {

  // MARK: Lifecycle

  init() {
    let service = AnthropicServiceFactory.service(apiKey: "", betaHeaders: nil, debugEnabled: true)

    let initialManager = AnthropicNonStreamManager(service: service)

    _chatManager = State(initialValue: initialManager)

    // Uncomment this and comment the above for OpenAI Demo

    //      let openAIService = OpenAIServiceFactory.service(apiKey: "", debugEnabled: true)
    //
    //      let openAIChatNonStreamManager = OpenAIChatNonStreamManager(service: openAIService)
    //
    //      _chatManager = State(initialValue: openAIChatNonStreamManager)
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      ChatView(chatManager: chatManager)
        .toolbar(removing: .title)
        .containerBackground(
          .thinMaterial, for: .window)
        .toolbarBackgroundVisibility(
          .hidden, for: .windowToolbar)
        .task {
          if let client = try? await githubClient.getClientAsync() {
            chatManager.updateClient(client)
          }
        }
    }
    .windowStyle(.hiddenTitleBar)
  }

  // MARK: Private

  @State private var chatManager: ChatManager
  private let githubClient = GIthubMCPClient()
}
