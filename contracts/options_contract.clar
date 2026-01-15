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

(define-data-var option-nonce uint u0)
(define-data-var oracle-price uint u0)
(define-data-var oracle-timestamp uint u0)

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
    payout: uint
  }
)

(define-read-only (get-option (option-id uint))
  (map-get? options option-id)
)

(define-read-only (get-oracle-price)
  (ok {price: (var-get oracle-price), timestamp: (var-get oracle-timestamp)})
)

(define-read-only (get-option-nonce)
  (ok (var-get option-nonce))
)

(define-public (set-oracle-price (price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set oracle-price price)
    (var-set oracle-timestamp stacks-block-height)
    (ok true)
  )
)

(define-public (create-call-option (strike-price uint) (premium uint) (expiry-block uint))
  (let
    (
      (option-id (var-get option-nonce))
    )
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set options option-id
      {
        owner: tx-sender,
        option-type: "call",
        strike-price: strike-price,
        premium: premium,
        expiry-block: expiry-block,
        exercised: false,
        settled: false,
        payout: u0
      }
    )
    
    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (create-put-option (strike-price uint) (premium uint) (expiry-block uint))
  (let
    (
      (option-id (var-get option-nonce))
    )
    (asserts! (> strike-price u0) err-invalid-strike)
    (asserts! (> expiry-block stacks-block-height) err-invalid-expiry)
    (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-payment)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set options option-id
      {
        owner: tx-sender,
        option-type: "put",
        strike-price: strike-price,
        premium: premium,
        expiry-block: expiry-block,
        exercised: false,
        settled: false,
        payout: u0
      }
    )
    
    (var-set option-nonce (+ option-id u1))
    (ok option-id)
  )
)

(define-public (exercise-option (option-id uint))
  (let
    (
      (option-data (unwrap! (map-get? options option-id) err-not-found))
      (current-price (var-get oracle-price))
      (strike (get strike-price option-data))
      (option-type (get option-type option-data))
      (payout u0)
    )
    (asserts! (is-eq (get owner option-data) tx-sender) err-not-owner)
    (asserts! (>= stacks-block-height (get expiry-block option-data)) err-not-expired)
    (asserts! (not (get exercised option-data)) err-already-exercised)
    (asserts! (> current-price u0) err-oracle-not-set)
    
    (let
      (
        (calculated-payout
          (if (is-eq option-type "call")
            (if (> current-price strike)
              (- current-price strike)
              u0
            )
            (if (> strike current-price)
              (- strike current-price)
              u0
            )
          )
        )
      )
      
      (map-set options option-id
        (merge option-data {
          exercised: true,
          settled: true,
          payout: calculated-payout
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

(define-public (transfer-option (option-id uint) (recipient principal))
  (let
    (
      (option-data (unwrap! (map-get? options option-id) err-not-found))
    )
    (asserts! (is-eq (get owner option-data) tx-sender) err-not-owner)
    (asserts! (< stacks-block-height (get expiry-block option-data)) err-expired)
    (asserts! (not (get exercised option-data)) err-already-exercised)
    
    (map-set options option-id
      (merge option-data {owner: recipient})
    )
    
    (ok true)
  )
)