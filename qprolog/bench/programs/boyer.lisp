;;;; boyer.lisp -- GENERATED from swi/boyer.pl by bench/pl2lispy.lisp; do not edit.

(<- (top) (wff ?wff) (rewrite ?wff ?newwff) (tautology ?newwff nil nil))
(<-
 (wff
  (implies (and (implies ?x ?y) (and (implies ?y ?z) (and (implies ?z ?u) (implies ?u ?w))))
   (implies ?x ?w)))
 (unify ?x (f (myplus (myplus a b) (myplus c zero))))
 (unify ?y (f (times (times a b) (myplus c d)))) (unify ?z (f (reverse (append (append a b) nil))))
 (unify ?u (equal (myplus a b) (boyer_difference x y)))
 (unify ?w (lessp (remainder a b) (boyer_member a (length b)))))
(<- (tautology ?wff) (rewrite ?wff ?newwff) (tautology ?newwff nil nil))
(<- (tautology ?wff ?tlist ?flist)
 (:or (truep ?wff ?tlist) -> true (falsep ?wff ?flist) -> fail
  (unify ?wff
   (if ?if
       ?then
       ?else))
  ->
  (:or (truep ?if ?tlist) -> (tautology ?then ?tlist ?flist) (falsep ?if ?flist) ->
   (tautology ?else ?tlist ?flist)
   (:and (tautology ?then (?if . ?tlist) ?flist) (tautology ?else ?tlist (?if . ?flist)))))
 !)
(<- (rewrite ?atom ?atom) (atomic ?atom) !)
(<- (rewrite ?old ?new) (functor ?old ?f ?n) (functor ?mid ?f ?n) (rewrite_args ?n ?old ?mid)
 (:or (:and (equal ?mid ?next) (rewrite ?next ?new)) (unify ?new ?mid)) !)
(<- (rewrite_args 0 _ _) !)
(<- (rewrite_args ?n ?old ?mid) (arg ?n ?old ?oldarg) (arg ?n ?mid ?midarg)
 (rewrite ?oldarg ?midarg) (is ?n1 (- ?n 1)) (rewrite_args ?n1 ?old ?mid))
(<- (truep t _) !)
(<- (truep ?wff ?tlist) (boyer_member ?wff ?tlist))
(<- (falsep f _) !)
(<- (falsep ?wff ?flist) (boyer_member ?wff ?flist))
(<- (boyer_member ?x (?x . _)) !)
(<- (boyer_member ?x (_ . ?t)) (boyer_member ?x ?t))
(<-
 (equal (and ?p ?q)
        (if ?p
            (if ?q
                t
                f)
            f)))
(<- (equal (append (append ?x ?y) ?z) (append ?x (append ?y ?z))))
(<-
 (equal (assignment ?x (append ?a ?b))
        (if (assignedp ?x ?a)
            (assignment ?x ?a)
            (assignment ?x ?b))))
(<- (equal (assume_false ?var ?alist) (cons (cons ?var f) ?alist)))
(<- (equal (assume_true ?var ?alist) (cons (cons ?var t) ?alist)))
(<- (equal (boolean ?x) (or (equal ?x t) (equal ?x f))))
(<-
 (equal (car (gopher ?x))
        (if (listp ?x)
            (car (flatten ?x))
            zero)))
(<- (equal (compile ?form) (reverse (codegen (optimize ?form) nil))))
(<- (equal (count_list ?z (sort_lp ?x ?y)) (myplus (count_list ?z ?x) (count_list ?z ?y))))
(<- (equal (countps_ ?l ?pred) (countps_loop ?l ?pred zero)))
(<- (equal (boyer_difference ?a ?b) ?c) (boyer_difference ?a ?b ?c))
(<- (equal (divides ?x ?y) (zerop (remainder ?y ?x))))
(<- (equal (dsort ?x) (sort2 ?x)))
(<- (equal (eqp ?x ?y) (equal (fix ?x) (fix ?y))))
(<- (equal (equal ?a ?b) ?c) (eq ?a ?b ?c))
(<-
 (equal (even1 ?x)
        (if (zerop ?x)
            t
            (odd (decr ?x)))))
