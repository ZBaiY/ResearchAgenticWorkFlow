(* Wolfram backend job payload generator *)
spec = ImportString[Environment["COMPUTE_SPEC_JSON"], "RawJSON"];
params = Lookup[spec, "params", <||>];
a = N@Lookup[params, "a", 2.0];
b = N@Lookup[params, "b", 1.0];
xs = N /@ Lookup[params, "sample_points", {0, 1, 2, 3, 4}];
ys = (a # + b) & /@ xs;
meanY = If[Length[ys] > 0, Mean[ys], Missing["NotAvailable"]];

payload = <|
  "backend" -> "wolfram",
  "computation" -> "linear_model",
  "inputs" -> <|"x" -> xs|>,
  "params" -> <|"a" -> a, "b" -> b|>,
  "results" -> <|"y" -> ys, "mean_y" -> meanY|>,
  "sanity_checks" -> {
    <|"name" -> "result_vector_length_matches_input", "passed" -> (Length[xs] == Length[ys])|>,
    <|"name" -> "result_values_are_finite", "passed" -> AllTrue[ys, NumericQ]|>,
    <|"name" -> "mean_value_within_expected_range", "passed" -> If[Length[ys] > 0, meanY < 1000, False]|>
  }
|>;

out = Environment["COMPUTE_BACKEND_OUTPUT"];
If[StringLength[out] == 0, Print["COMPUTE_BACKEND_OUTPUT is required"]; Exit[2]];
Export[out, payload, "RawJSON"];
