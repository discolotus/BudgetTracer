import Foundation

struct PlaidLinkTokenRequest: Encodable {
    var clientID: String
    var secret: String
    var clientName: String
    var user: PlaidLinkUser
    var products: [String]
    var countryCodes: [String]
    var language: String
    var webhook: String?
    var transactions: PlaidLinkTransactions

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case clientName = "client_name"
        case user
        case products
        case countryCodes = "country_codes"
        case language
        case webhook
        case transactions
    }
}

struct PlaidLinkUser: Encodable {
    var clientUserID: String

    enum CodingKeys: String, CodingKey {
        case clientUserID = "client_user_id"
    }
}

struct PlaidLinkTransactions: Encodable {
    var daysRequested: Int

    enum CodingKeys: String, CodingKey {
        case daysRequested = "days_requested"
    }
}

public struct PlaidLinkTokenResponse: Decodable, Hashable, Sendable {
    public var linkToken: String
    public var expiration: String
    public var requestID: String?

    public init(linkToken: String, expiration: String, requestID: String?) {
        self.linkToken = linkToken
        self.expiration = expiration
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
        case expiration
        case requestID = "request_id"
    }
}

struct PlaidSandboxPublicTokenRequest: Encodable {
    var clientID: String
    var secret: String
    var institutionID: String
    var initialProducts: [String]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case institutionID = "institution_id"
        case initialProducts = "initial_products"
    }
}

public struct PlaidSandboxPublicTokenResponse: Decodable, Hashable, Sendable {
    public var publicToken: String
    public var requestID: String?

    public init(publicToken: String, requestID: String?) {
        self.publicToken = publicToken
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case requestID = "request_id"
    }
}

struct PlaidPublicTokenExchangeRequest: Encodable {
    var clientID: String
    var secret: String
    var publicToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case publicToken = "public_token"
    }
}

public struct PlaidPublicTokenExchangeResponse: Decodable, Hashable, Sendable {
    public var accessToken: String
    public var itemID: String
    public var requestID: String?

    public init(accessToken: String, itemID: String, requestID: String?) {
        self.accessToken = accessToken
        self.itemID = itemID
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemID = "item_id"
        case requestID = "request_id"
    }
}

struct PlaidTransactionsSyncRequest: Encodable {
    var clientID: String
    var secret: String
    var accessToken: String
    var cursor: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case accessToken = "access_token"
        case cursor
    }
}

struct PlaidAccountsGetRequest: Encodable {
    var clientID: String
    var secret: String
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case secret
        case accessToken = "access_token"
    }
}

public struct PlaidAccountsGetResponse: Decodable, Hashable, Sendable {
    public var accounts: [PlaidAccount]
    public var requestID: String?

    public init(accounts: [PlaidAccount], requestID: String?) {
        self.accounts = accounts
        self.requestID = requestID
    }

    public static let empty = PlaidAccountsGetResponse(accounts: [], requestID: nil)

    enum CodingKeys: String, CodingKey {
        case accounts
        case requestID = "request_id"
    }
}

public struct PlaidTransactionsSyncResponse: Decodable, Hashable, Sendable {
    public var accounts: [PlaidAccount]
    public var added: [PlaidTransaction]
    public var modified: [PlaidTransaction]
    public var removed: [PlaidRemovedTransaction]
    public var nextCursor: String
    public var hasMore: Bool
    public var requestID: String?

    public init(
        accounts: [PlaidAccount],
        added: [PlaidTransaction],
        modified: [PlaidTransaction],
        removed: [PlaidRemovedTransaction],
        nextCursor: String,
        hasMore: Bool,
        requestID: String?
    ) {
        self.accounts = accounts
        self.added = added
        self.modified = modified
        self.removed = removed
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.requestID = requestID
    }

    public static let empty = PlaidTransactionsSyncResponse(
        accounts: [],
        added: [],
        modified: [],
        removed: [],
        nextCursor: "",
        hasMore: false,
        requestID: nil
    )

    mutating func append(_ page: PlaidTransactionsSyncResponse) {
        accounts.append(contentsOf: page.accounts)
        added.append(contentsOf: page.added)
        modified.append(contentsOf: page.modified)
        removed.append(contentsOf: page.removed)
        nextCursor = page.nextCursor
        hasMore = page.hasMore
        requestID = page.requestID
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case added
        case modified
        case removed
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case requestID = "request_id"
    }
}

