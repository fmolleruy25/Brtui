import XCTest
@testable import WordPress

private struct TestRoute: Route {
    let path: String
    let section: DeepLinkSection? = .mySite
    let source: DeepLinkSource = .link
    let action: NavigationAction = TestAction()
    let shouldTrack = false
    let jetpackPowered = false
}

private struct TestAction: NavigationAction {
    func perform(_ values: [String: String], source: UIViewController?, router: LinkRouter) {}
}

class RouteMatcherTests: XCTestCase {

    var matcher: RouteMatcher!
    var routes: [Route]!

    func testNoMatchingRoutes() {
        routes = [ TestRoute(path: "/me") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/hello")!)
        XCTAssert(matches.count == 0)
    }

    func testMatchingRouteWithSingleComponent() {
        routes = [ TestRoute(path: "/me"), TestRoute(path: "/me/account") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me")!) as [Route]
        XCTAssert(matches.first!.isEqual(to: routes.first!))
        XCTAssert(matches.count == 1)
    }

    func testMatchingRouteWithManyComponents() {
        routes = [ TestRoute(path: "/me"), TestRoute(path: "/me/account") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/account")!) as [Route]
        XCTAssert(matches.first!.isEqual(to: routes.last!))
        XCTAssert(matches.count == 1)
    }

    func testMultipleMatchingRoutes() {
        routes = [ TestRoute(path: "/me"), TestRoute(path: "/me") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me")!) as [Route]
        XCTAssert(matches.elementsEqual(routes, by: { $0.isEqual(to: $1) }))
    }

    func testMatchingRouteWithSingleFinalPlaceholder() {
        routes = [ TestRoute(path: "/me/:placeholder") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/hello")!) as [Route]
        XCTAssert(matches.first!.isEqual(to: routes.first!))
        XCTAssert(matches.count == 1)
    }

    // MARK: - Placeholders

    func testMatchedRoutesHaveTheOriginalURLAsAValue() {
        routes = [ TestRoute(path: "/me") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "https://wordpress.com/me")!)
        let values = matches.first!.values
        XCTAssert(values.count == 1)
        XCTAssertEqual(values[MatchedRouteURLComponentKey.url.rawValue], "https://wordpress.com/me")
    }

    func testMatchedRouteWithSinglePlaceholdersHasPopulatedValue() {
        routes = [ TestRoute(path: "/me/:account") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/bobsmith")!)
        let values = matches.first!.values
        XCTAssert(values.count == 2)
        XCTAssertEqual(values["account"], "bobsmith")
    }

    func testLongerRouteDoesntMatchPartial() {
        routes = [ TestRoute(path: "/me/:account/share/:type") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/bobsmith")!)
        XCTAssert(matches.count == 0)
    }

    func testMatchedRouteWithManyPlaceholders() {
        routes = [ TestRoute(path: "/me/:account/share/:type") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/bobsmith/share/group")!)
        let values = matches.first!.values
        XCTAssert(values.count == 3)
        XCTAssertEqual(values["account"], "bobsmith")
        XCTAssertEqual(values["type"], "group")
    }

    func testMultipleMatchedRouteWithManyPlaceholders() {
        routes = [ TestRoute(path: "/me/:account/share/:type"),
                   TestRoute(path: "/me/:account/share/"),
                   TestRoute(path: "/me/:account/share/:test") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "/me/bobsmith/share/group")!)
        XCTAssert(matches.count == 2)

        let values1 = matches.first!.values
        XCTAssert(values1.count == 3)

        let values2 = matches.last!.values
        XCTAssert(values2.count == 3)

        XCTAssertEqual(values1["account"], "bobsmith")
        XCTAssertEqual(values1["type"], "group")
        XCTAssertEqual(values2["account"], "bobsmith")
        XCTAssertEqual(values2["test"], "group")
    }

    // MARK: - Source query item

    func testRouteWithNoSourceQueryItem() {
        routes = [ TestRoute(path: "/stats") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "https://wordpress.com/stats")!)
        let values = matches.first!.values
        XCTAssert(values.count == 1)
        XCTAssertEqual(values[MatchedRouteURLComponentKey.url.rawValue], "https://wordpress.com/stats")
        XCTAssertNil(values[MatchedRouteURLComponentKey.source.rawValue])
    }

    func testRouteWithSourceQueryItem() {
        routes = [ TestRoute(path: "/stats") ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "https://wordpress.com/stats?source=widget")!)
        let match = matches.first!
        XCTAssert(match.values.count == 2)
        XCTAssertEqual(match.values[MatchedRouteURLComponentKey.source.rawValue], "widget")
        XCTAssertEqual(match.source, DeepLinkSource.widget)
    }

    func testStatsSubscribersRoute() {
        routes = [ StatsRoute.subscribers ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "https://wordpress.com/stats/subscribers/testsite.com")!)

        let match = matches.first!
        XCTAssertEqual(match.section, DeepLinkSection.stats)
        XCTAssertEqual(match.source, DeepLinkSource.link)
    }

    func testStatsSubscribersDayRoute() {
        routes = [ StatsRoute.daySubscribers ]
        matcher = RouteMatcher(routes: routes)

        let matches = matcher.routesMatching(URL(string: "https://wordpress.com/stats/subscribers/day/testsite.com")!)

        let match = matches.first!
        XCTAssertEqual(match.section, DeepLinkSection.stats)
        XCTAssertEqual(match.source, DeepLinkSource.link)
    }

    // MARK: - AppBanner

    func testAppBannerRouter() throws {
        // GIVEN a banner URL with a redirect in a fragment
        let route = "https://apps.wordpress.com/get/?campaign=qr-code-media#%2Fmedia%2F1234567"

        // WHEN
        routes = [AppBannerRoute()]
        matcher = RouteMatcher(routes: routes)
        let matches = matcher.routesMatching(URL(string: route)!)

        // THEN a match if found
        let match = try XCTUnwrap(matches.first)
        XCTAssert(match.values.count == 2)
        XCTAssertNotNil(match.values[MatchedRouteURLComponentKey.url.rawValue])
        XCTAssertEqual(match.values[MatchedRouteURLComponentKey.fragment.rawValue], "%2Fmedia%2F1234567")

        // WHEN invoking a URL
        var router = MockRouter(routes: [])
        router.completion = { url, source in
            // THEN it opens a universal link from a fragement and passes the campaign
            XCTAssertEqual(url, URL(string: "https://wordpress.com/media/1234567?campaign=qr-code-media"))
            XCTAssertEqual(source, DeepLinkSource.banner(campaign: "qr-code-media"))
        }
        AppBannerRoute().perform(match.values, router: router)
    }
}
