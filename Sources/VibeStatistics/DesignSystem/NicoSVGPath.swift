import CoreGraphics
import Foundation

/// Parses the original Figma vector paths into Core Graphics paths (no glyph substitution).
enum NicoSVGPath {
    private static var cache: [String: CGPath] = [:]
    private static let regex = try! NSRegularExpression(pattern: "[a-zA-Z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
    static func parse(_ source: String) -> CGPath {
        if let path = cache[source] { return path }
        let ns = source as NSString
        let tokens = regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        let path = CGMutablePath()
        var i = 0, command = "", previousCommand = ""
        var point = CGPoint.zero, start = CGPoint.zero, control = CGPoint.zero
        func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if Double(tokens[i]) == nil { command = tokens[i]; i += 1 }
            let relative = command == command.lowercased()
            let c = command.uppercased()
            let count = ["M":2,"L":2,"H":1,"V":1,"C":6,"S":4,"Q":4,"T":2,"A":7,"Z":0][c]
            guard let count, i + count <= tokens.count else { break }
            if count > 0 && tokens[i..<(i+count)].contains(where: { Double($0) == nil }) { break }
            let origin = relative ? point : .zero
            func pair() -> CGPoint { CGPoint(x: number() + origin.x, y: number() + origin.y) }
            switch c {
            case "M": point = pair(); start = point; path.move(to: point); command = relative ? "l" : "L"
            case "L": point = pair(); path.addLine(to: point)
            case "H": point.x = number() + origin.x; path.addLine(to: point)
            case "V": point.y = number() + origin.y; path.addLine(to: point)
            case "C": let a = pair(), b = pair(), end = pair(); path.addCurve(to: end, control1: a, control2: b); control = b; point = end
            case "S":
                let a = ["C","S"].contains(previousCommand) ? CGPoint(x: 2*point.x-control.x,y:2*point.y-control.y) : point
                let b = pair(), end = pair(); path.addCurve(to: end, control1: a, control2: b); control = b; point = end
            case "Q": let a = pair(), end = pair(); path.addQuadCurve(to: end, control: a); control = a; point = end
            case "T":
                let a = ["Q","T"].contains(previousCommand) ? CGPoint(x:2*point.x-control.x,y:2*point.y-control.y) : point
                let end = pair(); path.addQuadCurve(to: end, control: a); control = a; point = end
            case "A":
                let rx = number(), ry = number(), rotation = number(), large = number() != 0, sweep = number() != 0, end = pair()
                arc(path, from: point, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep); point = end
            case "Z": path.closeSubpath(); point = start; command = ""
            default: break
            }
            previousCommand = c
        }
        cache[source] = path
        return path
    }
    private static func arc(_ path: CGMutablePath, from: CGPoint, to: CGPoint, rx rawRX: CGFloat, ry rawRY: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        guard from != to else { return }
        var rx = abs(rawRX), ry = abs(rawRY)
        guard rx > 0, ry > 0 else { path.addLine(to: to); return }
        let phi = rotation * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (from.x-to.x)/2, dy = (from.y-to.y)/2
        let xp = cp*dx+sp*dy, yp = -sp*dx+cp*dy
        let scale = xp*xp/(rx*rx)+yp*yp/(ry*ry)
        if scale > 1 { rx *= sqrt(scale); ry *= sqrt(scale) }
        let numerator = max(0,rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp)
        let denominator = rx*rx*yp*yp+ry*ry*xp*xp
        let coefficient = (large == sweep ? -1.0 : 1.0) * sqrt(numerator/max(denominator,0.0000001))
        let cxp = coefficient*rx*yp/ry, cyp = -coefficient*ry*xp/rx
        let cx = cp*cxp-sp*cyp+(from.x+to.x)/2, cy = sp*cxp+cp*cyp+(from.y+to.y)/2
        let ux = (xp-cxp)/rx, uy = (yp-cyp)/ry, vx = (-xp-cxp)/rx, vy = (-yp-cyp)/ry
        let start = atan2(uy,ux)
        var delta = atan2(ux*vy-uy*vx,ux*vx+uy*vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1,Int(ceil(abs(delta)/(.pi/2))))
        func transform(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x:cx+rx*cp*x-ry*sp*y,y:cy+rx*sp*x+ry*cp*y) }
        for i in 0..<segments {
            let a = start+delta*CGFloat(i)/CGFloat(segments), b = start+delta*CGFloat(i+1)/CGFloat(segments)
            let k = 4/3*tan((b-a)/4)
            path.addCurve(to: transform(cos(b),sin(b)), control1: transform(cos(a)-k*sin(a),sin(a)+k*cos(a)), control2: transform(cos(b)+k*sin(b),sin(b)-k*cos(b)))
        }
    }
}
