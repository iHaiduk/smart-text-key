import Testing
import Foundation
@testable import SmartTextKey

// MARK: - Mock URL Protocol

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [NSLocalizedDescriptionKey: "No handler registered."])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Safe Chunk Collector

final class SafeChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var chunks: [String] = []
    
    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(chunk)
    }
}

// MARK: - Suite Setup

@Suite("API Providers Integration Tests", .serialized)
@MainActor
struct APIProvidersTests {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - OpenAI Compatible Provider Tests
    
    @Test("Test OpenAI non-streaming completion and response parsing")
    func testOpenAICompatibleCompletion() async throws {
        let client = OpenAICompatibleProviderClient(defaultBaseURL: "https://api.openai.com/v1", session: session)
        let config = APIConfig(name: "OpenAI Test", apiBaseURL: "https://api.openai.com/v1", apiKey: "sk-test-key", modelName: "gpt-4o")
        let action = PromptAction(title: "Translate", systemPrompt: "Sys Prompt", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let expectedResponse = """
        {
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": "Hello from OpenAI Mock!"
                    }
                }
            ]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.httpMethod == "POST")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedResponse.data(using: .utf8))
        }
        
        let result = try await client.complete(config: config, action: action, finalPrompt: "Translate this", onChunk: nil)
        #expect(result == "Hello from OpenAI Mock!")
    }
    
    @Test("Test OpenAI streaming chunk assembly")
    func testOpenAICompatibleStreaming() async throws {
        let client = OpenAICompatibleProviderClient(defaultBaseURL: "https://api.openai.com/v1", session: session)
        let config = APIConfig(name: "OpenAI Test", apiBaseURL: "", apiKey: "sk-test-key", modelName: "gpt-4o")
        let action = PromptAction(title: "Translate", systemPrompt: "Sys Prompt", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let sseChunks = [
            "data: {\"choices\": [{\"delta\": {\"content\": \"Hello\"}}]}\n",
            "data: {\"choices\": [{\"delta\": {\"content\": \" world\"}}]}\n",
            "data: [DONE]\n"
        ].joined(separator: "\n")
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sseChunks.data(using: .utf8))
        }
        
        let collector = SafeChunkCollector()
        let result = try await client.complete(config: config, action: action, finalPrompt: "Hi", onChunk: { chunk in
            collector.append(chunk)
        })
        
        #expect(result == "Hello world")
        #expect(collector.chunks == ["Hello", " world"])
    }
    
    @Test("Test OpenAI fetch available models")
    func testOpenAIFetchModels() async throws {
        let client = OpenAICompatibleProviderClient(defaultBaseURL: "https://api.openai.com/v1", session: session)
        
        let modelsPayload = """
        {
            "data": [
                {"id": "gpt-4"},
                {"id": "gpt-3.5-turbo"},
                {"id": "gpt-4o"}
            ]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, modelsPayload.data(using: .utf8))
        }
        
        let models = await client.fetchAvailableModels(baseURL: "", apiKey: "sk-test-key")
        #expect(models == ["gpt-3.5-turbo", "gpt-4", "gpt-4o"])
    }

    // MARK: - Ollama Provider Tests
    
    @Test("Test Ollama non-streaming completion and base URL normalization")
    func testOllamaCompletion() async throws {
        let client = OllamaProviderClient(session: session)
        // base URL should be normalized (removing /v1 if present)
        let config = APIConfig(name: "Ollama Local", apiBaseURL: "http://127.0.0.1:11434/v1/", apiKey: "", modelName: "llama3")
        let action = PromptAction(title: "Code", systemPrompt: "System", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let expectedResponse = """
        {
            "message": {
                "content": "Hello from Ollama Mock!"
            },
            "done": true
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
            #expect(request.httpMethod == "POST")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedResponse.data(using: .utf8))
        }
        
        let result = try await client.complete(config: config, action: action, finalPrompt: "Tell me", onChunk: nil)
        #expect(result == "Hello from Ollama Mock!")
    }

    @Test("Test Ollama streaming completion")
    func testOllamaStreaming() async throws {
        let client = OllamaProviderClient(session: session)
        let config = APIConfig(name: "Ollama Local", apiBaseURL: "http://localhost:11434", apiKey: "", modelName: "llama3")
        let action = PromptAction(title: "Code", systemPrompt: "System", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let ndjsonResponse = """
        {"message": {"content": "Clean "}, "done": false}
        {"message": {"content": "code"}, "done": true}
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, ndjsonResponse.data(using: .utf8))
        }
        
        let collector = SafeChunkCollector()
        let result = try await client.complete(config: config, action: action, finalPrompt: "Hi", onChunk: { chunk in
            collector.append(chunk)
        })
        