public struct PlaidAccount: Decodable, Hashable, Sendable {
    public var accountID: String
    public var balances: PlaidBalances
    public var mask: String?
    public var name: String
    public var officialName: String?
    public var type: String
    public var subtype: String?

    public init(
        accountID: String,
        balances: PlaidBalances,
        mask: String?,
        name: String,
        officialName: String?,
        type: String,
        subtype: String?
    ) {
        self.accountID = accountID
        self.balances = balances
        self.mask = mask
        self.name = name
        self.officialName = officialName
        self.type = type
        self.subtype = subtype
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case balances
        case mask
        case name
        case officialName = "official_name"
        case type
        case subtype
    }
}

public struct PlaidBalances: Decodable, Hashable, Sendable {
    public var available: Decimal?
    public var current: Decimal?
    public var isoCurrencyCode: String?
    public var unofficialCurrencyCode: String?

    public init(available: Decimal?, current: Decimal?, isoCurrencyCode: String?, unofficialCurrencyCode: String?) {
        self.available = available
        self.current = current
        self.isoCurrencyCode = isoCurrencyCode
        self.unofficialCurrencyCode = unofficialCurrencyCode
    }

    enum CodingKeys: String, CodingKey {
        case available
        case current
        case isoCurrencyCode = "iso_currency_code"
        case unofficialCurrencyCode = "unofficial_currency_code"
    }
}

public struct PlaidTransaction: Decodable, Hashable, Sendable {
    public var transactionID: String
    public var accountID: String
    public var pendingTransactionID: String?
    public var name: String
    public var merchantName: String?
    public var date: String
    public var datetime: String?
    public var authorizedDate: String?
    public var authorizedDatetime: String?
    public var amount: Decimal
    public var isoCurrencyCode: String?
    public var unofficialCurrencyCode: String?
    public var paymentChannel: String?
    public var pending: Bool
    public var personalFinanceCategory: PlaidPersonalFinanceCategory?

    public init(
        transactionID: String,
        accountID: String,
        pendingTransactionID: String?,
        name: String,
        merchantName: String?,
        date: String,
        datetime: String? = nil,
        authorizedDate: String?,
        authorizedDatetime: String? = nil,
        amount: Decimal,
        isoCurrencyCode: String?,
        unofficialCurrencyCode: String?,
        paymentChannel: String?,
        pending: Bool,
        personalFinanceCategory: PlaidPersonalFinanceCategory?
    ) {
        self.transactionID = transactionID
        self.accountID = accountID
        self.pendingTransactionID = pendingTransactionID
        self.name = name
        self.merchantName = merchantName
        self.date = date
        self.datetime = datetime
        self.authorizedDate = authorizedDate
        self.authorizedDatetime = authorizedDatetime
        self.amount = amount
        self.isoCurrencyCode = isoCurrencyCode
        self.unofficialCurrencyCode = unofficialCurrencyCode
        self.paymentChannel = paymentChannel
        self.pending = pending
        self.personalFinanceCategory = personalFinanceCategory
    }

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case accountID = "account_id"
        case pendingTransactionID = "pending_transaction_id"
        case name
        case merchantName = "merchant_name"
        case date
        case datetime
        case authorizedDate = "authorized_date"
        case authorizedDatetime = "authorized_datetime"
        case amount
        case isoCurrencyCode = "iso_currency_code"
        case unofficialCurrencyCode = "unofficial_currency_code"
        case paymentChannel = "payment_channel"
        case pending
        case personalFinanceCategory = "personal_finance_category"
    }
}

public struct PlaidPersonalFinanceCategory: Decodable, Hashable, Sendable {
    public var primary: String?
    public var detailed: String?

    public init(primary: String?, detailed: String?) {
        self.primary = primary
        self.detailed = detailed
    }
}

public struct PlaidRemovedTransaction: Decodable, Hashable, Sendable {
    public var transactionID: String
    public var accountID: String?

    public init(transactionID: String, accountID: String?) {
        self.transactionID = transactionID
        self.accountID = accountID
    }

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case accountID = "account_id"
    }
}
