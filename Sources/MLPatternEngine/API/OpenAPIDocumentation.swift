import Foundation

public struct OpenAPIDocumentation {
    public static let spec = """
    {
      "openapi": "3.0.3",
      "info": {
        "title": "Mercatus ML Pattern Engine API",
        "description": "A comprehensive machine learning system for cryptocurrency market analysis, pattern recognition, and prediction",
        "version": "1.0.0",
        "contact": {
          "name": "Mercatus Team",
          "email": "support@mercatus.com"
        },
        "license": {
          "name": "MIT",
          "url": "https://opensource.org/licenses/MIT"
        }
      },
      "servers": [
        {
          "url": "https://api.mercatus.com",
          "description": "Production server"
        },
        {
          "url": "https://staging-api.mercatus.com",
          "description": "Staging server"
        },
        {
          "url": "http://localhost:8080",
          "description": "Development server"
        }
      ],
      "security": [
        {
          "BearerAuth": []
        }
      ],
      "paths": {
        "/api/v1/predict": {
          "post": {
            "tags": ["Predictions"],
            "summary": "Get price prediction",
            "description": "Get ML-powered price prediction for a given cryptocurrency symbol",
            "operationId": "predictPrice",
            "security": [{"BearerAuth": []}],
            "requestBody": {
              "required": true,
              "content": {
                "application/json": {
                  "schema": {
                    "$ref": "#/components/schemas/PredictionRequest"
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "Successful prediction",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/PredictionResponse"
                    }
                  }
                }
              },
              "400": {
                "description": "Bad request",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/ErrorResponse"
                    }
                  }
                }
              },
              "401": {
                "description": "Unauthorized",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/ErrorResponse"
                    }
                  }
                }
              },
              "429": {
                "description": "Rate limit exceeded",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/ErrorResponse"
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/predict/batch": {
          "post": {
            "tags": ["Predictions"],
            "summary": "Get batch predictions",
            "description": "Get multiple predictions in a single request",
            "operationId": "batchPredict",
            "security": [{"BearerAuth": []}],
            "requestBody": {
              "required": true,
              "content": {
                "application/json": {
                  "schema": {
                    "$ref": "#/components/schemas/BatchPredictionRequest"
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "Successful batch predictions",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": {
                        "$ref": "#/components/schemas/PredictionResponse"
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/patterns/detect": {
          "post": {
            "tags": ["Patterns"],
            "summary": "Detect chart patterns",
            "description": "Detect technical chart patterns in price data",
            "operationId": "detectPatterns",
            "security": [{"BearerAuth": []}],
            "requestBody": {
              "required": true,
              "content": {
                "application/json": {
                  "schema": {
                    "$ref": "#/components/schemas/PatternDetectionRequest"
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "Patterns detected",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": {
                        "$ref": "#/components/schemas/PatternResponse"
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/health": {
          "get": {
            "tags": ["Health"],
            "summary": "Health check",
            "description": "Get service health status and metrics",
            "operationId": "getHealth",
            "responses": {
              "200": {
                "description": "Service health status",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/HealthResponse"
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/models": {
          "get": {
            "tags": ["Models"],
            "summary": "List active models",
            "description": "Get list of active ML models",
            "operationId": "getModels",
            "security": [{"BearerAuth": []}],
            "responses": {
              "200": {
                "description": "List of active models",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": {
                        "$ref": "#/components/schemas/ModelInfo"
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/metrics": {
          "get": {
            "tags": ["Metrics"],
            "summary": "Get performance metrics",
            "description": "Get system performance metrics",
            "operationId": "getMetrics",
            "security": [{"BearerAuth": []}],
            "responses": {
              "200": {
                "description": "Performance metrics",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/MetricsResponse"
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/auth/login": {
          "post": {
            "tags": ["Authentication"],
            "summary": "User login",
            "description": "Authenticate user and get access token",
            "operationId": "login",
            "requestBody": {
              "required": true,
              "content": {
                "application/json": {
                  "schema": {
                    "$ref": "#/components/schemas/LoginRequest"
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "Login successful",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/AuthToken"
                    }
                  }
                }
              },
              "401": {
                "description": "Invalid credentials",
                "content": {
                  "application/json": {
                    "schema": {
                      "$ref": "#/components/schemas/ErrorResponse"
                    }
                  }
                }
              }
            }
          }
        }
      },
      "components": {
        "securitySchemes": {
          "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT"
          }
        },
        "schemas": {
          "PredictionRequest": {
            "type": "object",
            "required": ["symbol", "timeHorizon", "modelType", "features"],
            "properties": {
              "symbol": {
                "type": "string",
                "description": "Cryptocurrency trading pair symbol",
                "example": "BTC-USD"
              },
              "timeHorizon": {
                "type": "number",
                "description": "Prediction time horizon in seconds",
                "example": 300
              },
              "modelType": {
                "type": "string",
                "enum": ["PRICE_PREDICTION", "VOLATILITY_PREDICTION", "TREND_CLASSIFICATION", "PATTERN_RECOGNITION"],
                "description": "Type of ML model to use"
              },
              "features": {
                "type": "object",
                "additionalProperties": {
                  "type": "number"
                },
                "description": "Input features for the model",
                "example": {
                  "price": 50000.0,
                  "volatility": 0.02,
                  "trend_strength": 0.1
                }
              }
            }
          },
          "PredictionResponse": {
            "type": "object",
            "properties": {
              "prediction": {
                "type": "number",
                "description": "Predicted value",
                "example": 51000.0
              },
              "confidence": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Confidence score",
                "example": 0.85
              },
              "uncertainty": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Uncertainty measure",
                "example": 0.1
              },
              "modelVersion": {
                "type": "string",
                "description": "Model version used",
                "example": "1.0.0"
              },
              "timestamp": {
                "type": "string",
                "format": "date-time",
                "description": "Prediction timestamp"
              },
              "symbol": {
                "type": "string",
                "description": "Trading pair symbol",
                "example": "BTC-USD"
              },
              "timeHorizon": {
                "type": "number",
                "description": "Time horizon in seconds",
                "example": 300
              }
            }
          },
          "BatchPredictionRequest": {
            "type": "object",
            "required": ["requests"],
            "properties": {
              "requests": {
                "type": "array",
                "items": {
                  "$ref": "#/components/schemas/PredictionRequest"
                }
              }
            }
          },
          "PatternDetectionRequest": {
            "type": "object",
            "required": ["symbol"],
            "properties": {
              "symbol": {
                "type": "string",
                "description": "Trading pair symbol",
                "example": "ETH-USD"
              },
              "patternTypes": {
                "type": "array",
                "items": {
                  "type": "string",
                  "enum": ["head_and_shoulders", "double_top", "double_bottom", "triangle", "flag", "pennant", "wedge"]
                },
                "description": "Specific pattern types to detect"
              },
              "timeRange": {
                "$ref": "#/components/schemas/TimeRange"
              }
            }
          },
          "PatternResponse": {
            "type": "object",
            "properties": {
              "patternId": {
                "type": "string",
                "description": "Unique pattern identifier"
              },
              "patternType": {
                "type": "string",
                "description": "Type of detected pattern"
              },
              "symbol": {
                "type": "string",
                "description": "Trading pair symbol"
              },
              "startTime": {
                "type": "string",
                "format": "date-time",
                "description": "Pattern start time"
              },
              "endTime": {
                "type": "string",
                "format": "date-time",
                "description": "Pattern end time"
              },
              "confidence": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Pattern confidence score"
              },
              "completionScore": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Pattern completion score"
              },
              "priceTarget": {
                "type": "number",
                "description": "Predicted price target"
              },
              "stopLoss": {
                "type": "number",
                "description": "Recommended stop loss level"
              },
              "marketConditions": {
                "type": "object",
                "additionalProperties": {
                  "type": "string"
                },
                "description": "Market conditions during pattern formation"
              }
            }
          },
          "TimeRange": {
            "type": "object",
            "required": ["from", "to"],
            "properties": {
              "from": {
                "type": "string",
                "format": "date-time",
                "description": "Start time"
              },
              "to": {
                "type": "string",
                "format": "date-time",
                "description": "End time"
              }
            }
          },
          "HealthResponse": {
            "type": "object",
            "properties": {
              "isHealthy": {
                "type": "boolean",
                "description": "Service health status"
              },
              "latency": {
                "type": "number",
                "description": "Average response latency in milliseconds"
              },
              "cacheHitRate": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Cache hit rate"
              },
              "activeModels": {
                "type": "array",
                "items": {
                  "type": "string"
                },
                "description": "List of active models"
              },
              "lastUpdated": {
                "type": "string",
                "format": "date-time",
                "description": "Last update timestamp"
              },
              "version": {
                "type": "string",
                "description": "API version"
              }
            }
          },
          "ModelInfo": {
            "type": "object",
            "properties": {
              "modelId": {
                "type": "string",
                "description": "Unique model identifier"
              },
              "version": {
                "type": "string",
                "description": "Model version"
              },
              "modelType": {
                "type": "string",
                "description": "Type of model"
              },
              "accuracy": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Model accuracy score"
              },
              "createdAt": {
                "type": "string",
                "format": "date-time",
                "description": "Model creation timestamp"
              },
              "isActive": {
                "type": "boolean",
                "description": "Whether model is currently active"
              }
            }
          },
          "MetricsResponse": {
            "type": "object",
            "properties": {
              "predictionsPerSecond": {
                "type": "number",
                "description": "Predictions processed per second"
              },
              "averageLatency": {
                "type": "number",
                "description": "Average prediction latency in milliseconds"
              },
              "errorRate": {
                "type": "number",
                "description": "Error rate percentage"
              },
              "memoryUsage": {
                "type": "number",
                "description": "Memory usage in MB"
              },
              "cpuUsage": {
                "type": "number",
                "description": "CPU usage percentage"
              },
              "cacheStats": {
                "$ref": "#/components/schemas/CacheStats"
              },
              "modelStats": {
                "type": "array",
                "items": {
                  "$ref": "#/components/schemas/ModelStats"
                }
              }
            }
          },
          "CacheStats": {
            "type": "object",
            "properties": {
              "hitRate": {
                "type": "number",
                "description": "Cache hit rate"
              },
              "missRate": {
                "type": "number",
                "description": "Cache miss rate"
              },
              "totalKeys": {
                "type": "integer",
                "description": "Total number of cached keys"
              },
              "memoryUsage": {
                "type": "integer",
                "description": "Memory usage in bytes"
              }
            }
          },
          "ModelStats": {
            "type": "object",
            "properties": {
              "modelId": {
                "type": "string",
                "description": "Model identifier"
              },
              "predictionsCount": {
                "type": "integer",
                "description": "Number of predictions made"
              },
              "averageAccuracy": {
                "type": "number",
                "description": "Average prediction accuracy"
              },
              "lastUsed": {
                "type": "string",
                "format": "date-time",
                "description": "Last time model was used"
              }
            }
          },
          "LoginRequest": {
            "type": "object",
            "required": ["username", "password"],
            "properties": {
              "username": {
                "type": "string",
                "description": "Username"
              },
              "password": {
                "type": "string",
                "description": "Password"
              }
            }
          },
          "AuthToken": {
            "type": "object",
            "properties": {
              "token": {
                "type": "string",
                "description": "JWT access token"
              },
              "expiresAt": {
                "type": "string",
                "format": "date-time",
                "description": "Token expiration time"
              },
              "permissions": {
                "type": "array",
                "items": {
                  "type": "string"
                },
                "description": "User permissions"
              }
            }
          },
          "ErrorResponse": {
            "type": "object",
            "properties": {
              "error": {
                "type": "string",
                "description": "Error type"
              },
              "code": {
                "type": "string",
                "description": "Error code"
              },
              "message": {
                "type": "string",
                "description": "Error message"
              },
              "timestamp": {
                "type": "string",
                "format": "date-time",
                "description": "Error timestamp"
              },
              "requestId": {
                "type": "string",
                "description": "Request identifier"
              }
            }
          }
        }
      },
      "tags": [
        {
          "name": "Predictions",
          "description": "ML-powered price and volatility predictions"
        },
        {
          "name": "Patterns",
          "description": "Technical chart pattern detection"
        },
        {
          "name": "Health",
          "description": "Service health and monitoring"
        },
        {
          "name": "Models",
          "description": "ML model management"
        },
        {
          "name": "Metrics",
          "description": "Performance metrics and statistics"
        },
        {
          "name": "Authentication",
          "description": "User authentication and authorization"
        }
      ]
    }
    """

    public static func generateDocumentation() -> String {
        return spec
    }

    public static func saveToFile(at path: String) throws {
        let data = spec.data(using: .utf8)!
        try data.write(to: URL(fileURLWithPath: path))
    }
}