(<- (equal (exec (append ?x ?y) ?pds ?envrn) (exec ?y (exec ?x ?pds ?envrn) ?envrn)))
(<- (equal (exp ?a ?b) ?c) (exp ?a ?b ?c))
(<- (equal (fact_ ?i) (fact_loop ?i 1)))
(<- (equal (falsify ?x) (falsify1 (normalize ?x) nil)))
(<-
 (equal (fix ?x)
        (if (numberp ?x)
            ?x
            zero)))
(<-
 (equal (flatten (cdr (gopher ?x)))
        (if (listp ?x)
            (cdr (flatten ?x))
            (cons zero nil))))
(<- (equal (gcd ?a ?b) ?c) (gcd ?a ?b ?c))
(<-
 (equal (get ?j (set ?i ?val ?mem))
        (if (eqp ?j ?i)
            ?val
            (get ?j ?mem))))
(<- (equal (greatereqp ?x ?y) (not (lessp ?x ?y))))
(<- (equal (greatereqpr ?x ?y) (not (lessp ?x ?y))))
(<- (equal (greaterp ?x ?y) (lessp ?y ?x)))
(<-
 (equal
  (if (if ?a
          ?b
          ?c)
      ?d
      ?e)
  (if ?a
      (if ?b
          ?d
          ?e)
      (if ?c
          ?d
          ?e))))
(<- (equal (iff ?x ?y) (and (implies ?x ?y) (implies ?y ?x))))
(<-
 (equal (implies ?p ?q)
        (if ?p
            (if ?q
                t
                f)
            t)))
(<-
 (equal (last (append ?a ?b))
        (if (listp ?b)
            (last ?b)
            (if (listp ?a)
                (cons (car (last ?a)))
                ?b))))
(<- (equal (length ?a) ?b) (mylength ?a ?b))
(<- (equal (lesseqp ?x ?y) (not (lessp ?y ?x))))
(<- (equal (lessp ?a ?b) ?c) (lessp ?a ?b ?c))
(<- (equal (listp (gopher ?x)) (listp ?x)))
(<- (equal (mc_flatten ?x ?y) (append (flatten ?x) ?y)))
(<- (equal (meaning ?a ?b) ?c) (meaning ?a ?b ?c))
(<- (equal (boyer_member ?a ?b) ?c) (myboyer_member ?a ?b ?c))
(<-
 (equal (not ?p)
        (if ?p
            f
            t)))
(<- (equal (my_nth ?a ?b) ?c) (my_nth ?a ?b ?c))
(<-
 (equal (numberp (greatest_factor ?x ?y))
        (not (and (or (zerop ?y) (equal ?y 1)) (not (numberp ?x))))))
(<-
 (equal (or ?p ?q)
        (if ?p
            t
            (if ?q
                t
                f)
            f)))
(<- (equal (myplus ?a ?b) ?c) (myplus ?a ?b ?c))
(<- (equal (power_eval ?a ?b) ?c) (power_eval ?a ?b ?c))
(<-
 (equal (prime ?x) (and (not (zerop ?x)) (and (not (equal ?x (add1 zero))) (prime1 ?x (decr ?x))))))
