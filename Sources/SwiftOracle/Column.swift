import Foundation



public struct Column: Identifiable {
    public var id = UUID()
    
    public let name: String
    public let type: DataTypes
    public init(name: String, type: DataTypes) {
        self.name = name
        self.type = type
   }
}
