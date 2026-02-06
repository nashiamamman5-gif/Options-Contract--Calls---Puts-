(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-expired (err u103))
(define-constant err-not-expired (err u104))
(define-constant err-already-exercised (err u105))
(define-constant err-insufficient-payment (err u106))
(define-constant err-invalid-strike (err u107))
(define-constant err-invalid-expiry (err u108))
(define-constant err-not-owner (err u109))
(define-constant err-oracle-not-set (err u110))
(define-constant err-order-not-found (err u111))
(define-constant err-not-for-sale (err u112))
(define-constant err-insufficient-price (err u113))

(define-data-var option-nonce uint u0)
(define-data-var oracle-price uint u0)
(define-data-var oracle-timestamp uint u0)

(define-data-var pool-balance uint u0)
(define-data-var lp-token-supply uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var implied-volatility uint u30)

(define-data-var order-nonce uint u0)

(define-map options
  uint
  {
    owner: principal,
    option-type: (string-ascii 4),
    strike-price: uint,
    premium: uint,
    expiry-block: uint,
    exercised: bool,
    settled: bool,
    payout: uint,
  }
)

(define-map lp-balances
  principal
  uint
)

(define-map sell-orders
  uint
  {
    option-id: uint,
    seller: principal,
    asking-price: uint,
    active: bool,
  }
)

(define-read-only (get-option (option-id uint))
  (map-get? options option-id)
)

(define-read-only (get-oracle-price)
  (ok {
    price: (var-get oracle-price),
    timestamp: (var-get oracle-timestamp),
  })
)

(define-read-only (get-option-nonce)
  (ok (var-get option-nonce))
)

(define-read-only (get-pool-stats)
  (ok {
    pool-balance: (var-get pool-balance),
    lp-token-supply: (var-get lp-token-supply),
    total-fees: (var-get total-fees-collected),
    implied-volatility: (var-get implied-volatility),
  })
)

(define-read-only (get-lp-balance (user principal))
  (ok (default-to u0 (map-get? lp-balances user)))
)

(define-read-only (calculate-premium
    (strike-price uint)
    (expiry-block uint)
  )
  (let (
      (current-price (var-get oracle-price))
      (blocks-to-expiry (if (> expiry-block stacks-block-height)
        (- expiry-block stacks-block-height)
        u1
      ))
      (price-diff (if (> strike-price current-price)
        (- strike-price current-price)
        (- current-price strike-price)
      ))
      (volatility (var-get implied-volatility))
      (time-factor (/ blocks-to-expiry u1000))
      (base-premium (/ (* price-diff time-factor volatility) u10000))
      (minimum-premium (/ strike-price u100))
    )
    (ok (if (> base-premium minimum-premium)
      base-premium
      minimum-premium
    ))
  )
)

(define-public (set-oracle-price (price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set oracle-price price)
    (var-set oracle-timestamp stacks-block-height)
    (ok true)
  )
)

(define-public (create-call-option
    (strike-price uint)
    (premium uint)
    (expiry-block uint)
  )
  (let ((option-id (var-get option-nonce)))
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)

    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

    (map-set options option-id {
      owner: tx-sender,
      option-type: "call",
      strike-price: strike-price,
      premium: premium,
      expiry-block: expiry-block,
      exercised: false,
      settled: false,
      payout: u0,
    })

    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (create-put-option
    (strike-price uint)
    (premium uint)
    (expiry-block uint)
  )
  (let ((option-id (var-get option-nonce)))
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)

    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

    (map-set options option-id {
      owner: tx-sender,
      option-type: "put",
      strike-price: strike-price,
      premium: premium,
      expiry-block: expiry-block,
      exercised: false,
      settled: false,
      payout: u0,
    })

    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (exercise-option (option-id uint))
  (let (
      (option-data (unwrap! (map-get? options option-id) err-not-found))
      (current-price (var-get oracle-price))
      (strike (get strike-price option-data))
      (option-type (get option-type option-data))
      (payout u0)
    )
    (asserts! (is-eq (get owner option-data) tx-sender) err-not-owner)
    (asserts! (>= stacks-block-height (get expiry-block option-data))
      err-not-expired
    )
    (asserts! (not (get exercised option-data)) err-already-exercised)
    (asserts! (> current-price u0) err-oracle-not-set)

    (let ((calculated-payout (if (is-eq option-type "call")
        (if (> current-price strike)
          (- current-price strike)
          u0
        )
        (if (> strike current-price)
          (- strike current-price)
          u0
        )
      )))
      (map-set options option-id
        (merge option-data {
          exercised: true,
          settled: true,
          payout: calculated-payout,
        })
      )

      (if (> calculated-payout u0)
        (try! (as-contract (stx-transfer? calculated-payout tx-sender (get owner option-data))))
        true
      )

      (ok calculated-payout)
    )
  )
)

(define-public (transfer-option
    (option-id uint)
    (recipient principal)
  )
  (let ((option-data (unwrap! (map-get? options option-id) err-not-found)))
    (asserts! (is-eq (get owner option-data) tx-sender) err-not-owner)
    (asserts! (< stacks-block-height (get expiry-block option-data)) err-expired)
    (asserts! (not (get exercised option-data)) err-already-exercised)

    (map-set options option-id (merge option-data { owner: recipient }))

    (ok true)
  )
)

