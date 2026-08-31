(:schema :periodic-surrogate-v1
 :provenance
 (:source "Scherliess and Fejer (1999), Figure 6, Jicamarca equinox column"
  :doi "10.1029/1999JA900025"
  :interpretation "Approximate readings of solid model curves, not radar means"
  :digitizer "Codex genAI running fejer-ai; visual reading from 180 dpi rendering"
  :uncertainty-m-per-s 3
  :pre-spike-uncertainty-m-per-s 6
  :period-boundary-uncertainty-m-per-s 8
  :date "2026-08-26")
 :plot
 (:width 420 :height 245
  :plot-left 58 :plot-right 405 :plot-bottom 38 :plot-top 230
  :x-min 0 :x-max 24 :y-min -30 :y-max 55
  :x-ticks (0 4 8 12 16 20 24)
  :y-ticks (-20 0 20 40)
  :x-label "Local time (h)"
  :y-label "Vertical drift (m s$^{-1}$)"
  :sample-step 0.25)
 :series
 ((:id :solar-flux-80 :label "$S_a=80$"
   :anchors ((0 -18) (4 -10) (6 -3) (8 10) (10 22) (12 23)
             (14 16) (16 8) (18 6) (19 12) (20 -8) (22 -16))
   :checks ((2 -15) (7 3) (11 24) (15 12) (17 5) (21 -14) (23 -17)))
  (:id :solar-flux-140 :label "$S_a=140$"
   :anchors ((0 -22) (4 -17) (6 -9) (8 5) (10 17) (12 20)
             (14 14) (16 7) (18 9) (19 29) (20 -6) (22 -24))
   :checks ((2 -20) (7 -2) (11 20) (15 10) (17 7) (21 -21) (23 -24)))
  (:id :solar-flux-200 :label "$S_a=200$"
   :anchors ((0 -25) (4 -23) (6 -14) (8 3) (10 17) (12 21)
             (14 17) (16 11) (18 14) (19 48) (20 1) (22 -13))
   :checks ((2 -22) (7 -6) (11 21) (15 13) (17 10) (21 -11) (23 -11)))))
