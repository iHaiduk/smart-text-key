import Foundation

struct ProviderHTTP {
    static func url(baseURL: String, defaultBaseURL: String, path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = defaultBaseURL
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let url = URL(string: "\(base)/\(path)") else {
            throw AIError.invalidURL
        }
        return url
    }

    static func request(url: URL, apiKey: String, authorizationHeader: String = "Authorization") -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanApiKey.isEmpty else {
            return request
        }

        if authorizationHeader == "Authorization" {
            request.setValue("Bearer \(cleanApiKey)", forHTTPHeaderField: authorizationHeader)
        } else {
            request.setValue(cleanApiKey, forHTTPHeaderField: authorizationHeader)
        }

        return request
    }

    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(error)
        }
    }

    static func bytes(for request: URLRequest, session: URLSession = .shared) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            return (bytes, httpResponse)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(error)
        }
    }

    static func validate(_ response: HTTPURLResponse, data: Data? = nil) throws {
        guard (200...299).contains(response.statusCode) else {
            let details = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP status \(response.statusCode)"
            throw AIError.apiError(response.statusCode, details)
        }
    }

    static func connectedMessage(from ids: [String]) -> String {
        guard let example = ids.first else {
            return "Connected (Online)"
        }
        return "Connected (\(ids.count) models: e.g. \(example))"
    }
}