(define-public (deposit-liquidity (amount uint))
  (let (
      (current-pool (var-get pool-balance))
      (current-supply (var-get lp-token-supply))
      (user-balance (default-to u0 (map-get? lp-balances tx-sender)))
      (lp-tokens-to-mint (if (is-eq current-supply u0)
        amount
        (/ (* amount current-supply) current-pool)
      ))
    )
    (asserts! (> amount u0) err-insufficient-payment)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (var-set pool-balance (+ current-pool amount))
    (var-set lp-token-supply (+ current-supply lp-tokens-to-mint))
    (map-set lp-balances tx-sender (+ user-balance lp-tokens-to-mint))

    (ok lp-tokens-to-mint)
  )
)

(define-public (withdraw-liquidity (lp-tokens uint))
  (let (
      (user-balance (default-to u0 (map-get? lp-balances tx-sender)))
      (current-pool (var-get pool-balance))
      (current-supply (var-get lp-token-supply))
      (stx-to-return (/ (* lp-tokens current-pool) current-supply))
    )
    (asserts! (>= user-balance lp-tokens) err-insufficient-payment)
    (asserts! (> lp-tokens u0) err-insufficient-payment)

    (var-set pool-balance (- current-pool stx-to-return))
    (var-set lp-token-supply (- current-supply lp-tokens))
    (map-set lp-balances tx-sender (- user-balance lp-tokens))

    (try! (as-contract (stx-transfer? stx-to-return tx-sender tx-sender)))

    (ok stx-to-return)
  )
)

(define-public (buy-call-from-pool
    (strike-price uint)
    (expiry-block uint)
  )
  (let (
      (option-id (var-get option-nonce))
      (premium (unwrap! (calculate-premium strike-price expiry-block) err-oracle-not-set))
      (current-pool (var-get pool-balance))
    )
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (> (var-get oracle-price) u0) err-oracle-not-set)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)

    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

    (var-set pool-balance (+ current-pool premium))
    (var-set total-fees-collected (+ (var-get total-fees-collected) premium))

    (map-set options option-id {
      owner: tx-sender,
      option-type: "call",
      strike-price: strike-price,
      premium: premium,
      expiry-block: expiry-block,
      exercised: false,
      settled: false,
      payout: u0,
    })

    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (buy-put-from-pool
    (strike-price uint)
    (expiry-block uint)
  )
  (let (
      (option-id (var-get option-nonce))
      (premium (unwrap! (calculate-premium strike-price expiry-block) err-oracle-not-set))
      (current-pool (var-get pool-balance))
    )
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (> (var-get oracle-price) u0) err-oracle-not-set)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)

    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

    (var-set pool-balance (+ current-pool premium))
    (var-set total-fees-collected (+ (var-get total-fees-collected) premium))

    (map-set options option-id {
      owner: tx-sender,
      option-type: "put",
      strike-price: strike-price,
      premium: premium,
      expiry-block: expiry-block,
      exercised: false,
      settled: false,
      payout: u0,
    })

    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (set-implied-volatility (volatility uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set implied-volatility volatility)
    (ok true)
  )
)

(define-public (list-option-for-sale
    (option-id uint)
    (asking-price uint)
  )
  (let (
      (option-data (unwrap! (map-get? options option-id) err-not-found))
      (order-id (var-get order-nonce))
    )
    (asserts! (is-eq (get owner option-data) tx-sender) err-not-owner)
    (asserts! (< stacks-block-height (get expiry-block option-data)) err-expired)
    (asserts! (not (get exercised option-data)) err-already-exercised)
    (asserts! (> asking-price u0) err-insufficient-price)

    (map-set options option-id
      (merge option-data { owner: (as-contract tx-sender) })
    )

    (map-set sell-orders order-id {
      option-id: option-id,
      seller: tx-sender,
      asking-price: asking-price,
      active: true,
    })

    (var-set order-nonce (+ order-id u1))
    (ok order-id)
  )
)

(define-public (cancel-listing (order-id uint))
  (let (
      (order-data (unwrap! (map-get? sell-orders order-id) err-order-not-found))
      (option-id (get option-id order-data))
      (option-data (unwrap! (map-get? options option-id) err-not-found))
    )
    (asserts! (is-eq (get seller order-data) tx-sender) err-not-owner)
    (asserts! (get active order-data) err-not-for-sale)

    (map-set sell-orders order-id (merge order-data { active: false }))

    (map-set options option-id (merge option-data { owner: tx-sender }))

    (ok true)
  )
)

(define-public (buy-listed-option (order-id uint))
  (let (
      (order-data (unwrap! (map-get? sell-orders order-id) err-order-not-found))
      (option-id (get option-id order-data))
      (seller (get seller order-data))
      (asking-price (get asking-price order-data))
      (option-data (unwrap! (map-get? options option-id) err-not-found))
    )
    (asserts! (get active order-data) err-not-for-sale)
    (asserts! (>= (stx-get-balance tx-sender) asking-price)
      err-insufficient-payment
    )

    (try! (stx-transfer? asking-price tx-sender seller))

    (map-set sell-orders order-id (merge order-data { active: false }))

    (map-set options option-id (merge option-data { owner: tx-sender }))

    (ok option-id)
  )
)

(define-public (update-listing-price
    (order-id uint)
    (new-price uint)
  )
  (let ((order-data (unwrap! (map-get? sell-orders order-id) err-order-not-found)))
    (asserts! (is-eq (get seller order-data) tx-sender) err-not-owner)
    (asserts! (get active order-data) err-not-for-sale)
    (asserts! (> new-price u0) err-insufficient-price)

    (map-set sell-orders order-id (merge order-data { asking-price: new-price }))

    (ok true)
  )
)

(define-read-only (get-listing (order-id uint))
  (map-get? sell-orders order-id)
)

(define-read-only (get-order-nonce)
  (ok (var-get order-nonce))
)
