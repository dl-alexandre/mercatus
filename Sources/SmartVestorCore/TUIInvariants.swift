import Foundation

public enum TUIInvariants {
    public static func validateUniqueIDs(_ root: TUIRenderable, visited: inout Set<AnyHashable>) -> [String] {
        var errors: [String] = []

        if visited.contains(root.id) {
            errors.append("Duplicate ID found: \(root.id)")
        }
        visited.insert(root.id)

        for child in root.children() {
            errors.append(contentsOf: validateUniqueIDs(child, visited: &visited))
        }

        return errors
    }

    public static func validateMeasureThenRender(_ component: TUIRenderable, in size: Size, at origin: Point) -> [String] {
        var errors: [String] = []

        let measured = component.measure(in: size)
        let bounds = Rect(origin: origin, size: measured)

        if bounds.origin.x < 0 || bounds.origin.y < 0 {
            errors.append("Component \(component.id): render origin (\(bounds.origin.x), \(bounds.origin.y)) is negative")
        }

        if bounds.origin.x + bounds.size.width > size.width {
            errors.append("Component \(component.id): render exceeds width (\(bounds.origin.x + bounds.size.width) > \(size.width))")
        }

        if bounds.origin.y + bounds.size.height > size.height {
            errors.append("Component \(component.id): render exceeds height (\(bounds.origin.y + bounds.size.height) > \(size.height))")
        }

        return errors
    }

    public static func validateLayoutBounds(_ container: TUIRenderable, in size: Size) -> [String] {
        var errors: [String] = []

        let parentMeasured = container.measure(in: size)
        var childHeightSum = 0

        for child in container.children() {
            let childMeasured = child.measure(in: size)
            childHeightSum += childMeasured.height
        }

        if childHeightSum > parentMeasured.height {
            errors.append("Container \(container.id): children total height (\(childHeightSum)) exceeds parent (\(parentMeasured.height))")
        }

        return errors
    }

    public static func validateTree(_ root: TUIRenderable, in size: Size, at origin: Point = .zero) -> [String] {
        var errors: [String] = []
        var visitedIDs: Set<AnyHashable> = []

        errors.append(contentsOf: validateUniqueIDs(root, visited: &visitedIDs))
        errors.append(contentsOf: validateMeasureThenRender(root, in: size, at: origin))
        errors.append(contentsOf: validateLayoutBounds(root, in: size))

        var stack: [(TUIRenderable, Point)] = [(root, origin)]
        while let (component, componentOrigin) = stack.popLast() {
            let measured = component.measure(in: size)
            var currentY = componentOrigin.y

            for child in component.children() {
                let childMeasured = child.measure(in: Size(width: size.width - componentOrigin.x, height: size.height - currentY))
                let childOrigin = Point(x: componentOrigin.x, y: currentY)

                errors.append(contentsOf: validateMeasureThenRender(child, in: size, at: childOrigin))
                errors.append(contentsOf: validateLayoutBounds(child, in: size))

                stack.append((child, childOrigin))
                currentY += childMeasured.height
            }
        }

        return errors
    }
}