(<- (equal (prime_list (append ?x ?y)) (and (prime_list ?x) (prime_list ?y))))
(<- (equal (quotient ?a ?b) ?c) (quotient ?a ?b ?c))
(<- (equal (remainder ?a ?b) ?c) (remainder ?a ?b ?c))
(<- (equal (reverse_ ?x) (reverse_loop ?x nil)))
(<- (equal (reverse (append ?a ?b)) (append (reverse ?b) (reverse ?a))))
(<- (equal (reverse_loop ?a ?b) ?c) (reverse_loop ?a ?b ?c))
(<- (equal (samefringe ?x ?y) (equal (flatten ?x) (flatten ?y))))
(<- (equal (sigma zero ?i) (quotient (times ?i (add1 ?i)) 2)))
(<- (equal (sort2 (delete ?x ?l)) (delete ?x (sort2 ?l))))
(<- (equal (tautology_checker ?x) (tautologyp (normalize ?x) nil)))
(<- (equal (times ?a ?b) ?c) (times ?a ?b ?c))
(<- (equal (times_list (append ?x ?y)) (times (times_list ?x) (times_list ?y))))
(<- (equal (value (normalize ?x) ?a) (value ?x ?a)))
(<- (equal (zerop ?x) (or (equal ?x zero) (not (numberp ?x)))))
(<- (boyer_difference ?x ?x zero) !)
(<- (boyer_difference (myplus ?x ?y) ?x (fix ?y)) !)
(<- (boyer_difference (myplus ?y ?x) ?x (fix ?y)) !)
(<- (boyer_difference (myplus ?x ?y) (myplus ?x ?z) (boyer_difference ?y ?z)) !)
(<- (boyer_difference (myplus ?b (myplus ?a ?c)) ?a (myplus ?b ?c)) !)
(<- (boyer_difference (add1 (myplus ?y ?z)) ?z (add1 ?y)) !)
(<- (boyer_difference (add1 (add1 ?x)) 2 (fix ?x)))
(<- (eq (myplus ?a ?b) zero (and (zerop ?a) (zerop ?b))) !)
(<- (eq (myplus ?a ?b) (myplus ?a ?c) (equal (fix ?b) (fix ?c))) !)
(<- (eq zero (boyer_difference ?x ?y) (not (lessp ?y ?x))) !)
(<- (eq ?x (boyer_difference ?x ?y) (and (numberp ?x) (and (or (equal ?x zero) (zerop ?y))))) !)
(<- (eq (times ?x ?y) zero (or (zerop ?x) (zerop ?y))) !)
(<- (eq (append ?a ?b) (append ?a ?c) (equal ?b ?c)) !)
(<- (eq (flatten ?x) (cons ?y nil) (and (nlistp ?x) (equal ?x ?y))) !)
(<- (eq (greatest_factor ?x ?y) zero (and (or (zerop ?y) (equal ?y 1)) (equal ?x zero))) !)
(<- (eq (greatest_factor ?x _) 1 (equal ?x 1)) !)
(<- (eq ?z (times ?w ?z) (and (numberp ?z) (or (equal ?z zero) (equal ?w 1)))) !)
(<- (eq ?x (times ?x ?y) (or (equal ?x zero) (and (numberp ?x) (equal ?y 1)))) !)
(<-
 (eq (times ?a ?b) 1
     (and (not (equal ?a zero))
          (and (not (equal ?b zero))
               (and (numberp ?a)
                    (and (numberp ?b) (and (equal (decr ?a) zero) (equal (decr ?b) zero)))))))
 !)
(<-
 (eq (boyer_difference ?x ?y) (boyer_difference ?z ?y)
     (if (lessp ?x ?y)
         (not (lessp ?y ?z))
         (if (lessp ?z ?y)
             (not (lessp ?y ?x))
             (equal (fix ?x) (fix ?z)))))
 !)
(<-
 (eq (lessp ?x ?y) ?z
     (if (lessp ?x ?y)
         (equal t ?z)
         (equal f ?z))))
(<- (exp ?i (myplus ?j ?k) (times (exp ?i ?j) (exp ?i ?k))) !)
(<- (exp ?i (times ?j ?k) (exp (exp ?i ?j) ?k)))
(<- (gcd ?x ?y (gcd ?y ?x)) !)
(<- (gcd (times ?x ?z) (times ?y ?z) (times ?z (gcd ?x ?y))))
(<- (mylength (reverse ?x) (length ?x)))
(<- (mylength (cons _ (cons _ (cons _ (cons _ (cons _ (cons _ ?x7)))))) (myplus 6 (length ?x7))))
(<- (lessp (remainder _ ?y) ?y (not (zerop ?y))) !)
(<- (lessp (quotient ?i ?j) ?i (and (not (zerop ?i)) (or (zerop ?j) (not (equal ?j 1))))) !)
(<- (lessp (remainder ?x ?y) ?x (and (not (zerop ?y)) (and (not (zerop ?x)) (not (lessp ?x ?y)))))
 !)
