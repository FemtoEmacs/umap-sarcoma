% sarcoma-setup.pl -- Edinburgh-notation port of sarcoma-setup.x's ENV-VALUE
% and SUBSTEP facts (2026-09-14). Consulted by sarcoma-setup-edinburgh.lisp
% via consult("sarcoma-setup.pl"); see that file's header for what stays as
% Lisp (the shebang, the loads, *pipeline-root*, and the final run-pipeline
% call) and why, and sarcoma-setup.x's own header for why the pipeline is
% stated as data (SUBSTEP/5 facts) at all rather than a flat script.
%
% Every value here is identical to sarcoma-setup.x's -- this is a straight
% notation change, not a behavior change. Two translation notes:
%   * env-value(epochs, V) / env-value(rate, V) use `is' infix (V is Expr,
%     added to edinburgh-reader.lisp after this file was first written --
%     see NOTES.md's "is gains an infix spelling" section) with a
%     bare-paren Lisp escape on the right, (getenv-or "SAR_EPOCHS" "200")
%     -- the exact same escape hatch det-mode.pl's count-up/3 uses for
%     (+ N 1). GETENV-OR is already on the *LISP-EVAL-FUNCTIONS*
%     whitelist via pipeline.lisp's own (register-callable 'getenv-or),
%     loaded before this file is consulted -- nothing extra to register
%     here. `is' and `lisp-eval' are the same builtin under the hood
%     (BUILTIN-STEP evaluates the right side and unifies it with the
%     left, either spelling), and `is(V, Expr)' parses identically to
%     `V is Expr' -- this file just uses the more idiomatic ISO spelling
%     now that both exist.
%   * Each SUBSTEP's ArgList (a plain Lisp list in sarcoma-setup.x, e.g.
%     ("pilot-problem.sexp")) is an Edinburgh list, ["pilot-problem.sexp"],
%     read via READ-LIST-TAIL -- unrelated to the `is' point above, just
%     the ordinary Edinburgh list syntax for what was always ordinary
%     list data.

env-value(epochs, V) :- V is (getenv-or "SAR_EPOCHS" "200").
env-value(rate, V) :- V is (getenv-or "SAR_LR" "0.002d0").
env-value(result, "output/sarcoma-awrs-smc-result.sexp").
env-value(corpus, "smc-trainer/corpus/sarcoma-awrs-shards/manifest.sexp").
env-value(model, "smc-trainer/cl-sarcoma-awrs-model.sexp").
env-value(html, "output/cl-sarcoma-awrs-preferences.html").

substep(1, 1, "[1/5] Prepare evidence",
        "prepare-umap-data.lisp", ["pilot-problem.sexp"]).
substep(1, 2, "Build full evidence map",
        "build-umap.lisp", ["pilot-problem.sexp", "output/sarcoma-full.html"]).
substep(2, 1, "[2/5] AWRS-SMC search",
        "awrs-smc/search-umap.lisp", ["smc/pilot-search.sexp", Result]) :-
    env-value(result, Result).
substep(3, 1, "[3/5] Build corpus",
        "smc-trainer/build-sharded-corpus.lisp",
        [Result, "smc-trainer/corpus/sarcoma-awrs-shards/", "25"]) :-
    env-value(result, Result).
substep(3, 2, "Validate corpus",
        "smc-trainer/validate-corpus.lisp", [Corpus]) :-
    env-value(corpus, Corpus).
substep(4, 1, "[4/5] Train Transformer",
        "smc-trainer/train.lisp", [Corpus, Model, Epochs, Rate]) :-
    env-value(corpus, Corpus), env-value(model, Model),
    env-value(epochs, Epochs), env-value(rate, Rate).
substep(5, 1, "[5/5] Generate formatted HTML",
        "sarcoma-specific/build-preferences-page.lisp", [Corpus, Model, Html]) :-
    env-value(corpus, Corpus), env-value(model, Model), env-value(html, Html).
