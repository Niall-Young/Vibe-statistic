import XCTest
import AppKit
@testable import VibeStatistics

final class NicoTests: XCTestCase {
    func testEveryTokenResolvesInEveryModeWithoutCycles() throws {
        XCTAssertEqual(Nico.variables.count, 360)
        XCTAssertEqual(NicoColorToken.allCases.count + NicoMetricToken.allCases.count + NicoStringToken.allCases.count, 360)
        XCTAssertEqual(Nico.collections.count, 8)
        for dark in [false,true] {
            for language in Nico.Language.allCases {
                for variable in Nico.variables {
                    let value = try Nico.resolve(variable.string("id"),mode:.init(dark:dark,language:language))
                    switch variable.string("resolvedType") {
                    case "COLOR":
                        let rgba = try XCTUnwrap(value as? [String:Any])
                        for channel in ["r","g","b","a"] {
                            XCTAssertTrue((0...1).contains(rgba.double(channel)),"\(variable.string("name")) \(channel)")
                        }
                    case "FLOAT": XCTAssertNotNil(value as? NSNumber)
                    case "STRING": XCTAssertNotNil(value as? String)
                    default: XCTFail("Unexpected token type")
                    }
                }
            }
        }
        XCTAssertThrowsError(try Nico.resolve("not-a-token"))
    }
    func testAliasAlphaAndNativeThemeAreNotAppliedTwice() {
        let source: [String:Any] = ["color":["r":0,"g":0,"b":0],"opacity":0.86,"boundVariables":["color":["id":"VariableID:1:224","type":"VARIABLE_ALIAS"]]]
        // Find the original text binding by name so the assertion follows its documented contract.
        var paint = source
        paint["boundVariables"] = ["color":["id":Nico.byName["--color-text"]!.string("id"),"type":"VARIABLE_ALIAS"]]
        let light = Nico.paintColor(paint,mode:.init())
        XCTAssertEqual(light.alphaComponent,0.86,accuracy:0.0001)
        let dark = Nico.paintColor(paint,mode:.init(dark:true))
        XCTAssertGreaterThan(dark.redComponent,light.redComponent)
        XCTAssertEqual(Nico.number("--border-radius-sm"),8)
        XCTAssertEqual(Nico.number("--font-size-sm"),14)
    }
    func testColorWithOpacityTokenKeepsItsPercentAlpha() {
        // interaction tokens nest the alias under "color" and carry a percent "opacity".
        let light = Nico.nsColor("--color-interaction-hover-negative",mode:.init())
        XCTAssertEqual(light.alphaComponent,0.04,accuracy:0.0001)
        XCTAssertGreaterThan(light.redComponent,0.9)
        let dark = Nico.nsColor("--color-interaction-hover-negative",mode:.init(dark:true))
        XCTAssertEqual(dark.alphaComponent,0.08,accuracy:0.0001)
    }
    func testCompleteComponentCoverageAndValidNativeGeometry() throws {
        var sets = 0, variants = 0, singles = 0
        for entry in Nico.inventory where !entry.objects("sets").isEmpty || !entry.objects("single").isEmpty {
            let page = NicoLibrary.page(entry.string("id"))
            sets += page.sets.count; singles += page.singles.count
            for set in page.sets {
                variants += set.variants.count
                XCTAssertEqual(Set(set.variants.map(\.id)).count,set.variants.count)
                let expected = try XCTUnwrap(entry.objects("sets").first { $0.string("id") == set.id })
                XCTAssertEqual(set.variants.count,Int(expected.double("count")))
                for variant in set.variants {
                    XCTAssertTrue(page.nodes.indices.contains(variant.root))
                    XCTAssertEqual(set.match(variant.properties)?.id,variant.id)
                }
            }
            for node in page.nodes {
                XCTAssertTrue(node.double("width").isFinite && node.double("height").isFinite)
                for child in node["children"] as? [Int] ?? [] { XCTAssertTrue(page.nodes.indices.contains(child)) }
                for path in node.objects("vectorPaths") {
                    XCTAssertFalse(NicoSVGPath.parse(path.string("data")).isEmpty)
                    XCTAssertFalse(NicoSVGPath.parse(path.string("data")).boundingBoxOfPath.isInfinite)
                }
                // Every Boolean in this source contains one flattened vector; no guessed boolean operation.
                if node.string("type") == "BOOLEAN_OPERATION" { XCTAssertEqual((node["children"] as? [Int])?.count,1) }
                for paint in node.objects("fills") { XCTAssertTrue(["SOLID","IMAGE","GRADIENT_LINEAR","GRADIENT_RADIAL"].contains(paint.string("type"))) }
            }
        }
        XCTAssertEqual(sets,45); XCTAssertEqual(variants,2506); XCTAssertEqual(singles,12)
    }
    func testAllButtonStateRecipesAndInputStatesExist() {
        for color in NicoButtonColor.allCases {
            for size in NicoSize.allCases {
                for kind in NicoButtonKind.allCases {
                    for state in ["normal","hover","selected","loading","disabled"] {
                        let props = ["color":color.rawValue,"size":size.rawValue,"kind":kind.rawValue,"capsule":"false","left icon":"false","right icon":"false","hover":String(state == "hover"),"selected":String(state == "selected"),"loading":String(state == "loading"),"disabled":String(state == "disabled")]
                        XCTAssertNotNil(NicoLibrary.component("Button",properties:props),"\(props)")
                    }
                }
            }
        }
        for size in NicoSize.allCases {
            for on in [false,true] {
                for disabled in [false,true] {
                    XCTAssertNotNil(NicoLibrary.component("Switch",properties:["size":size.rawValue,"switch":String(on),"disabled":String(disabled)]))
                }
            }
        }
    }
    func testStylesAndSourceAssetsAreComplete() throws {
        XCTAssertEqual(Nico.textStyles.count,54); XCTAssertEqual(Nico.paintStyles.count,6); XCTAssertEqual(Nico.effectStyles.count,9)
        for style in Nico.paintStyles {
            for paint in style.objects("paints") { XCTAssertNotNil(NicoImages.image(paint.string("imageHash")),style.string("name")) }
        }
        _ = Nico.registerFonts
        XCTAssertNotNil(NSFont(name:"Poppins-Regular",size:14))
        XCTAssertNotNil(NSFont(name:"Poppins-Medium",size:14))
        XCTAssertNotNil(NSFont(name:"Poppins-SemiBold",size:14))
    }
    func testSVGScientificNotationRelativeCurvesAndClosedPaths() {
        let path = NicoSVGPath.parse("M 1e1 10 l 10 0 v 10 h -10 Z")
        XCTAssertEqual(path.boundingBoxOfPath,CGRect(x:10,y:10,width:10,height:10))
        let curve = NicoSVGPath.parse("M0 0 Q10 20 20 0 T40 0")
        XCTAssertEqual(curve.boundingBoxOfPath.width,40,accuracy:0.001)
        let arc = NicoSVGPath.parse("M0 10 A10 10 0 0 1 20 10")
        XCTAssertEqual(arc.boundingBoxOfPath.width,20,accuracy:0.001)
    }
    func testBusinessSelectionRecipesExistForReachableStates() {
        for enabled in [false, true] {
            for selected in [false, true] {
                for hovering in [false, true] {
                    XCTAssertNotNil(NicoLibrary.component("Segmented item", properties: ["size": "md", "selected": String(selected), "label": "true", "icon": "false", "hover": String(enabled && hovering && !selected), "disabled": String(!enabled)]))
                }
            }
            for expanded in [false, true] {
                for hovering in [false, true] {
                    XCTAssertNotNil(NicoLibrary.component("Select", properties: ["size": "md", "filled": "true", "hover": String(enabled && hovering && !expanded), "focused": String(enabled && expanded), "read only": "false", "disabled": String(!enabled), "clear all": String(!enabled), "negative": "false"]))
                }
            }
        }
        XCTAssertNotNil(NicoLibrary.component("Menu", properties: [:]))
        for selected in [false, true] {
            for hovering in [false, true] {
                XCTAssertNotNil(NicoLibrary.component("Menu item", properties: ["size": "md", "selected": String(selected), "hover": String(hovering), "disabled": "false"]))
            }
        }
    }

}
