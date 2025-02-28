;; lending-pool.clar

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_PAUSED (err u104))
(define-constant ERR_INVALID_RATIO (err u105))
(define-constant ERR_INVALID_RATE (err u106))
(define-constant ERR_LIQUIDATION_FAILED (err u107))

;; Data vars
(define-data-var min-collateral-ratio uint u150) ;; 150% collateralization ratio
(define-data-var liquidation-threshold uint u120) ;; 120% liquidation threshold
(define-data-var interest-rate uint u5) ;; 5% annual interest rate
(define-data-var total-deposits uint u0)
(define-data-var total-borrows uint u0)
(define-data-var paused bool false)
(define-data-var liquidation-fee uint u5) ;; 5% liquidation fee

;; Data maps
(define-map user-deposits { user: principal } { amount: uint, last-update: uint })
(define-map user-borrows { user: principal } { amount: uint, last-update: uint })
(define-map whitelisted-liquidators { user: principal } { active: bool })

;; Events
(define-private (deposit-event (user principal) (amount uint))
  (print {event: "deposit", user: user, amount: amount}))

(define-private (withdraw-event (user principal) (amount uint))
  (print {event: "withdraw", user: user, amount: amount}))

(define-private (borrow-event (user principal) (amount uint))
  (print {event: "borrow", user: user, amount: amount}))

(define-private (repay-event (user principal) (amount uint))
  (print {event: "repay", user: user, amount: amount}))

(define-private (liquidation-event (liquidator principal) (borrower principal) (amount uint) (fee uint))
  (print {event: "liquidation", liquidator: liquidator, borrower: borrower, amount: amount, fee: fee}))

(define-private (interest-accrued-event (user principal) (amount uint))
  (print {event: "interest-accrued", user: user, amount: amount}))

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
        last-update: stacks-block-height
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
        last-update: stacks-block-height
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
        last-update: stacks-block-height
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
        last-update: stacks-block-height
      }
    )
    (var-set total-borrows (- (var-get total-borrows) amount))
    (repay-event sender amount)
    (ok amount)
  )
)

;; NEW FUNCTION #1: Liquidate underwater positions
(define-public (liquidate (borrower principal) (amount uint))
  (let
    (
      (liquidator tx-sender)
      (borrower-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: borrower})))
      (borrower-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: borrower})))
      (liquidator-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: liquidator})))
      (collateral-ratio (unwrap-panic (calculate-collateral-ratio (get amount borrower-deposit) (get amount borrower-borrow))))
      (liquidation-fee-amount (/ (* amount (var-get liquidation-fee)) u100))
      (collateral-to-seize (+ amount liquidation-fee-amount))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= collateral-ratio (var-get liquidation-threshold)) ERR_LIQUIDATION_FAILED)
    (asserts! (>= (get amount borrower-borrow) amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (>= (get amount borrower-deposit) collateral-to-seize) ERR_INSUFFICIENT_COLLATERAL)
    
    ;; Transfer STX from liquidator to contract to repay borrower's debt
    (try! (stx-transfer? amount liquidator (as-contract tx-sender)))
    
    ;; Update borrower's borrow balance
    (map-set user-borrows 
      {user: borrower} 
      {
        amount: (- (get amount borrower-borrow) amount), 
        last-update: stacks-block-height
      }
    )
    
    ;; Update borrower's deposit balance (reduce by collateral seized)
    (map-set user-deposits 
      {user: borrower} 
      {
        amount: (- (get amount borrower-deposit) collateral-to-seize), 
        last-update: stacks-block-height
      }
    )
    
    ;; Update liquidator's deposit balance (increase by collateral seized)
    (map-set user-deposits 
      {user: liquidator} 
      {
        amount: (+ (get amount liquidator-deposit) collateral-to-seize), 
        last-update: stacks-block-height
      }
    )
    
    ;; Update total borrows
    (var-set total-borrows (- (var-get total-borrows) amount))
    
    ;; Emit liquidation event
    (liquidation-event liquidator borrower amount liquidation-fee-amount)
    (ok collateral-to-seize)
  )
)

;; NEW FUNCTION #2: Accrue interest for a user
(define-public (accrue-interest (user principal))
  (let
    (
      (current-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: user})))
      (blocks-elapsed (- stacks-block-height (get last-update current-borrow)))
      (interest-amount (calculate-interest (get amount current-borrow) blocks-elapsed))
      (new-borrow-amount (+ (get amount current-borrow) interest-amount))
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> (get amount current-borrow) u0) ERR_INVALID_AMOUNT)
    
    ;; Update user's borrow balance with accrued interest
    (map-set user-borrows 
      {user: user} 
      {
        amount: new-borrow-amount, 
        last-update: stacks-block-height
      }
    )
    
    ;; Update total borrows
    (var-set total-borrows (+ (var-get total-borrows) interest-amount))
    
    ;; Emit interest accrued event
    (interest-accrued-event user interest-amount)
    (ok interest-amount)
  )
)

;; NEW FUNCTION #3: Flash loan functionality
(define-public (flash-loan (amount uint) (recipient principal) (memo (optional (buff 34))))
  (let
    (
      (sender tx-sender)
      (fee (/ (* amount u1) u1000)) ;; 0.1% fee
    )
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get total-deposits)) ERR_INSUFFICIENT_BALANCE)
    
    ;; Transfer STX to recipient
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    
    ;; Check that loan + fee is repaid in same transaction
    (try! (stx-transfer? (+ amount fee) recipient (as-contract tx-sender)))
    
    ;; Add fee to total deposits
    (var-set total-deposits (+ (var-get total-deposits) fee))
    
    ;; Emit event (could create a specific event for flash loans)
    (print {event: "flash-loan", recipient: recipient, amount: amount, fee: fee})
    (ok fee)
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

(define-read-only (calculate-collateral-ratio (collateral uint) (debt uint))
  (if (is-eq debt u0)
    (ok u0)
    (ok (/ (* collateral u100) debt))))

(define-read-only (get-total-deposits)
  (ok (var-get total-deposits)))

(define-read-only (get-total-borrows)
  (ok (var-get total-borrows)))

(define-read-only (is-underwater (user principal))
  (let
    (
      (current-deposit (default-to {amount: u0, last-update: u0} (map-get? user-deposits {user: user})))
      (current-borrow (default-to {amount: u0, last-update: u0} (map-get? user-borrows {user: user})))
      (collateral (get amount current-deposit))
      (debt (get amount current-borrow))
    )
    (if (is-eq debt u0)
      (ok false)
      (ok (< (* collateral u100) (* debt (var-get liquidation-threshold)))))))

;; Admin functions
(define-public (set-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the new ratio is between 100% and 500%
    (asserts! (and (>= new-ratio u100) (<= new-ratio u500)) ERR_INVALID_RATIO)
    (var-set min-collateral-ratio new-ratio)
    (ok new-ratio)))

(define-public (set-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the threshold is less than min-collateral-ratio but above 100%
    (asserts! (and (>= new-threshold u100) (< new-threshold (var-get min-collateral-ratio))) ERR_INVALID_RATIO)
    (var-set liquidation-threshold new-threshold)
    (ok new-threshold)))

(define-public (set-interest-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the new rate is between 0% and 100%
    (asserts! (<= new-rate u100) ERR_INVALID_RATE)
    (var-set interest-rate new-rate)
    (ok new-rate)))

(define-public (set-liquidation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Ensure the new fee is between 0% and 20%
    (asserts! (<= new-fee u20) ERR_INVALID_RATE)
    (var-set liquidation-fee new-fee)
    (ok new-fee)))

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