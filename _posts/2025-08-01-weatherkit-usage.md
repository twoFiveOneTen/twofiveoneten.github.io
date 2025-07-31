---
layout: post
title:  "WeatherKit 的使用"
date:   2025-08-01 00:39:26 +0800
categories: iOS
---

## iOS WeatherKit 全面开发指南

WeatherKit 是苹果在 iOS 16 中引入的天气数据框架，提供准确、可靠的天气信息服务。它取代了之前的 Dark Sky API，为开发者提供了官方的天气数据解决方案。

## 基础配置
### 1. 项目配置
首先需要在 Xcode 项目中启用 WeatherKit 能力：

1. 选择项目 target
2. 进入 "Signing & Capabilities" 标签
3. 点击 "+ Capability" 添加 "WeatherKit"
4. 确保开发者账号支持 WeatherKit 服务

### 2. 导入框架

```swift
import WeatherKit
import CoreLocation
```

### 3. 权限配置

在 `Info.plist` 中添加位置权限说明：

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>此应用需要访问您的位置以提供天气信息</string>
```

## 核心组件详解

### WeatherService

`WeatherService` 是 WeatherKit 的核心服务类，负责获取天气数据：

```swift
let weatherService = WeatherService()
```

### 位置管理

天气数据需要基于地理位置，通常结合 CoreLocation 使用：

```swift
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
}
```

## 天气数据获取

### 1. 当前天气

```swift
func getCurrentWeather(for location: CLLocation) async throws -> CurrentWeather {
    let currentWeather = try await weatherService.weather(for: location)
    return currentWeather.currentWeather
}

// 使用示例
Task {
    do {
        let current = try await getCurrentWeather(for: userLocation)
        print("当前温度: \(current.temperature)")
        print("天气状况: \(current.condition)")
        print("湿度: \(current.humidity)")
    } catch {
        print("获取天气数据失败: \(error)")
    }
}
```

### 2. 每小时预报

```swift
func getHourlyForecast(for location: CLLocation) async throws -> Forecast<HourWeather> {
    let weather = try await weatherService.weather(for: location)
    return weather.hourlyForecast
}

// 使用示例
Task {
    do {
        let hourlyForecast = try await getHourlyForecast(for: userLocation)
        for hourWeather in hourlyForecast {
            print("时间: \(hourWeather.date)")
            print("温度: \(hourWeather.temperature)")
            print("降水概率: \(hourWeather.precipitationChance)")
        }
    } catch {
        print("获取小时预报失败: \(error)")
    }
}
```

### 3. 每日预报

```swift
func getDailyForecast(for location: CLLocation) async throws -> Forecast<DayWeather> {
    let weather = try await weatherService.weather(for: location)
    return weather.dailyForecast
}

// 使用示例
Task {
    do {
        let dailyForecast = try await getDailyForecast(for: userLocation)
        for dayWeather in dailyForecast {
            print("日期: \(dayWeather.date)")
            print("最高温度: \(dayWeather.highTemperature)")
            print("最低温度: \(dayWeather.lowTemperature)")
            print("天气状况: \(dayWeather.condition)")
        }
    } catch {
        print("获取每日预报失败: \(error)")
    }
}
```

### 4. 天气预警

```swift
func getWeatherAlerts(for location: CLLocation) async throws -> [WeatherAlert] {
    let weather = try await weatherService.weather(for: location)
    return weather.weatherAlerts ?? []
}

// 使用示例
Task {
    do {
        let alerts = try await getWeatherAlerts(for: userLocation)
        for alert in alerts {
            print("预警标题: \(alert.summary)")
            print("预警详情: \(alert.detailsURL)")
            print("严重程度: \(alert.severity)")
        }
    } catch {
        print("获取天气预警失败: \(error)")
    }
}
```

## 实际应用示例

### 完整的天气应用 ViewModel

```swift
import Foundation
import WeatherKit
import CoreLocation

