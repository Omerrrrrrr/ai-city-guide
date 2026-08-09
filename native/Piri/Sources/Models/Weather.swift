import Foundation

enum WeatherCondition: String, Codable {
    case sunny, cloudy, rainy, snowy, stormy, foggy
}

struct Weather: Codable, Hashable {
    var city: String
    var temp: Double
    var feelsLike: Double
    var condition: WeatherCondition
    var description: String
    var humidity: Double
    var windSpeed: Double

    enum CodingKeys: String, CodingKey {
        case city, temp, condition, description, humidity
        case feelsLike = "feels_like"
        case windSpeed = "wind_speed"
    }
}

extension WeatherCondition {
    var emoji: String {
        switch self {
        case .sunny: return "☀️"
        case .cloudy: return "⛅"
        case .rainy: return "🌧️"
        case .snowy: return "❄️"
        case .stormy: return "⛈️"
        case .foggy: return "🌫️"
        }
    }

    var isIndoor: Bool {
        self == .rainy || self == .stormy || self == .snowy
    }
}
