import XCTest
@testable import Aria

final class AriaTests: XCTestCase {

    // MARK: - Model Tests

    func testAttentionItemUrgency() {
        let item = AttentionItem(
            type: .urgentEmail,
            title: "Test Email",
            urgency: 0.8,
            source: .email
        )

        XCTAssertEqual(item.urgency, 0.8)
        XCTAssertEqual(item.icon, "envelope.badge")
    }

    func testTaskPriorityCalculation() {
        let priority = AriaTask.calculatePriority(
            dueDate: Date().addingTimeInterval(3600), // 1 hour from now
            source: .email,
            contextPeople: ["John", "Jane"],
            estimatedMinutes: 30,
            isBlocking: true,
            isBlocked: false,
            userPatternScore: 0.7
        )

        XCTAssertGreaterThan(priority, 70)
    }

    func testTaskUrgencyWhenOverdue() {
        var task = AriaTask(
            title: "Overdue task",
            dueDate: Date().addingTimeInterval(-3600), // 1 hour ago
            priority: 50
        )

        XCTAssertTrue(task.isOverdue)
        XCTAssertGreaterThan(task.urgency, 0.7)
    }

    func testEmailPriorityCalculation() {
        let priority = Email.calculatePriority(
            senderImportance: 0.9,
            hasDeadline: true,
            requiresResponse: true,
            isThread: true,
            unreadInThread: 3,
            keywords: ["urgent", "deadline"]
        )

        XCTAssertGreaterThan(priority, 80)
    }

    // MARK: - Calendar Tests

    func testEventConflictDetection() {
        let event1 = CalendarEvent(
            provider: .apple,
            providerEventId: "1",
            calendarId: "cal",
            title: "Meeting 1",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )

        let event2 = CalendarEvent(
            provider: .apple,
            providerEventId: "2",
            calendarId: "cal",
            title: "Meeting 2",
            startDate: Date().addingTimeInterval(1800), // Overlaps
            endDate: Date().addingTimeInterval(5400)
        )

        XCTAssertTrue(event1.conflicts(with: event2))
    }

    func testEventNoConflict() {
        let event1 = CalendarEvent(
            provider: .apple,
            providerEventId: "1",
            calendarId: "cal",
            title: "Meeting 1",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )

        let event2 = CalendarEvent(
            provider: .apple,
            providerEventId: "2",
            calendarId: "cal",
            title: "Meeting 2",
            startDate: Date().addingTimeInterval(7200), // No overlap
            endDate: Date().addingTimeInterval(10800)
        )

        XCTAssertFalse(event1.conflicts(with: event2))
    }

    // MARK: - Contact Tests

    func testContactMatching() {
        let contact = AriaContact(
            firstName: "John",
            lastName: "Smith",
            nickname: "Johnny",
            emails: [ContactEmail(email: "john@example.com", label: "work", isPrimary: true)]
        )

        XCTAssertTrue(contact.matches(query: "John"))
        XCTAssertTrue(contact.matches(query: "Smith"))
        XCTAssertTrue(contact.matches(query: "Johnny"))
        XCTAssertTrue(contact.matches(query: "john@example"))
        XCTAssertFalse(contact.matches(query: "Jane"))
    }

    func testContactShouldReachOut() {
        var contact = AriaContact(
            firstName: "Mom",
            lastName: "",
            communicationFrequency: .weekly,
            lastContactDate: Date().addingTimeInterval(-86400 * 14) // 14 days ago
        )

        XCTAssertTrue(contact.shouldReachOut)
    }

    // MARK: - Vector Search Tests

    func testCosineSimilarity() async {
        let vectorSearch = VectorSearch.shared

        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]

        let similarity = await vectorSearch.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonal() async {
        let vectorSearch = VectorSearch.shared

        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]

        let similarity = await vectorSearch.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001)
    }

    // MARK: - Intent Classification Tests

    func testLocalIntentClassification() async {
        let classifier = LocalIntentClassifier()

        let result = await classifier.classify("read my emails")
        XCTAssertEqual(result.intent, .readEmail)
        XCTAssertGreaterThan(result.confidence, 0.7)
    }

    func testCalendarIntentClassification() async {
        let classifier = LocalIntentClassifier()

        let result = await classifier.classify("what's on my calendar today")
        XCTAssertEqual(result.intent, .checkCalendar)
    }

    func testCancelIntentClassification() async {
        let classifier = LocalIntentClassifier()

        let result = await classifier.classify("never mind")
        XCTAssertEqual(result.intent, .cancel)
    }

    // MARK: - Shopping Tests

    func testShoppingCartOperations() async {
        var cart = ShoppingCart(items: [])

        let item1 = CartItem(productId: "1", name: "Milk", quantity: 1, estimatedPrice: 4.99)
        let item2 = CartItem(productId: "2", name: "Bread", quantity: 2, estimatedPrice: 3.99)

        cart.add(item1)
        cart.add(item2)

        XCTAssertEqual(cart.itemCount, 3)
        XCTAssertEqual(cart.estimatedTotal, 8.98)

        cart.remove(productId: "1")
        XCTAssertEqual(cart.itemCount, 2)
    }

    func testPurchasePatternReorder() {
        let pattern = PurchasePattern(
            productId: "1",
            productName: "Milk",
            averageFrequencyDays: 7,
            lastPurchaseDate: Date().addingTimeInterval(-86400 * 8), // 8 days ago
            averageQuantity: 1,
            totalPurchases: 10
        )

        XCTAssertTrue(pattern.shouldSuggestReorder)
    }

    // MARK: - Banking Tests

    func testRecurringBillDetection() {
        let bill = RecurringBill(
            id: UUID(),
            merchantName: "Netflix",
            amount: 15.99,
            frequency: .monthly,
            nextDueDate: Date().addingTimeInterval(86400 * 3), // 3 days from now
            lastPaidDate: Date().addingTimeInterval(-86400 * 27),
            accountId: "checking",
            category: .entertainment,
            isAutoPay: true
        )

        XCTAssertTrue(bill.isUpcoming)
        XCTAssertFalse(bill.isPastDue)
    }

    func testTransactionCategorization() {
        let transaction = Transaction(
            plaidTransactionId: "1",
            accountId: "checking",
            name: "NETFLIX.COM",
            merchantName: "Netflix",
            amount: 15.99,
            date: Date(),
            primaryCategory: .entertainment
        )

        XCTAssertTrue(transaction.isExpense)
        XCTAssertEqual(transaction.primaryCategory.icon, "film")
    }
}