@MainActor
class WeatherViewModel: ObservableObject {
    @Published var currentWeather: CurrentWeather?
    @Published var hourlyForecast: Forecast<HourWeather>?
    @Published var dailyForecast: Forecast<DayWeather>?
    @Published var weatherAlerts: [WeatherAlert] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let weatherService = WeatherService()
    private let locationManager = LocationManager()
    
    init() {
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.requestLocation()
    }
    
    func loadWeatherData() async {
        guard let location = locationManager.location else {
            errorMessage = "无法获取位置信息"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            async let current = weatherService.weather(for: location)
            let weather = try await current
            
            currentWeather = weather.currentWeather
            hourlyForecast = weather.hourlyForecast
            dailyForecast = weather.dailyForecast
            weatherAlerts = weather.weatherAlerts ?? []
            
        } catch {
            errorMessage = handleWeatherError(error)
        }
        
        isLoading = false
    }
    
    private func handleWeatherError(_ error: Error) -> String {
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .unsupportedLocation:
                return "不支持的地理位置"
            @unknown default:
                return "天气服务暂时不可用"
            }
        }
        return "获取天气数据失败: \(error.localizedDescription)"
    }
}
```

### SwiftUI 界面实现

```swift
import SwiftUI
import WeatherKit

struct WeatherView: View {
    @StateObject private var viewModel = WeatherViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView("加载中...")
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    } else {
                        currentWeatherView
                        hourlyForecastView
                        dailyForecastView
                        weatherAlertsView
                    }
                }
                .padding()
            }
            .navigationTitle("天气")
            .refreshable {
                await viewModel.loadWeatherData()
            }
        }
        .task {
            await viewModel.loadWeatherData()
        }
    }
    
    @ViewBuilder
    private var currentWeatherView: some View {
        if let current = viewModel.currentWeather {
            VStack {
                Text(current.temperature.formatted(.measurement(width: .abbreviated)))
                    .font(.largeTitle)
                    .bold()
                
                Text(current.condition.description)
                    .font(.title2)
                
                HStack {
                    Label("湿度 \(current.humidity.formatted(.percent))", 
                          systemImage: "humidity")
                    Spacer()
                    Label("风速 \(current.wind.speed.formatted())", 
                          systemImage: "wind")
                }
                .font(.caption)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    @ViewBuilder
    private var hourlyForecastView: some View {
        if let hourlyForecast = viewModel.hourlyForecast {
            VStack(alignment: .leading) {
                Text("小时预报")
                    .font(.headline)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(Array(hourlyForecast.prefix(24)), id: \.date) { hour in
                            VStack {
                                Text(hour.date.formatted(.dateTime.hour()))
                                    .font(.caption)
                                
                                Image(systemName: hour.symbolName)
                                    .font(.title3)
                                
                                Text(hour.temperature.formatted(.measurement(width: .abbreviated)))
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var dailyForecastView: some View {
        if let dailyForecast = viewModel.dailyForecast {
            VStack(alignment: .leading) {
                Text("十日预报")
                    .font(.headline)
                
                ForEach(Array(dailyForecast.prefix(10)), id: \.date) { day in
                    HStack {
                        Text(day.date.formatted(.dateTime.weekday()))
                            .frame(width: 80, alignment: .leading)
                        
                        Image(systemName: day.symbolName)
                        
                        Spacer()
                        
                        Text(day.lowTemperature.formatted(.measurement(width: .abbreviated)))
                            .foregroundColor(.secondary)
                        
                        Text("-")
                        
                        Text(day.highTemperature.formatted(.measurement(width: .abbreviated)))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    private var weatherAlertsView: some View {
        if !viewModel.weatherAlerts.isEmpty {
            VStack(alignment: .leading) {
                Text("天气预警")
                    .font(.headline)
                
                ForEach(viewModel.weatherAlerts, id: \.summary) { alert in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text(alert.summary)
                                .font(.subheadline)
                                .bold()
                            
                            if let region = alert.region {
                                Text(region)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
}
```

## 最佳实践

### 1. 错误处理

```swift
enum WeatherAppError: LocalizedError {
    case locationUnavailable
    case weatherServiceUnavailable
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "无法获取位置信息，请检查位置权限设置"
        case .weatherServiceUnavailable:
            return "天气服务暂时不可用，请稍后重试"
        case .networkError:
            return "网络连接异常，请检查网络设置"
        }
    }
}

func safeWeatherFetch(for location: CLLocation) async throws -> Weather {
    do {
        return try await weatherService.weather(for: location)
    } catch {
        if error is WeatherError {
            throw WeatherAppError.weatherServiceUnavailable
        } else {
            throw WeatherAppError.networkError
        }
    }
}
```

### 2. 数据缓存策略

```swift
class WeatherCache {
    private var cache: [String: CachedWeatherData] = [:]
    private let cacheTimeout: TimeInterval = 300 // 5分钟
    
    struct CachedWeatherData {
        let weather: Weather
        let timestamp: Date
    }
    
    func cachedWeather(for location: CLLocation) -> Weather? {
        let key = locationKey(for: location)
        
        guard let cachedData = cache[key],
              Date().timeIntervalSince(cachedData.timestamp) < cacheTimeout else {
            return nil
        }
        
        return cachedData.weather
    }
    
    func cacheWeather(_ weather: Weather, for location: CLLocation) {
        let key = locationKey(for: location)
        cache[key] = CachedWeatherData(weather: weather, timestamp: Date())
    }
    
    private func locationKey(for location: CLLocation) -> String {
        return "\(location.coordinate.latitude),\(location.coordinate.longitude)"
    }
}
```

### 3. 温度单位处理

```swift
extension Measurement where UnitType == UnitTemperature {
    var localizedTemperature: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: self)
    }
}

// 使用示例
let temperature = currentWeather.temperature
let displayText = temperature.localizedTemperature + "°"
```

### 4. 天气图标映射

```swift
extension WeatherCondition {
    var customIconName: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .cloudy:
            return "cloud.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
        case .rain:
            return "cloud.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .thunderstorms:
            return "cloud.bolt.rain.fill"
        default:
            return "questionmark"
        }
    }
}
```

### 5. 性能优化

```swift
class OptimizedWeatherManager {
    private let weatherService = WeatherService()
    private var currentTask: Task<Weather, Error>?
    
    func getWeather(for location: CLLocation) async throws -> Weather {
        // 取消之前的请求
        currentTask?.cancel()
        
        // 创建新的请求任务
        currentTask = Task {
            try await weatherService.weather(for: location)
        }
        
        return try await currentTask!.value
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

### 6. 多地点天气管理

```swift
class MultiLocationWeatherManager: ObservableObject {
    @Published var weatherData: [String: Weather] = [:]
    @Published var isLoading: Set<String> = []
    
    private let weatherService = WeatherService()
    
    func addLocation(_ location: CLLocation, name: String) async {
        let key = locationKey(for: location, name: name)
        
        await MainActor.run {
            isLoading.insert(key)
        }
        
        do {
            let weather = try await weatherService.weather(for: location)
            await MainActor.run {
                weatherData[key] = weather
                isLoading.remove(key)
            }
        } catch {
            await MainActor.run {
                isLoading.remove(key)
            }
            print("获取天气数据失败: \(error)")
        }
    }
    
    private func locationKey(for location: CLLocation, name: String) -> String {
        return "\(name)_\(location.coordinate.latitude)_\(location.coordinate.longitude)"
    }
}
```

## 注意事项

1. **API 限制**: WeatherKit 有使用限制，建议实现适当的缓存机制
2. **权限管理**: 确保正确处理位置权限，提供友好的权限请求体验
3. **离线处理**: 考虑网络不可用时的降级方案
4. **电池优化**: 避免频繁请求天气数据，合理设置更新间隔
5. **用户体验**: 提供加载状态、错误提示和重试机制
6. **数据准确性**: WeatherKit 提供高质量数据，但仍需考虑数据的时效性

WeatherKit 为 iOS 开发者提供了强大而可靠的天气数据服务。通过合理的架构设计、错误处理和性能优化，可以构建出优秀的天气应用体验。记住始终关注用户体验，提供直观、响应迅速的界面，让用户能够轻松获取所需的天气信息。