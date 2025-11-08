import Foundation

public class StochasticPriceEnvironment: Environment {
    public init() {}
    public let actionSpaceSize = 3  // 0: hold, 1: buy, 2: sell
    public let observationSpaceSize = 5  // price, volume, position, cash, portfolio_value

    private var price: Float = 100.0
    private var position: Int = 0
    private var cash: Float = 10000.0
    private var portfolioValue: Float = 10000.0

    public func reset() -> [Float] {
        price = 100.0
        position = 0
        cash = 10000.0
        portfolioValue = 10000.0
        return getObservation()
    }

    public func step(action: Int) -> (observation: [Float], reward: Float, done: Bool, info: [String: Any]) {
        // Simulate price change
        let priceChange = Float.random(in: -2.0...2.0)
        price += priceChange

        var reward: Float = 0.0
        let prevValue = portfolioValue

        switch action {
        case 1:  // buy
            if cash >= price {
                position += 1
                cash -= price
            }
        case 2:  // sell
            if position > 0 {
                position -= 1
                cash += price
            }
        default:  // hold
            break
        }

        portfolioValue = cash + Float(position) * price
        reward = portfolioValue - prevValue

        let done = portfolioValue <= 0 || portfolioValue >= 20000.0

        return (getObservation(), reward, done, [:])
    }

    private func getObservation() -> [Float] {
        [price, Float.random(in: 100.0...1000.0), Float(position), cash, portfolioValue]
    }
}