        #expect(result == "Clean code")
        #expect(collector.chunks == ["Clean ", "code"])
    }

    // MARK: - Anthropic Provider Tests
    
    @Test("Test Anthropic non-streaming completion, headers and payload parsing")
    func testAnthropicCompletion() async throws {
        let client = AnthropicProviderClient(session: session)
        let config = APIConfig(name: "Anthropic Cloud", apiBaseURL: "https://api.anthropic.com/v1", apiKey: "ant-test-key", modelName: "claude-3-5-sonnet")
        let action = PromptAction(title: "Rewrite", systemPrompt: "Sys", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let expectedResponse = """
        {
            "content": [
                {
                    "type": "text",
                    "text": "Hello from Claude Mock!"
                }
            ]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "ant-test-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.httpMethod == "POST")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedResponse.data(using: .utf8))
        }
        
        let result = try await client.complete(config: config, action: action, finalPrompt: "Rewrite this", onChunk: nil)
        #expect(result == "Hello from Claude Mock!")
    }

    @Test("Test Anthropic custom stream delta event decoding")
    func testAnthropicStreaming() async throws {
        let client = AnthropicProviderClient(session: session)
        let config = APIConfig(name: "Anthropic Cloud", apiBaseURL: "", apiKey: "ant-test-key", modelName: "claude-3-5-sonnet")
        let action = PromptAction(title: "Rewrite", systemPrompt: "Sys", template: "{{TEXT}}", shortcutId: "test_sh")
        
        let streamingEvents = [
            "data: {\"type\": \"content_block_delta\", \"delta\": {\"text\": \"Highly \"}}\n",
            "data: {\"type\": \"content_block_delta\", \"delta\": {\"text\": \"hardened!\"}}\n",
            "data: {\"type\": \"message_stop\"}\n"
        ].joined(separator: "\n")
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, streamingEvents.data(using: .utf8))
        }
        
        let collector = SafeChunkCollector()
        let result = try await client.complete(config: config, action: action, finalPrompt: "Hi", onChunk: { chunk in
            collector.append(chunk)
        })
        
        #expect(result == "Highly hardened!")
        #expect(collector.chunks == ["Highly ", "hardened!"])
    }

    // MARK: - Integration Thinking Process Stripping Test

    @Test("Test AIService cleanThinkingProcess filters output appropriately")
    @MainActor
    func testAIServiceThinkingProcessStripping() async throws {
        let action = PromptAction(
            title: "Thinking Test",
            systemPrompt: "Ignore",
            template: "User input: {{TEXT}}",
            shortcutId: "thinking_test"
        )
        
        // Setup direct active config
        let localConfig = APIConfig(
            name: "Test Ollama",
            apiBaseURL: "http://localhost:11434/v1",
            apiKey: "",
            modelName: "llama3",
            providerId: "ollama"
        )
        
        AppSettings.shared.apiConfigs.removeAll()
        AppSettings.shared.apiConfigs.append(localConfig)
        AppSettings.shared.activeConfigId = localConfig.id
        
        let responseWithThinking = """
        <think>
        Let me think about how to write clean code...
        We should use structured logging and separate files.
        </think>
        Hello from clean code world!
        """
        
        let expectedResponse = """
        {
            "message": {
                "content": "\(responseWithThinking.replacingOccurrences(of: "\n", with: "\\n"))"
            },
            "done": true
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedResponse.data(using: .utf8))
        }
        
        let service = AIService(session: session)
        let result = try await service.process(action: action, capturedText: "Clean code please", originalClipboardText: "")
        #expect(result == "Hello from clean code world!")
    }

    // MARK: - Rich Features Tests

    @Test("Test dynamic per-app action shortcut resolution")
    func testPerAppActionBindingResolution() {
        let globalAction = PromptAction(
            title: "Global Action",
            systemPrompt: "Sys",
            template: "Global: {{TEXT}}",
            shortcutId: "test_sh",
            bundleId: nil
        )
        
        let xcodeAction = PromptAction(
            title: "Xcode Action",
            systemPrompt: "Sys",
            template: "Xcode: {{TEXT}}",
            shortcutId: "test_sh",
            bundleId: "com.apple.dt.Xcode"
        )
        
        let actions = [globalAction, xcodeAction]
        
        // 1. Resolve for Xcode
        let activeBundleXcode = "com.apple.dt.Xcode"
        let resolvedXcode = actions.first(where: { $0.bundleId == activeBundleXcode }) ?? actions.first(where: { $0.bundleId == nil }) ?? globalAction
        #expect(resolvedXcode.title == "Xcode Action")
        
        // 2. Resolve for Slack
        let activeBundleSlack = "com.tinyspeck.slackmacgap"
        let resolvedSlack = actions.first(where: { $0.bundleId == activeBundleSlack }) ?? actions.first(where: { $0.bundleId == nil }) ?? globalAction
        #expect(resolvedSlack.title == "Global Action")
    }

    @Test("Test pipeline local static snippet expansion")
    @MainActor
    func testPipelineSnippetLocalExecution() async throws {
        let clipboard = MockClipboardClient()
        let ai = MockAIClient()
        let hud = MockHUDPresenter()
        let history = MockHistoryStore()
        let reporter = MockErrorReporter()
        
        let pipeline = TransformationPipeline(
            clipboardClient: clipboard,
            aiClient: ai,
            hudPresenter: hud,
            historyStore: history,
            errorReporter: reporter
        )
        
        let snippet = PromptAction(
            title: "Static Snippet",
            systemPrompt: "",
            template: "Hello World",
            shortcutId: "snippet_sh",
            isSnippet: true
        )
        
        await pipeline.run(action: snippet)
        
        // Snippets must NOT trigger AI processing or show HUD loaders,
        // and must paste the generated static expansion text directly.
        #expect(ai.processCalled == false)
        #expect(clipboard.pasteCalled == true)
        #expect(clipboard.pastedText == "Hello World")
    }
}
