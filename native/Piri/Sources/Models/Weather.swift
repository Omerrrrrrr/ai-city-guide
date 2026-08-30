import Foundation
import SwiftUI

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
    /// `/weather` bundles this into the same OpenWeatherMap round trip
    /// (see the server's `airUrl` fetch alongside the main `owUrl` one) --
    /// `nil` only when that secondary fetch itself failed, not gated on
    /// tier/quota.
    var airQuality: AirQuality?

    enum CodingKeys: String, CodingKey {
        case city, temp, condition, description, humidity
        case feelsLike = "feels_like"
        case windSpeed = "wind_speed"
        case airQuality = "air_quality"
    }
}

enum AirQualityLevel: String, Codable {
    case good, fair, moderate, poor
    case veryPoor = "very_poor"
}

struct AirQuality: Codable, Hashable {
    var aqi: Int
    var level: AirQualityLevel
    var components: [String: Double]?
}

extension AirQualityLevel {
    var labelKey: String {
        switch self {
        case .good: return "weather.airQuality.good"
        case .fair: return "weather.airQuality.fair"
        case .moderate: return "weather.airQuality.moderate"
        case .poor: return "weather.airQuality.poor"
        case .veryPoor: return "weather.airQuality.veryPoor"
        }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .fair: return .yellow
        case .moderate: return .orange
        case .poor: return .red
        case .veryPoor: return .purple
        }
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
