# ML Pattern Engine

A comprehensive machine learning system for cryptocurrency market analysis, pattern recognition, and prediction with full integration into arbitrage and portfolio management systems.

## 🚀 Features

### Core ML Capabilities
- **Data Ingestion**: Real-time and historical market data collection with quality validation
- **Feature Extraction**: 6+ technical indicators (RSI, MACD, EMA, Bollinger Bands, Stochastic, Volume Profile)
- **Pattern Recognition**: 7 chart pattern types with confidence scoring
- **Price Prediction**: Multi-timeframe ML models (1, 5, 15 minutes) with uncertainty quantification
- **Model Management**: Complete lifecycle management with versioning and deployment strategies

### API & Integration
- **REST API**: Full RESTful API with OpenAPI 3.0 specification
- **WebSocket Streaming**: Real-time data streaming with authentication and rate limiting
- **Arbitrage Integration**: ML-enhanced arbitrage opportunity detection
- **SmartVestor Integration**: AI-powered portfolio management and rebalancing
- **Monitoring**: Comprehensive metrics collection and alerting system

### Performance & Reliability
- **High Performance**: Sub-100ms inference latency with intelligent caching
- **Circuit Breaker**: Automatic failure protection and recovery
- **Rate Limiting**: Configurable request throttling
- **Monitoring**: Real-time metrics, alerts, and health checks

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Layer    │    │    ML Core      │    │ Serving Layer   │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ Data Ingestion  │───▶│ Feature Extract │───▶│ Inference Svc   │
│ Quality Valid   │    │ Pattern Detect  │    │ Cache Manager   │
│ Time Series DB  │    │ Prediction Eng  │    │ Circuit Breaker │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                       ┌─────────────────┐
                       │ Training Pipeline│
                       ├─────────────────┤
                       │ Model Manager   │
                       │ Training Orchestrator│
                       └─────────────────┘
                                │
                       ┌─────────────────┐
                       │ Integration Layer│
                       ├─────────────────┤
                       │ Arbitrage Int.  │
                       │ SmartVestor Int.│
                       │ API & WebSocket │
                       └─────────────────┘
```

## 📦 Modules

- **MLPatternEngine**: Core ML functionality
- **MLPatternEngineAPI**: REST API and WebSocket interfaces
- **MLPatternEngineIntegration**: Integration with arbitrage and SmartVestor systems

## 🚀 Quick Start

### Basic Usage

```swift
import MLPatternEngine

// Initialize the ML engine
let mlEngine = MLPatternEngine()

// Get a price prediction
let prediction = try await mlEngine.getPrediction(
    for: "BTC-USD",
    timeHorizon: 300, // 5 minutes
    modelType: .pricePrediction
)

// Detect patterns
let patterns = try await mlEngine.detectPatterns(for: "BTC-USD")

// Extract features
let features = try await mlEngine.extractFeatures(
    for: "BTC-USD",
    historicalData: marketData
)
```

### API Usage

```swift
import MLPatternEngineAPI

// Initialize API service
let apiService = APIService(mlEngine: mlEngine, logger: logger)

// Make prediction request
let request = PredictionRequestDTO(
    symbol: "BTC-USD",
    timeHorizon: 300,
    modelType: "PRICE_PREDICTION",
    features: [:]
)

let response = try await apiService.predictPrice(request: request, authToken: token)
```

### Integration Usage

```swift
import MLPatternEngineIntegration

// Initialize integration orchestrator
let orchestrator = IntegrationOrchestrator(
    mlEngine: mlEngine,
    arbitrageDetector: arbitrageDetector,
    logger: logger,
    metricsCollector: metricsCollector,
    alertingSystem: alertingSystem
)

// Generate unified trading strategy
let strategy = try await orchestrator.generateUnifiedTradingStrategy()

// Perform real-time analysis
let analysis = try await orchestrator.performRealTimeAnalysis()
```

## 📊 Performance Targets

- **Latency**: <100ms for single predictions, <50ms for cached predictions
- **Accuracy**: F1 score >0.70, MAPE <2% for price predictions
- **Availability**: 99.9% uptime with circuit breaker protection
- **Throughput**: 1000+ predictions per second
- **Cache Hit Rate**: >80% for frequently accessed predictions

## 🔧 Configuration

### Environment Variables

```bash
# API Configuration
ML_API_PORT=8080
ML_API_HOST=0.0.0.0

# Database Configuration
ML_DB_URL=postgresql://localhost:5432/ml_pattern_engine
ML_DB_POOL_SIZE=20

# Cache Configuration
ML_CACHE_SIZE=10000
ML_CACHE_TTL=300

# Model Configuration
ML_MODEL_PATH=/models
ML_MODEL_UPDATE_INTERVAL=3600
```

### Configuration File

```json
{
  "api": {
    "port": 8080,
    "host": "0.0.0.0",
    "rateLimit": {
      "requestsPerMinute": 1000,
      "burstSize": 100
    }
  },
  "models": {
    "pricePrediction": {
      "enabled": true,
      "confidenceThreshold": 0.7,
      "updateInterval": 3600
    },
    "volatilityPrediction": {
      "enabled": true,
      "confidenceThreshold": 0.6,
      "updateInterval": 1800
    }
  },
  "monitoring": {
    "metricsEnabled": true,
    "alertingEnabled": true,
    "logLevel": "INFO"
  }
}
```

## 📈 Monitoring & Alerting

### Metrics Collected

- **Prediction Metrics**: Latency, accuracy, confidence scores
- **API Metrics**: Request rates, error rates, response times
- **System Metrics**: Memory usage, CPU usage, active connections
- **Model Metrics**: Accuracy, drift detection, deployment status
- **Cache Metrics**: Hit rates, miss rates, cache size

### Alert Rules

- **High Latency**: P95 latency >150ms
- **Low Accuracy**: Prediction accuracy <70%
- **High Error Rate**: API error rate >10/minute
- **Model Drift**: PSI >0.25
- **Memory Usage**: Memory usage >2GB
- **Data Quality**: Quality score <0.8

## 🔌 API Endpoints

### Predictions

- `POST /api/v1/predict` - Single prediction
- `POST /api/v1/predict/batch` - Batch predictions
- `GET /api/v1/predict/{symbol}` - Get latest prediction

### Patterns

- `POST /api/v1/patterns/detect` - Detect patterns
- `GET /api/v1/patterns/{symbol}` - Get detected patterns

### Health & Status

- `GET /api/v1/health` - Service health check
- `GET /api/v1/models` - List active models
- `GET /api/v1/metrics` - Get performance metrics

### WebSocket

- `WS /ws` - Real-time data streaming
  - Subscribe to predictions: `{"type": "subscribe_predictions", "data": {"symbol": "BTC-USD"}}`
  - Subscribe to patterns: `{"type": "subscribe_patterns", "data": {"symbol": "BTC-USD"}}`

## 🧪 Testing

```bash
# Run all tests
swift test

# Run specific test target
swift test --filter MLPatternEngineTests

# Run with coverage
swift test --enable-code-coverage
```

## 📚 Documentation

- [API Documentation](docs/api.md)
- [Integration Guide](docs/integration.md)
- [Performance Tuning](docs/performance.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/ml-pattern-engine/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/ml-pattern-engine/discussions)
- **Documentation**: [Wiki](https://github.com/your-org/ml-pattern-engine/wiki)