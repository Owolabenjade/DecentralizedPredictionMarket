;; Constants and Data Structures

(define-constant owner 'SP2C2YZW6J8CJJ0YCNMPFE5Q2J3MSP4B2JWX28ZYQ')
(define-constant closed-status "closed")

(define-map events
  { event-id: uint }
  {
    description: (string-ascii 100),
    options: (list 10 (string-ascii 20)),
    status: (string-ascii 10),
    outcome: (optional (string-ascii 20))
  })

(define-map bets
  { event-id: uint, user: principal }
  {
    option: (string-ascii 20),
    amount: uint
  })

(define-data-var non-reentrant bool false)

;; Event Management Functions

(define-public (create-event (event-id uint) (description (string-ascii 100)) (options (list 10 (string-ascii 20))))
  (begin
    ;; Prevent reentrant calls
    (asserts! (is-eq (var-get non-reentrant) false) (err u"Reentrant call detected"))
    (var-set non-reentrant true)

    ;; Insert the new event
    (map-insert events
      { event-id: event-id }
      {
        description: description,
        options: options,
        status: "open",
        outcome: none
      })

    ;; Reset the non-reentrant flag
    (var-set non-reentrant false)
    (ok event-id)
  )
)

(define-public (place-bet (event-id uint) (option (string-ascii 20)) (amount uint))
  (begin
    ;; Prevent reentrant calls
    (asserts! (is-eq (var-get non-reentrant) false) (err u"Reentrant call detected"))
    (var-set non-reentrant true)

    ;; Ensure the event is open and the option is valid
    (match (map-get? events { event-id: event-id })
      some-event
      (if (is-eq (get status some-event) "open")
        (begin
          ;; Insert the bet
          (map-insert bets
            { event-id: event-id, user: tx-sender }
            {
              option: option,
              amount: amount
            })
          ;; Reset the non-reentrant flag
          (var-set non-reentrant false)
          (ok amount)
        )
        (begin
          ;; Reset the non-reentrant flag
          (var-set non-reentrant false)
          (err u"Event is closed")
        )
      )
      (begin
        ;; Reset the non-reentrant flag
        (var-set non-reentrant false)
        (err u"Event not found")
      )
    )
  )
)

;; Access Control for closing events

(define-public (close-event (event-id uint) (outcome (string-ascii 20)))
  (begin
    ;; Ensure only the contract owner can close events
    (asserts! (is-eq tx-sender owner) (err u"Only the contract owner can close events"))

    ;; Close the event and set the outcome
    (match (map-get? events { event-id: event-id })
      some-event
      (if (is-eq (get status some-event) "open")
        (begin
          ;; Update the event status to closed and set the outcome
          (map-set events { event-id: event-id }
            {
              description: (get description some-event),
              options: (get options some-event),
              status: closed-status,
              outcome: (some outcome)
            })
          (ok outcome)
        )
        (err u"Event is already closed")
      )
      (err u"Event not found")
    )
  )
)

;; Bet Settlement and Payouts (with optimizations)

(define-public (settle-bets (event-id uint))
  (begin
    ;; Ensure only the contract owner can settle bets
    (asserts! (is-eq tx-sender owner) (err u"Only the contract owner can settle bets"))
    ;; Prevent reentrant calls
    (asserts! (is-eq (var-get non-reentrant) false) (err u"Reentrant call detected"))
    (var-set non-reentrant true)

    ;; Settle the bets and distribute payouts
    (let
      (
        ;; Get the event data
        (maybe-event (map-get? events { event-id: event-id }))
      )
      (match maybe-event
        some-event
        (if (is-eq (get status some-event) closed-status)
          (let
            (
              ;; Get the outcome of the event
              (event-outcome (get outcome some-event))
              ;; Calculate the total amount bet on the event
              (total-bets (fold (lambda (bet accum)
                                  (+ accum (get amount (snd bet))))
                                u0
                                (map-filter (lambda (bet)
                                              (is-eq (get event-id (fst bet)) event-id))
                                            bets)))
              ;; Calculate the total amount bet on the winning option
              (winning-bets (fold (lambda (bet accum)
                                    (if (is-eq (get option (snd bet)) event-outcome)
                                        (+ accum (get amount (snd bet)))
                                        accum))
                                  u0
                                  (map-filter (lambda (bet)
                                                (is-eq (get event-id (fst bet)) event-id))
                                              bets)))
            )

            ;; Distribute payouts to winners
            (map-map (lambda (bet)
                       (let
                         (
                           (bet-details (snd bet))
                           (bet-user (get user (fst bet)))
                         )
                         (if (is-eq (get option bet-details) event-outcome)
                             (let
                               (
                                 ;; Calculate the payout
                                 (payout (* (get amount bet-details) (/ total-bets winning-bets)))
                               )
                               ;; Transfer the payout to the user
                               (as-contract (stx-transfer? payout tx-sender bet-user))
                             )
                             (ok u0)
                         )
                       ))
                     bets)

            ;; Reset the non-reentrant flag
            (var-set non-reentrant false)
            (ok (get outcome some-event))
          )
          (begin
            ;; Reset the non-reentrant flag
            (var-set non-reentrant false)
            (err u"Event is not closed or outcome not set")
          )
        )
        (begin
          ;; Reset the non-reentrant flag
          (var-set non-reentrant false)
          (err u"Event not found")
        )
      )
    )
  )
)
