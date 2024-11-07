import Foundation

struct WeatherResponse: Codable {
    let main: MainWeather
    let weather: [Weather]
}

struct MainWeather: Codable {
    let temp: Double
}

struct Weather: Codable {
    let description: String
    let icon: String
}

class WeatherService {
    private let apiKey = "d4fe3c20d6b0b5eb2b029ec9d8e92cdb"
    private let city = "Auckland,nz"
    
    func fetchWeather() async throws -> WeatherResponse {
        let urlString = "https://api.openweathermap.org/data/2.5/weather?q=\(city)&appid=\(apiKey)&units=metric"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(WeatherResponse.self, from: data)
    }
    
    func weatherSymbol(for description: String) -> String {
        // Map OpenWeather descriptions to SF Symbols (non-filled versions)
        switch description.lowercased() {
        case let desc where desc.contains("clear"):
            return "sun.max"
        case let desc where desc.contains("cloud"):
            return desc.contains("scattered") || desc.contains("broken") ? "cloud" : "cloud.sun"
        case let desc where desc.contains("rain"):
            return "cloud.rain"
        case let desc where desc.contains("drizzle"):
            return "cloud.drizzle"
        case let desc where desc.contains("thunderstorm"):
            return "cloud.bolt.rain"
        case let desc where desc.contains("snow"):
            return "cloud.snow"
        case let desc where desc.contains("mist") || desc.contains("fog"):
            return "cloud.fog"
        default:
            return "cloud"
        }
    }
} 