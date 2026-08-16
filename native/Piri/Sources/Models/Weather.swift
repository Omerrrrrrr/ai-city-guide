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

struct DailyForecast: Codable, Identifiable, Hashable {
    var date: String
    var tempMin: Double
    var tempMax: Double
    var condition: WeatherCondition
    var description: String

    var id: String { date }
}

struct DailyForecastResponse: Codable {
    var city: String
    var daily: [DailyForecast]
}

extension WeatherCondition {
    var icon: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.sun.fill"
        case .rainy: return "cloud.rain.fill"
        case .snowy: return "cloud.snow.fill"
        case .stormy: return "cloud.bolt.rain.fill"
        case .foggy: return "cloud.fog.fill"
        }
    }

    var isIndoor: Bool {
        self == .rainy || self == .stormy || self == .snowy
    }
}
