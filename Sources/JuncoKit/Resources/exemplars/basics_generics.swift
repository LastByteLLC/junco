// Generic function and generic type with constraints
import Foundation

func firstMatch<T: Equatable>(in array: [T], matching value: T) -> Int? {
    array.firstIndex(of: value)
}

struct Stack<Element> {
    private var items: [Element] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    mutating func push(_ item: Element) {
        items.append(item)
    }

    mutating func pop() -> Element? {
        items.popLast()
    }

    func peek() -> Element? {
        items.last
    }
}

extension Stack where Element: CustomStringConvertible {
    func printAll() {
        for item in items.reversed() {
            print(item.description)
        }
    }
}

var stack = Stack<Int>()
stack.push(10)
stack.push(20)
let top = stack.pop() // 20
