//
//  GeminiExtractor.swift
//  AssignmentRadar
//
//  Calls the Google Gemini multimodal API via native URLSession to extract
//  dates, subjects, and course codes from uploaded syllabus or date sheet photos.
//  Supports custom models (e.g., gemini-3.8-flash), dynamic ListModels auto-discovery,
//  and seamless fallback across API versions (v1beta, v1).
//  Requires zero third-party dependencies.
//

import UIKit
import Foundation

enum GeminiExtractorError: LocalizedError {
    case missingApiKey
    case invalidImage
    case networkError(String)
    case invalidResponse(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Please provide a valid Google Gemini API key."
        case .invalidImage:
            return "Unable to process the photo. Please try another image."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .invalidResponse(let msg):
            return "Could not parse Gemini response: \(msg)"
        case .apiError(let statusCode, let message):
            if statusCode == 400 || statusCode == 403 || statusCode == 401 {
                return "Gemini API rejected the request (\(statusCode)): \(message). Please check that your API key is valid."
            }
            return "Gemini API error (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Gemini Raw JSON Schema
private struct GeminiItemDTO: Decodable {
    let title: String
    let subject: String?
    let date: String
    let time: String?
}

private struct GeminiWrapperDTO: Decodable {
    let deadlines: [GeminiItemDTO]
}

private struct ListModelsResponseDTO: Decodable {
    struct ModelDTO: Decodable {
        let name: String
        let supportedGenerationMethods: [String]?
    }
    let models: [ModelDTO]?
}

// MARK: - Gemini Multimodal Service
final class GeminiExtractor {

    /// Normalizes model names (e.g. "gemini 3.8 flash" -> "gemini-3.8-flash")
    static func normalizeModelName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("models/") {
            s = String(s.dropFirst(7))
        }
        s = s.replacingOccurrences(of: " ", with: "-").lowercased()
        return s
    }

    /// Queries ListModels endpoint to discover supported models for this specific API key.
    static func fetchSupportedModels(apiKey: String) async -> [String]? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoints = [
            "https://generativelanguage.googleapis.com/v1beta/models?key=\(cleanKey)",
            "https://generativelanguage.googleapis.com/v1/models?key=\(cleanKey)"
        ]

        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                continue
            }
            guard let root = try? JSONDecoder().decode(ListModelsResponseDTO.self, from: data),
                  let list = root.models else {
                continue
            }

            let supported = list.filter {
                $0.supportedGenerationMethods?.contains("generateContent") == true
            }.map { model in
                model.name.hasPrefix("models/") ? String(model.name.dropFirst(7)) : model.name
            }