(<- (lessp (myplus ?x ?y) (myplus ?x ?z) (lessp ?y ?z)) !)
(<- (lessp (times ?x ?z) (times ?y ?z) (and (not (zerop ?z)) (lessp ?x ?y))) !)
(<- (lessp ?y (myplus ?x ?y) (not (zerop ?x))) !)
(<- (lessp (length (delete ?x ?l)) (length ?l) (boyer_member ?x ?l)))
(<-
 (meaning (plus_tree (append ?x ?y)) ?a
  (myplus (meaning (plus_tree ?x) ?a) (meaning (plus_tree ?y) ?a)))
 !)
(<- (meaning (plus_tree (plus_fringe ?x)) ?a (fix (meaning ?x ?a))) !)
(<-
 (meaning (plus_tree (delete ?x ?y)) ?a
  (if (boyer_member ?x ?y)
      (boyer_difference (meaning (plus_tree ?y) ?a) (meaning ?x ?a))
      (meaning (plus_tree ?y) ?a))))
(<- (myboyer_member ?x (append ?a ?b) (or (boyer_member ?x ?a) (boyer_member ?x ?b))) !)
(<- (myboyer_member ?x (reverse ?y) (boyer_member ?x ?y)) !)
(<- (myboyer_member ?a (intersect ?b ?c) (and (boyer_member ?a ?b) (boyer_member ?a ?c))))
(<- (my_nth zero _ zero))
(<-
 (my_nth nil ?i
  (if (zerop ?i)
      nil
      zero)))
(<-
 (my_nth (append ?a ?b) ?i (append (my_nth ?a ?i) (my_nth ?b (boyer_difference ?i (length ?a))))))
(<- (myplus (myplus ?x ?y) ?z (myplus ?x (myplus ?y ?z))) !)
(<- (myplus (remainder ?x ?y) (times ?y (quotient ?x ?y)) (fix ?x)) !)
(<-
 (myplus ?x (add1 ?y)
  (if (numberp ?y)
      (add1 (myplus ?x ?y))
      (add1 ?x))))
(<- (power_eval (big_plus1 ?l ?i ?base) ?base (myplus (power_eval ?l ?base) ?i)) !)
(<- (power_eval (power_rep ?i ?base) ?base (fix ?i)) !)
(<-
 (power_eval (big_plus ?x ?y ?i ?base) ?base
  (myplus ?i (myplus (power_eval ?x ?base) (power_eval ?y ?base))))
 !)
(<-
 (power_eval (big_plus (power_rep ?i ?base) (power_rep ?j ?base) zero ?base) ?base (myplus ?i ?j)))
(<- (quotient (myplus ?x (myplus ?x ?y)) 2 (myplus ?x (quotient ?y 2))))
(<-
 (quotient (times ?y ?x) ?y
  (if (zerop ?y)
      zero
      (fix ?x))))
(<- (remainder _ 1 zero) !)
(<- (remainder ?x ?x zero) !)
(<- (remainder (times _ ?z) ?z zero) !)
(<- (remainder (times ?y _) ?y zero))
(<- (reverse_loop ?x ?y (append (reverse ?x) ?y)) !)
(<- (reverse_loop ?x nil (reverse ?x)))
(<- (times ?x (myplus ?y ?z) (myplus (times ?x ?y) (times ?x ?z))) !)
(<- (times (times ?x ?y) ?z (times ?x (times ?y ?z))) !)
(<- (times ?x (boyer_difference ?c ?w) (boyer_difference (times ?c ?x) (times ?w ?x))) !)
(<-
 (times ?x (add1 ?y)
  (if (numberp ?y)
      (myplus ?x (times ?x ?y))
      (fix ?x))))
