;; lending-pool.clar

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_PAUSED (err u104))

;; Data vars
(define-data-var min-collateral-ratio uint u150) ;; 150% collateralization ratio
(define-data-var interest-rate uint u5) ;; 5% annual interest rate
(define-data-var total-deposits uint u0)
(define-data-var total-borrows uint u0)
(define-data-var paused bool false)

;; Data maps
(define-map user-deposits { user: principal } { amount: uint, last-update: uint })
(define-map user-borrows { user: principal } { amount: uint, last-update: uint })

;; Events
(define-private (deposit-event (user principal) (amount uint))
  (print {event: "deposit", user: user, amount: amount}))

(define-private (withdraw-event (user principal) (amount uint))
  (print {event: "withdraw", user: user, amount: amount}))

(define-private (borrow-event (user principal) (amount uint))
  (print {event: "borrow", user: user, amount: amount}))

(define-private (repay-event (user principal) (amount uint))
  (print {event: "repay", user: user, amount: amount}))

;; Public functions
(define-public (deposit (amount uint))
  (let 
    (
      (sender tx-sender)
      (current-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: sender})))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    (map-set user-deposits 
      {user: sender} 
      {
        amount: (+ (get amount current-deposit) amount), 
        last-update: block-height
      }
    )
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (deposit-event sender amount)
    (ok amount)
  )
)

(define-public (withdraw (amount uint))
  (let
    (
      (sender tx-sender)
      (current-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: sender})))
      (current-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: sender})))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get amount current-deposit) amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (is-ok (check-collateral-ratio sender (- (get amount current-deposit) amount) (get amount current-borrow))) ERR_INSUFFICIENT_COLLATERAL)
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    (map-set user-deposits 
      {user: sender} 
      {
        amount: (- (get amount current-deposit) amount), 
        last-update: block-height
      }
    )
    (var-set total-deposits (- (var-get total-deposits) amount))
    (withdraw-event sender amount)
    (ok amount)
  )
)

(define-public (borrow (amount uint))
  (let
    (
      (sender tx-sender)
      (current-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: sender})))
      (current-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: sender})))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-ok (check-collateral-ratio sender (get amount current-deposit) (+ (get amount current-borrow) amount))) ERR_INSUFFICIENT_COLLATERAL)
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    (map-set user-borrows 
      {user: sender} 
      {
        amount: (+ (get amount current-borrow) amount), 
        last-update: block-height
      }
    )
    (var-set total-borrows (+ (var-get total-borrows) amount))
    (borrow-event sender amount)
    (ok amount)
  )
)

(define-public (repay (amount uint))
  (let
    (
      (sender tx-sender)
      (current-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: sender})))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get amount current-borrow) amount) ERR_INSUFFICIENT_BALANCE)
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    (map-set user-borrows 
      {user: sender} 
      {
        amount: (- (get amount current-borrow) amount), 
        last-update: block-height
      }
    )
    (var-set total-borrows (- (var-get total-borrows) amount))
    (repay-event sender amount)
    (ok amount)
  )
)

;; Read-only functions
(define-read-only (get-deposit (user principal))
  (ok (get amount (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: user})))))

(define-read-only (get-borrow (user principal))
  (ok (get amount (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: user})))))

(define-read-only (check-collateral-ratio (user principal) (collateral uint) (debt uint))
  (if (is-eq debt u0)
    (ok true)
    (if (>= (* collateral u100) (* debt (var-get min-collateral-ratio)))
      (ok true)
      (err ERR_INSUFFICIENT_COLLATERAL))))

(define-read-only (get-total-deposits)
  (ok (var-get total-deposits)))

(define-read-only (get-total-borrows)
  (ok (var-get total-borrows)))

;; Admin functions
(define-public (set-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the new ratio is between 100% and 500%
    (asserts! (and (>= new-ratio u100) (<= new-ratio u500)) (err u105))
    (var-set min-collateral-ratio new-ratio)
    (ok new-ratio)))

(define-public (set-interest-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the new rate is between 0% and 100%
    (asserts! (<= new-rate u100) (err u106))
    (var-set interest-rate new-rate)
    (ok new-rate)))

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set paused (not (var-get paused)))
    (ok (var-get paused))))

;; Private functions
(define-private (calculate-interest (principal uint) (blocks uint))
  (let ((interest-per-block (/ (var-get interest-rate) (* u365 u144))))
    (/ (* principal interest-per-block blocks) u10000)))

;; Contract initialization
(begin
  (try! (stx-transfer? u1000000000 CONTRACT_OWNER (as-contract tx-sender)))
  (ok true))