            if !supported.isEmpty {
                // Prioritize flash models, then other multimodal models
                let sorted = supported.sorted { a, b in
                    let aFlash = a.lowercased().contains("flash")
                    let bFlash = b.lowercased().contains("flash")
                    if aFlash != bFlash { return aFlash }
                    return a > b
                }
                return sorted
            }
        }
        return nil
    }

    /// Sends the image to Gemini multimodal API and returns extracted deadlines.
    /// Tries preferredModel first (e.g. "gemini-3.8-flash"), followed by key-supported models and standard fallbacks.
    static func extractDeadlines(
        from image: UIImage,
        apiKey: String,
        preferredModel: String? = nil
    ) async throws -> [ParsedDeadlineDraft] {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw GeminiExtractorError.missingApiKey
        }

        // 1. Prepare and optimize image
        let resized = image.resizedForGemini(maxDimension: 1600)
        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
            throw GeminiExtractorError.invalidImage
        }
        let base64String = jpegData.base64EncodedString()

        // 2. Build candidate model list
        var modelCandidates: [String] = []

        // If user specified a model (e.g. "gemini 3.8 flash" or "gemini-3.8-flash"), put it FIRST
        if let pref = preferredModel?.trimmingCharacters(in: .whitespacesAndNewlines), !pref.isEmpty {
            let normalized = normalizeModelName(pref)
            if !normalized.isEmpty && normalized != "auto" {
                modelCandidates.append(normalized)
            }
        }

        // Add models discovered from ListModels for this exact key
        if let discovered = await fetchSupportedModels(apiKey: cleanKey) {
            for m in discovered {
                if !modelCandidates.contains(m) {
                    modelCandidates.append(m)
                }
            }
        }

        // Add standard candidate fallbacks
        let defaultFallbacks = [
            "gemini-3.8-flash",
            "gemini-2.0-flash",
            "gemini-2.5-flash",
            "gemini-2.0-flash-exp",
            "gemini-1.5-flash-latest",
            "gemini-1.5-flash",
            "gemini-1.5-pro",
            "gemini-pro"
        ]
        for m in defaultFallbacks {
            if !modelCandidates.contains(m) {
                modelCandidates.append(m)
            }
        }

        let prompt = """
        Analyze this photo of an academic syllabus, assignment sheet, exam timetable, or college noticeboard.
        Extract all exams, assignments, practicals, submissions, and deadlines listed in the document.

        For each entry, extract:
        1. "title": The name of the subject or assignment (e.g. "Geology", "Comp. App", "Maths / BCA Math", "Problem Set 1").
        2. "subject": The specific course code if available (e.g. "IGELTC0101", "CS301", "1BOTTC0201"), or a clean abbreviation of the subject. If none is found, use "General".
        3. "date": The exact due date or exam date in "YYYY-MM-DD" format.
        4. "time": The exam or submission time in 24-hour "HH:mm" format (e.g. "10:00" if the notice says "10.00 a.m.", "14:00" for 2:00 PM). If no specific time is listed on the document, default to "23:59".

        Return ONLY a JSON array of objects conforming to this schema:
        [
          {
            "title": "String",
            "subject": "String",
            "date": "YYYY-MM-DD",
            "time": "HH:mm"
          }
        ]
        Do not wrap in markdown or conversational commentary. Return pure JSON only.
        """

        var lastError: Error?
        let apiVersions = ["v1beta", "v1"]

        // 3. Iterate candidates across API versions until one succeeds
        for model in modelCandidates {
            for apiVer in apiVersions {
                let urlStr = "https://generativelanguage.googleapis.com/\(apiVer)/models/\(model):generateContent?key=\(cleanKey)"
                guard let url = URL(string: urlStr) else { continue }

                do {
                    let drafts = try await executeGenerateContent(
                        url: url,
                        prompt: prompt,
                        base64Image: base64String
                    )
                    return drafts
                } catch let err as GeminiExtractorError {
                    if case .apiError(let statusCode, _) = err, statusCode == 404 {
                        // 404: model not found for this apiVer, continue trying next candidate
                        lastError = err
                        continue
                    }
                    // For auth errors (400, 401, 403), throw immediately so the user can fix their key
                    throw err
                } catch {
                    lastError = error
                    continue
                }
            }
        }

        throw lastError ?? GeminiExtractorError.invalidResponse("No supported Gemini models found for this API key. Tried: \(modelCandidates.prefix(3).joined(separator: ", ")).")
    }

    // MARK: - Execute Request Helper
    private static func executeGenerateContent(
        url: URL,
        prompt: String,
        base64Image: String
    ) async throws -> [ParsedDeadlineDraft] {
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        request.timeoutInterval = 45

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiExtractorError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiExtractorError.invalidResponse("Invalid server response")
        }

        if httpResponse.statusCode != 200 {
            var errorMessage = "HTTP status \(httpResponse.statusCode)"
            if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errDict = errorObj["error"] as? [String: Any],
               let msg = errDict["message"] as? String {
                errorMessage = msg
            }
            throw GeminiExtractorError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = rootObj["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let rawText = firstPart["text"] as? String else {
            throw GeminiExtractorError.invalidResponse("Gemini response missing candidate text content")
        }

        // Clean JSON text
        var jsonText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```json") {
            jsonText = String(jsonText.dropFirst(7))
        } else if jsonText.hasPrefix("```") {
            jsonText = String(jsonText.dropFirst(3))
        }
        if jsonText.hasSuffix("```") {
            jsonText = String(jsonText.dropLast(3))
        }
        jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw GeminiExtractorError.invalidResponse("Failed to read JSON payload from Gemini")
        }

        var items: [GeminiItemDTO] = []
        if let directList = try? JSONDecoder().decode([GeminiItemDTO].self, from: jsonData) {
            items = directList
        } else if let wrapper = try? JSONDecoder().decode(GeminiWrapperDTO.self, from: jsonData) {
            items = wrapper.deadlines
        } else {
            throw GeminiExtractorError.invalidResponse("Gemini output format was not recognized as a deadline list")
        }

        return items.map { dto in
            let date = parseDate(dateStr: dto.date, timeStr: dto.time)
            let title = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = (dto.subject ?? "General").trimmingCharacters(in: .whitespacesAndNewlines)

            return ParsedDeadlineDraft(
                title: title.isEmpty ? "Assignment Task" : title,
                subject: subject.isEmpty ? "General" : subject,
                dueDate: date,
                isSelected: true
            )
        }
    }

    // MARK: - Date Parsing Helper
    private static func parseDate(dateStr: String, timeStr: String?) -> Date {
        let cleanTime = (timeStr ?? "23:59").trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(dateStr.trimmingCharacters(in: .whitespacesAndNewlines)) \(cleanTime)"

        let formats = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "dd-MM-yyyy HH:mm",
            "dd-MM-yyyy",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: combined) {
                return date
            }
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }

        return Date()
    }
}

// MARK: - UIImage Resize Extension
extension UIImage {
    fileprivate func resizedForGemini(maxDimension: CGFloat) -> UIImage {
        let width = self.size.width
        let height = self.size.height

        guard width > maxDimension || height > maxDimension else {
            return self
        }

        let aspectRatio = width / height
        let newSize: CGSize
        if width > height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized ?? self
    }
}
