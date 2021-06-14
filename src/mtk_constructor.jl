# Helpers
function default_model_cache_location()
    return joinpath(pkgdir(DifferentiableStateSpaceModels), ".function_cache")
end

function generate_first_order_model(H; ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, y, x, p_f,
                                    functions_type, skipzeros, simplify, parallel, verbose)

    is_sparse = (typeof(functions_type) <: SparseFunctions)
    y_vars = connect_markov_variables(y)
    x_vars = connect_markov_variables(x)
    n_y = length(y_vars)
    n_x = length(x_vars)
    n = n_y + n_x
    n_p = isnothing(p) ? 0 : length(p)
    n_ϵ = size(η, 2)
    n_z = (Q == I) ? n : size(Q, 1)

    # Extract triplets from  y_vars, x_vars for connected variable names
    y = [v[1] for v in y_vars]
    x = [v[1] for v in x_vars]
    y_p = [v[2] for v in y_vars]
    x_p = [v[2] for v in x_vars]
    y_ss = [v[3] for v in y_vars]
    x_ss = [v[3] for v in x_vars]
    y_p_substitutions = [y_p[i] => y[i] for i in eachindex(y)]
    x_p_substitutions = [x_p[i] => x[i] for i in eachindex(x)]
    y_ss_substitutions = [y_ss[i] => y[i] for i in eachindex(y)]
    x_ss_substitutions = [x_ss[i] => x[i] for i in eachindex(x)]
    all_substitutions = vcat(y_p_substitutions, x_p_substitutions, y_ss_substitutions,
                             x_ss_substitutions)

    # ensure no reuse of variable
    allunique([p; p_f; y; x; y_p; x_p; y_ss; x_ss]) ||
        throw(ArgumentError("Overlapping variables or parameters"))

    # sort variables in equation assignment form.
    ȳ_iv = sort_by_variables(ȳ_iv, y_ss)
    x̄_iv = sort_by_variables(x̄_iv, x_ss)
    ȳ = sort_by_variables(ȳ, y_ss)
    x̄ = sort_by_variables(x̄, x_ss)

    # steady state requiers differentiation after substitution, and wrt [y; x]
    H̄ = deepcopy(H)
    H̄_sub = substitute_and_simplify(H̄, all_substitutions; simplify)

    # Derivatives utilities return nothing if either argument nothing
    H_yp = recursive_differentiate(H, y_p, is_sparse)
    H_y = recursive_differentiate(H, y, is_sparse)
    H_xp = recursive_differentiate(H, x_p, is_sparse)
    H_x = recursive_differentiate(H, x, is_sparse)
    H_p = recursive_differentiate(H, p, is_sparse)
    Γ_p = recursive_differentiate(Γ, p, false)  # solution object required dense
    Ω_p = recursive_differentiate(Ω, p, false)
    ȳ_p = recursive_differentiate(ȳ, p, false)
    x̄_p = recursive_differentiate(x̄, p, false)
    H̄_w = recursive_differentiate(H̄_sub, [y; x], false) # differentiate post-substitution wrt w = [y;x], force a dense one
    H_yp_p = recursive_differentiate(H_yp, p, is_sparse)
    H_xp_p = recursive_differentiate(H_xp, p, is_sparse)
    H_y_p = recursive_differentiate(H_y, p, is_sparse)
    H_x_p = recursive_differentiate(H_x, p, is_sparse)
    Ψ = (n_p == 0) ? nothing : stack_hessians(H, [y_p; y; x_p; x], is_sparse)

    # apply substitutions and simplify if required.
    H_yp_sub = substitute_and_simplify(H_yp, all_substitutions; simplify)
    H_xp_sub = substitute_and_simplify(H_xp, all_substitutions; simplify)
    H_x_sub = substitute_and_simplify(H_x, all_substitutions; simplify)
    H_y_sub = substitute_and_simplify(H_y, all_substitutions; simplify)
    H_p_sub = substitute_and_simplify(H_p, all_substitutions; simplify)
    H_yp_p_sub = substitute_and_simplify(H_yp_p, all_substitutions; simplify)
    H_y_p_sub = substitute_and_simplify(H_y_p, all_substitutions; simplify)
    H_xp_p_sub = substitute_and_simplify(H_xp_p, all_substitutions; simplify)
    H_x_p_sub = substitute_and_simplify(H_x_p, all_substitutions; simplify)
    Ψ_sub = substitute_and_simplify(Ψ, all_substitutions; simplify)
    ȳ_p_sub = substitute_and_simplify(ȳ_p, []; simplify)
    x̄_p_sub = substitute_and_simplify(x̄_p, []; simplify)

    # Sparse allocations if needbe
    # Comprehensions can't be used with GeneralizedGenerated, so using "map"
    if is_sparse
        allocate_solver_cache_expr = :(m -> FirstOrderSolverCache(; p_hash = zero(UInt64),
                                                                  p_f_hash = zero(UInt64),
                                                                  p_ss_hash = zero(UInt64),
                                                                  p_f_ss_hash = zero(UInt64),
                                                                  p_perturbation_hash = zero(UInt64),
                                                                  p_f_perturbation_hash = zero(UInt64),
                                                                  H = zeros(m.n),
                                                                  H_yp = $(generate_undef_constructor(H_yp_sub)),
                                                                  H_y = $(generate_undef_constructor(H_y_sub)),
                                                                  H_xp = $(generate_undef_constructor(H_xp_sub)),
                                                                  H_x = $(generate_undef_constructor(H_x_sub)),
                                                                  H_yp_p = $(generate_undef_constructor(H_yp_p_sub)),
                                                                  H_y_p = $(generate_undef_constructor(H_y_p_sub)),
                                                                  H_xp_p = $(generate_undef_constructor(H_xp_p_sub)),
                                                                  H_x_p = $(generate_undef_constructor(H_x_p_sub)),
                                                                  H_p = $(generate_undef_constructor(H_p_sub)),
                                                                  Γ = zeros(m.n_ϵ, m.n_ϵ),
                                                                  B = zeros(m.n_x, m.n_ϵ),
                                                                  Ω = isnothing(m.Ω!) ?
                                                                      nothing :
                                                                      zeros(m.n_z),
                                                                  Ψ = $(generate_undef_constructor(Ψ_sub)),
                                                                  Γ_p = map(_ -> zeros(m.n_ϵ,
                                                                                       m.n_ϵ),
                                                                            1:(m.n_p)),
                                                                  B_p = map(_ -> zeros(m.n_x,
                                                                                       m.n_ϵ),
                                                                            1:(m.n_p)),
                                                                  Ω_p = isnothing(m.Ω_p!) ?
                                                                        nothing :
                                                                        zeros(m.n_z, m.n_p),
                                                                  x = zeros(m.n_x),
                                                                  y = zeros(m.n_y),
                                                                  y_p = zeros(m.n_y, m.n_p),
                                                                  x_p = zeros(m.n_x, m.n_p),
                                                                  g_x = zeros(m.n_y, m.n_x),
                                                                  h_x = zeros(m.n_x, m.n_x),
                                                                  g_x_p = map(_ -> zeros(m.n_y,
                                                                                         m.n_x),
                                                                              1:(m.n_p)),
                                                                  h_x_p = map(_ -> zeros(m.n_y,
                                                                                         m.n_x),
                                                                              1:(m.n_p)),
                                                                  Σ = Symmetric(zeros(m.n_ϵ,
                                                                                      m.n_ϵ)),
                                                                  Σ_p = map(_ -> Symmetric(zeros(m.n_ϵ,
                                                                                                 m.n_ϵ)),
                                                                            1:(m.n_p)), m.Q,
                                                                  m.η,
                                                                  A_1_p = map(_ -> zeros(m.n_x,
                                                                                    m.n_x),
                                                                                1:(m.n_p)),
                                                                  C_1 = zeros(m.n_z,
                                                                                m.n_x),
                                                                  C_1_p = map(_ -> zeros(m.n_z,
                                                                                           m.n_x),
                                                                                1:(m.n_p)),
                                                                                V = cholesky(Array(I(m.n_x))),
                                                                                V_p = map(_ -> zeros(m.n_x, m.n_x),
                                                                                          1:(m.n_p))))
    else #No GPU or tensor versions implemented yet
        allocate_solver_cache_expr = :(m -> FirstOrderSolverCache(m))
    end
    # Generate all functions
    Γ_expr = build_dssm_function(Γ, p, p_f; parallel, skipzeros)
    Γ_p_expr = build_dssm_function(Γ_p, p, p_f; parallel, skipzeros)
    Ω_expr = build_dssm_function(Ω, p, p_f; parallel, skipzeros)
    Ω_p_expr = build_dssm_function(Ω_p, p, p_f; parallel, skipzeros)
    H_expr = build_dssm_function(H, y_p, y, y_ss, x_p, x, x_ss, p, p_f; parallel, skipzeros)
    H_yp_expr = build_dssm_function(H_yp_sub, y, x, p, p_f; parallel, skipzeros)
    H_y_expr = build_dssm_function(H_y_sub, y, x, p, p_f; parallel, skipzeros)
    H_xp_expr = build_dssm_function(H_xp_sub, y, x, p, p_f; parallel, skipzeros)
    H_x_expr = build_dssm_function(H_x_sub, y, x, p, p_f; parallel, skipzeros)
    H_yp_p_expr = build_dssm_function(H_yp_p_sub, y, x, p, p_f; parallel, skipzeros)
    H_y_p_expr = build_dssm_function(H_y_p_sub, y, x, p, p_f; parallel, skipzeros)
    H_xp_p_expr = build_dssm_function(H_xp_p_sub, y, x, p, p_f; parallel, skipzeros)
    H_x_p_expr = build_dssm_function(H_x_p_sub, y, x, p, p_f; parallel, skipzeros)
    H_p_expr = build_dssm_function(H_p_sub, y, x, p, p_f; parallel, skipzeros)
    Ψ_expr = build_dssm_function(Ψ_sub, y, x, p, p_f; parallel, skipzeros)
    H̄_expr = build_dssm_function(H̄_sub, [y; x], p, p_f; parallel, skipzeros)
    H̄_w_expr = build_dssm_function(H̄_w, [y; x], p, p_f; parallel, skipzeros)
    ȳ_iv_expr = build_dssm_function(ȳ_iv, p, p_f; parallel, skipzeros)
    x̄_iv_expr = build_dssm_function(x̄_iv, p, p_f; parallel, skipzeros)
    ȳ_expr = build_dssm_function(ȳ, p, p_f; parallel, skipzeros)
    x̄_expr = build_dssm_function(x̄, p, p_f; parallel, skipzeros)
    ȳ_p_expr = build_dssm_function(ȳ_p_sub, p, p_f; parallel, skipzeros)
    x̄_p_expr = build_dssm_function(x̄_p_sub, p, p_f; parallel, skipzeros)

    verbose && printstyled("Done Building Model\n", color = :cyan)
    # if the module was included, gets the module name, otherwise returns nothing
    return (; n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr,
            H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr,
            H_x_p_expr, H_p_expr, Ψ_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr,
            ȳ_expr, x̄_expr, ȳ_p_expr, x̄_p_expr, functions_type,
            allocate_solver_cache_expr)
end

function FirstOrderPerturbationModel(H; ȳ = nothing, x̄ = nothing,
                                                ȳ_iv = nothing, x̄_iv = nothing, Γ,
                                                Ω = nothing, η, Q = I, p = nothing, y, x,
                                                p_f = nothing,
                                                functions_type = DenseFunctions(),
                                                select_p_ss_hash = I,
                                                select_p_f_ss_hash = I,
                                                select_p_perturbation_hash = I,
                                                select_p_f_perturbation_hash = I,
                                                simplify = true, skipzeros = true,
                                                parallel = ModelingToolkit.SerialForm(),
                                                verbose = false)
    mod = generate_first_order_model(H; y, x, ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, p_f,
                                     functions_type, simplify, skipzeros, parallel, verbose)
    @unpack n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr, H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr, H_x_p_expr, H_p_expr, Ψ_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr, ȳ_expr, x̄_expr, ȳ_p_expr, x̄_p_expr, functions_type, allocate_solver_cache_expr = mod
    Γ! = mk_gg_function(Γ_expr)
    Γ_p! = mk_gg_function(Γ_p_expr)
    Ω! = mk_gg_function(Ω_expr)
    Ω_p! = mk_gg_function(Ω_p_expr)
    H! = mk_gg_function(H_expr)
    H_yp! = mk_gg_function(H_yp_expr)
    H_y! = mk_gg_function(H_y_expr)
    H_xp! = mk_gg_function(H_xp_expr)
    H_x! = mk_gg_function(H_x_expr)
    H_yp_p! = mk_gg_function(H_yp_p_expr)
    H_y_p! = mk_gg_function(H_y_p_expr)
    H_xp_p! = mk_gg_function(H_xp_p_expr)
    H_x_p! = mk_gg_function(H_x_p_expr)
    H_p! = mk_gg_function(H_p_expr)
    Ψ! = mk_gg_function(Ψ_expr)
    H̄! = mk_gg_function(H̄_expr)
    H̄_w! = mk_gg_function(H̄_w_expr)
    ȳ_iv! = mk_gg_function(ȳ_iv_expr)
    x̄_iv! = mk_gg_function(x̄_iv_expr)
    ȳ! = mk_gg_function(ȳ_expr)
    x̄! = mk_gg_function(x̄_expr)
    ȳ_p! = mk_gg_function(ȳ_p_expr)
    x̄_p! = mk_gg_function(x̄_p_expr)
    steady_state! = nothing # not supported
    allocate_solver_cache = mk_gg_function(allocate_solver_cache_expr)

    return FirstOrderPerturbationModel(; n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ!,
                                                  Γ_p!, Ω!, Ω_p!, H!, H_yp!, H_y!, H_xp!,
                                                  H_x!, H_yp_p!, H_y_p!, H_xp_p!, H_x_p!,
                                                  H_p!, Ψ!, H̄!, H̄_w!, ȳ_iv!, x̄_iv!, ȳ!,
                                                  x̄!, ȳ_p!, x̄_p!, steady_state!,
                                                  functions_type, select_p_ss_hash,
                                                  select_p_f_ss_hash,
                                                  select_p_perturbation_hash,
                                                  select_p_f_perturbation_hash,
                                                  allocate_solver_cache)
end

function save_first_order_module(H; ȳ = nothing, x̄ = nothing, ȳ_iv = nothing,
                                 x̄_iv = nothing, Γ, Ω = nothing, η, Q = I, p = nothing, y,
                                 x, p_f = nothing, functions_type = DenseFunctions(),
                                 select_p_ss_hash = I, select_p_f_ss_hash = I,
                                 select_p_perturbation_hash = I,
                                 select_p_f_perturbation_hash = I, simplify = true,
                                 skipzeros = true, parallel = ModelingToolkit.SerialForm(),
                                 model_name,
                                 model_cache_location = default_model_cache_location(),
                                 overwrite_model_cache = false, verbose = false)

    model_cache_path = joinpath(model_cache_location, model_name * ".jl")

    # only load cache if the module isn't already loaded in memory
    if (isdefined(Main, Symbol(model_name)) && !overwrite_model_cache)
        verbose && printstyled("Using existing module $model_name\n", color = :cyan)
        return model_cache_path = model_cache_path
    end

    # if path already exists
    if (ispath(model_cache_path) && !overwrite_model_cache)
        # path exists and not overwriting
        verbose &&
            printstyled("Model already generated at $model_cache_path\n", color = :cyan)
    else
        mod = generate_first_order_model(H; y, x, ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, p_f,
                                         functions_type, simplify, parallel, skipzeros,
                                         verbose)
        @unpack n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr, H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr, H_x_p_expr, H_p_expr, Ψ_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr, ȳ_expr, x̄_expr, ȳ_p_expr, x̄_p_expr, functions_type, allocate_solver_cache_expr = mod

        mkpath(model_cache_location)
        open(model_cache_path, "w") do io
            write(io, "module $(model_name)\n")
            write(io,
                  "using SparseArrays, LinearAlgebra, DifferentiableStateSpaceModels, LaTeXStrings, ModelingToolkit\n")
            write(io, "const n_y = $n_y\n")
            write(io, "const n_x = $n_x\n")
            write(io, "const n = $n\n")
            write(io, "const n_p = $n_p\n")
            write(io, "const n_ϵ = $n_ϵ\n")
            write(io, "const n_z = $n_z\n")
            write(io, "const functions_type() = $functions_type\n")
            if n_ϵ == 1
                write(io, "const η = reshape($η, $n_x, $n_ϵ)\n")
            else
                write(io, "const η = $η\n")
            end
            write(io, "const Q = $Q\n")
            write(io, "const Γ! = $(Γ_expr)\n")
            write(io, "const Γ_p! = $(Γ_p_expr)\n")
            write(io, "const Ω! = $(Ω_expr)\n")
            write(io, "const Ω_p! = $(Ω_p_expr)\n")
            write(io, "const H! = $(H_expr)\n")
            write(io, "const H_yp! = $(H_yp_expr)\n")
            write(io, "const H_y! = $(H_y_expr)\n")
            write(io, "const H_xp! = $(H_xp_expr)\n")
            write(io, "const H_x! = $(H_x_expr)\n")
            write(io, "const H_yp_p! = $(H_yp_p_expr)\n")
            write(io, "const H_y_p! = $(H_y_p_expr)\n")
            write(io, "const H_xp_p! = $(H_xp_p_expr)\n")
            write(io, "const H_x_p! = $(H_x_p_expr)\n")
            write(io, "const H_p! = $(H_p_expr)\n")
            write(io, "const Ψ! = $(Ψ_expr)\n")
            write(io, "const H̄! = $(H̄_expr)\n")
            write(io, "const H̄_w! = $(H̄_w_expr)\n")
            write(io, "const ȳ_iv! = $(ȳ_iv_expr)\n")
            write(io, "const x̄_iv! = $(x̄_iv_expr)\n")
            write(io, "const ȳ! = $(ȳ_expr)\n")
            write(io, "const x̄! = $(x̄_expr)\n")
            write(io, "const ȳ_p! = $(ȳ_p_expr)\n")
            write(io, "const x̄_p! = $(x̄_p_expr)\n")
            write(io, "const steady_state! = nothing\n")
            write(io, "const allocate_solver_cache = $(allocate_solver_cache_expr)\n")
            write(io, "const select_p_ss_hash = $(select_p_ss_hash)\n")
            write(io, "const select_p_f_ss_hash = $(select_p_f_ss_hash)\n")
            write(io, "const select_p_perturbation_hash = $(select_p_perturbation_hash)\n")
            write(io,
                  "const select_p_f_perturbation_hash = $(select_p_f_perturbation_hash)\n")
            return write(io, "end\n") # end module
        end
        verbose && printstyled("Saved $model_name to $model_cache_path\n", color = :cyan)
    end

    # if the module was included, gets the module name, otherwise returns nothing
    return model_cache_path
end


# Probably a cleaner way to avoid the copy/paste, but it is a clear pattern to adapt
function generate_second_order_model(H; ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, y, x, p_f,
    functions_type, skipzeros, simplify, parallel, verbose)

is_sparse = (typeof(functions_type) <: SparseFunctions)
y_vars = connect_markov_variables(y)
x_vars = connect_markov_variables(x)
n_y = length(y_vars)
n_x = length(x_vars)
n = n_y + n_x
n_p = isnothing(p) ? 0 : length(p)
n_ϵ = size(η, 2)
n_z = (Q == I) ? n : size(Q, 1)

# Extract triplets from  y_vars, x_vars for connected variable names
y = [v[1] for v in y_vars]
x = [v[1] for v in x_vars]
y_p = [v[2] for v in y_vars]
x_p = [v[2] for v in x_vars]
y_ss = [v[3] for v in y_vars]
x_ss = [v[3] for v in x_vars]
y_p_substitutions = [y_p[i] => y[i] for i in eachindex(y)]
x_p_substitutions = [x_p[i] => x[i] for i in eachindex(x)]
y_ss_substitutions = [y_ss[i] => y[i] for i in eachindex(y)]
x_ss_substitutions = [x_ss[i] => x[i] for i in eachindex(x)]
all_substitutions = vcat(y_p_substitutions, x_p_substitutions, y_ss_substitutions,
x_ss_substitutions)

# ensure no reuse of variable
allunique([p; p_f; y; x; y_p; x_p; y_ss; x_ss]) ||
throw(ArgumentError("Overlapping variables or parameters"))

# sort variables in equation assignment form.
ȳ_iv = sort_by_variables(ȳ_iv, y_ss)
x̄_iv = sort_by_variables(x̄_iv, x_ss)
ȳ = sort_by_variables(ȳ, y_ss)
x̄ = sort_by_variables(x̄, x_ss)

# steady state requiers differentiation after substitution, and wrt [y; x]
H̄ = deepcopy(H)
H̄_sub = substitute_and_simplify(H̄, all_substitutions; simplify)

# Derivatives utilities return nothing if either argument nothing
H_yp = recursive_differentiate(H, y_p, is_sparse)
H_y = recursive_differentiate(H, y, is_sparse)
H_xp = recursive_differentiate(H, x_p, is_sparse)
H_x = recursive_differentiate(H, x, is_sparse)
H_p = recursive_differentiate(H, p, is_sparse)
Γ_p = recursive_differentiate(Γ, p, false)  # solution object required dense
Ω_p = recursive_differentiate(Ω, p, false)
ȳ_p = recursive_differentiate(ȳ, p, false)
x̄_p = recursive_differentiate(x̄, p, false)
H̄_w = recursive_differentiate(H̄_sub, [y; x], false) # differentiate post-substitution wrt w = [y;x], force a dense one
H_yp_p = recursive_differentiate(H_yp, p, is_sparse)
H_xp_p = recursive_differentiate(H_xp, p, is_sparse)
H_y_p = recursive_differentiate(H_y, p, is_sparse)
H_x_p = recursive_differentiate(H_x, p, is_sparse)
Ψ = stack_hessians(H, [y_p; y; x_p; x], is_sparse)
Ψ_p = (n_p == 0) ? nothing : recursive_differentiate(Ψ, p, is_sparse)
Ψ_yp = recursive_differentiate(Ψ, y_p, is_sparse)
Ψ_y = recursive_differentiate(Ψ, y, is_sparse)
Ψ_xp = recursive_differentiate(Ψ, x_p, is_sparse)
Ψ_x = recursive_differentiate(Ψ, x, is_sparse)

# apply substitutions and simplify if required.
H_yp_sub = substitute_and_simplify(H_yp, all_substitutions; simplify)
H_xp_sub = substitute_and_simplify(H_xp, all_substitutions; simplify)
H_x_sub = substitute_and_simplify(H_x, all_substitutions; simplify)
H_y_sub = substitute_and_simplify(H_y, all_substitutions; simplify)
H_p_sub = substitute_and_simplify(H_p, all_substitutions; simplify)
H_yp_p_sub = substitute_and_simplify(H_yp_p, all_substitutions; simplify)
H_y_p_sub = substitute_and_simplify(H_y_p, all_substitutions; simplify)
H_xp_p_sub = substitute_and_simplify(H_xp_p, all_substitutions; simplify)
H_x_p_sub = substitute_and_simplify(H_x_p, all_substitutions; simplify)
Ψ_sub = substitute_and_simplify(Ψ, all_substitutions; simplify)
Ψ_p_sub = substitute_and_simplify(Ψ_p, all_substitutions; simplify)
Ψ_yp_sub = substitute_and_simplify(Ψ_yp, all_substitutions; simplify)
Ψ_y_sub = substitute_and_simplify(Ψ_y, all_substitutions; simplify)
Ψ_xp_sub = substitute_and_simplify(Ψ_xp, all_substitutions; simplify)
Ψ_x_sub = substitute_and_simplify(Ψ_x, all_substitutions; simplify)
ȳ_p_sub = substitute_and_simplify(ȳ_p, []; simplify)
x̄_p_sub = substitute_and_simplify(x̄_p, []; simplify)

# Sparse allocations if needbe.
if is_sparse
allocate_solver_cache_expr = :(m -> SecondOrderSolverCache(; p_hash = zero(UInt64),
                                  p_f_hash = zero(UInt64),
                                  p_ss_hash = zero(UInt64),
                                  p_f_ss_hash = zero(UInt64),
                                  p_perturbation_hash = zero(UInt64),
                                  p_f_perturbation_hash = zero(UInt64),
                                  H = zeros(m.n),
                                  H_yp = $(generate_undef_constructor(H_yp_sub)),
                                  H_y = $(generate_undef_constructor(H_y_sub)),
                                  H_xp = $(generate_undef_constructor(H_xp_sub)),
                                  H_x = $(generate_undef_constructor(H_x_sub)),
                                  H_yp_p = $(generate_undef_constructor(H_yp_p_sub)),
                                  H_y_p = $(generate_undef_constructor(H_y_p_sub)),
                                  H_xp_p = $(generate_undef_constructor(H_xp_p_sub)),
                                  H_x_p = $(generate_undef_constructor(H_x_p_sub)),
                                  H_p = $(generate_undef_constructor(H_p_sub)),
                                  Γ = zeros(m.n_ϵ, m.n_ϵ),
                                  B = zeros(m.n_x, m.n_ϵ),
                                  Ω = isnothing(m.Ω!) ?
                                      nothing :
                                      zeros(m.n_z),
                                  Ψ = $(generate_undef_constructor(Ψ_sub)),
                                  Γ_p = map(_ -> zeros(m.n_ϵ,
                                                       m.n_ϵ),
                                            1:(m.n_p)),
                                  B_p = map(_ -> zeros(m.n_x,
                                                       m.n_ϵ),
                                            1:(m.n_p)),
                                  Ω_p = isnothing(m.Ω_p!) ?
                                        nothing :
                                        zeros(m.n_z,
                                              m.n_p),
                                  x = zeros(m.n_x),
                                  y = zeros(m.n_y),
                                  y_p = zeros(m.n_y,
                                              m.n_p),
                                  x_p = zeros(m.n_x,
                                              m.n_p),
                                  g_x = zeros(m.n_y,
                                              m.n_x),
                                  h_x = zeros(m.n_x,
                                              m.n_x),
                                  g_x_p = map(_ -> zeros(m.n_y,
                                                         m.n_x),
                                              1:(m.n_p)),
                                  h_x_p = map(_ -> zeros(m.n_y,
                                                         m.n_x),
                                              1:(m.n_p)),
                                  Σ = Symmetric(zeros(m.n_ϵ,
                                                      m.n_ϵ)),
                                  Σ_p = map(_ -> Symmetric(zeros(m.n_ϵ,
                                                                 m.n_ϵ)),
                                            1:(m.n_p)),
                                  m.Q, m.η,
                                  g_xx = zeros(m.n_y,
                                               m.n_x,
                                               m.n_x),
                                  h_xx = zeros(m.n_x,
                                               m.n_x,
                                               m.n_x),
                                  g_σσ = zeros(m.n_y),
                                  h_σσ = zeros(m.n_x),
                                  Ψ_p = $(generate_undef_constructor(Ψ_p_sub)),
                                  Ψ_yp = $(generate_undef_constructor(Ψ_yp_sub)),
                                  Ψ_y = $(generate_undef_constructor(Ψ_y_sub)),
                                  Ψ_xp = $(generate_undef_constructor(Ψ_xp_sub)),
                                  Ψ_x = $(generate_undef_constructor(Ψ_x_sub)),
                                  g_xx_p = map(_ -> zeros(m.n_y,
                                                          m.n_x,
                                                          m.n_x),
                                               1:(m.n_p)),
                                  h_xx_p = map(_ -> zeros(m.n_x,
                                                          m.n_x,
                                                          m.n_x),
                                               1:(m.n_p)),
                                  g_σσ_p = zeros(m.n_y,
                                                 m.n_p),
                                  h_σσ_p = zeros(m.n_x,
                                                 m.n_p),
                                  C_1 = zeros(m.n_z,
                                                m.n_x),
                                  C_1_p = map(_ -> zeros(m.n_z,
                                                           m.n_x),
                                                1:(m.n_p)),
                                  C_0 = zeros(m.n_z),
                                  C_0_p = zeros(m.n_z,
                                                   m.n_p),
                                  C_2 = zeros(m.n_z,
                                                 m.n_x,
                                                 m.n_x),
                                  C_2_p = map(_ -> zeros(m.n_z,
                                                            m.n_x,
                                                            m.n_x),
                                                 1:(m.n_p)),
                                  A_0_p = zeros(m.n_x,
                                                 m.n_p),
                                  A_1_p = map(_ -> zeros(m.n_x,
                                                 m.n_x),
                                                1:(m.n_p)),
                                  A_2_p = map(_ -> zeros(m.n_x,
                                                m.n_x,
                                                m.n_x),
                                                1:(m.n_p)),
                                  V = cholesky(Array(I(m.n_x))),
                                  V_p = map(_ -> zeros(m.n_x,
                                                       m.n_x),
                                            1:(m.n_p))))
else #No GPU or tensor versions implemented yet
allocate_solver_cache_expr = :(m -> SecondOrderSolverCache(m))
end
# Generate all functions
Γ_expr = build_dssm_function(Γ, p, p_f; parallel, skipzeros)
Γ_p_expr = build_dssm_function(Γ_p, p, p_f; parallel, skipzeros)
Ω_expr = build_dssm_function(Ω, p, p_f; parallel, skipzeros)
Ω_p_expr = build_dssm_function(Ω_p, p, p_f; parallel, skipzeros)
H_expr = build_dssm_function(H, y_p, y, y_ss, x_p, x, x_ss, p, p_f; parallel, skipzeros)
H_yp_expr = build_dssm_function(H_yp_sub, y, x, p, p_f; parallel, skipzeros)
H_y_expr = build_dssm_function(H_y_sub, y, x, p, p_f; parallel, skipzeros)
H_xp_expr = build_dssm_function(H_xp_sub, y, x, p, p_f; parallel, skipzeros)
H_x_expr = build_dssm_function(H_x_sub, y, x, p, p_f; parallel, skipzeros)
H_yp_p_expr = build_dssm_function(H_yp_p_sub, y, x, p, p_f; parallel, skipzeros)
H_y_p_expr = build_dssm_function(H_y_p_sub, y, x, p, p_f; parallel, skipzeros)
H_xp_p_expr = build_dssm_function(H_xp_p_sub, y, x, p, p_f; parallel, skipzeros)
H_x_p_expr = build_dssm_function(H_x_p_sub, y, x, p, p_f; parallel, skipzeros)
H_p_expr = build_dssm_function(H_p_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_expr = build_dssm_function(Ψ_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_p_expr = build_dssm_function(Ψ_p_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_yp_expr = build_dssm_function(Ψ_yp_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_y_expr = build_dssm_function(Ψ_y_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_xp_expr = build_dssm_function(Ψ_xp_sub, y, x, p, p_f; parallel, skipzeros)
Ψ_x_expr = build_dssm_function(Ψ_x_sub, y, x, p, p_f; parallel, skipzeros)
H̄_expr = build_dssm_function(H̄_sub, [y; x], p, p_f; parallel, skipzeros)
H̄_w_expr = build_dssm_function(H̄_w, [y; x], p, p_f; parallel, skipzeros)
ȳ_iv_expr = build_dssm_function(ȳ_iv, p, p_f; parallel, skipzeros)
x̄_iv_expr = build_dssm_function(x̄_iv, p, p_f; parallel, skipzeros)
ȳ_expr = build_dssm_function(ȳ, p, p_f; parallel, skipzeros)
x̄_expr = build_dssm_function(x̄, p, p_f; parallel, skipzeros)
ȳ_p_expr = build_dssm_function(ȳ_p_sub, p, p_f; parallel, skipzeros)
x̄_p_expr = build_dssm_function(x̄_p_sub, p, p_f; parallel, skipzeros)

verbose && printstyled("Done Building Model\n", color = :cyan)

return (; n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr,
H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr,
H_x_p_expr, H_p_expr, Ψ_expr, Ψ_p_expr, Ψ_yp_expr, Ψ_y_expr, Ψ_xp_expr,
Ψ_x_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr, ȳ_expr, x̄_expr,
ȳ_p_expr, x̄_p_expr, functions_type, allocate_solver_cache_expr)
end

function SecondOrderPerturbationModel(H; ȳ = nothing, x̄ = nothing,
                ȳ_iv = nothing, x̄_iv = nothing, Γ,
                Ω = nothing, η, Q = I, p = nothing, y, x,
                p_f = nothing,
                functions_type = DenseFunctions(),
                select_p_ss_hash = I,
                select_p_f_ss_hash = I,
                select_p_perturbation_hash = I,
                select_p_f_perturbation_hash = I,
                simplify = true, skipzeros = true,
                parallel = ModelingToolkit.SerialForm(),
                verbose = false)
mod = generate_second_order_model(H; y, x, ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, p_f,
     functions_type, simplify, skipzeros, parallel,
     verbose)
@unpack n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr, H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr, H_x_p_expr, H_p_expr, Ψ_expr, Ψ_p_expr, Ψ_yp_expr, Ψ_y_expr, Ψ_xp_expr, Ψ_x_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr, ȳ_expr, x̄_expr, ȳ_p_expr, x̄_p_expr, functions_type, allocate_solver_cache_expr = mod
Γ! = mk_gg_function(Γ_expr)
Γ_p! = mk_gg_function(Γ_p_expr)
Ω! = mk_gg_function(Ω_expr)
Ω_p! = mk_gg_function(Ω_p_expr)
H! = mk_gg_function(H_expr)
H_yp! = mk_gg_function(H_yp_expr)
H_y! = mk_gg_function(H_y_expr)
H_xp! = mk_gg_function(H_xp_expr)
H_x! = mk_gg_function(H_x_expr)
H_yp_p! = mk_gg_function(H_yp_p_expr)
H_y_p! = mk_gg_function(H_y_p_expr)
H_xp_p! = mk_gg_function(H_xp_p_expr)
H_x_p! = mk_gg_function(H_x_p_expr)
H_p! = mk_gg_function(H_p_expr)
Ψ! = mk_gg_function(Ψ_expr)
Ψ_p! = mk_gg_function(Ψ_p_expr)
Ψ_yp! = mk_gg_function(Ψ_yp_expr)
Ψ_y! = mk_gg_function(Ψ_y_expr)
Ψ_xp! = mk_gg_function(Ψ_xp_expr)
Ψ_x! = mk_gg_function(Ψ_x_expr)
H̄! = mk_gg_function(H̄_expr)
H̄_w! = mk_gg_function(H̄_w_expr)
ȳ_iv! = mk_gg_function(ȳ_iv_expr)
x̄_iv! = mk_gg_function(x̄_iv_expr)
ȳ! = mk_gg_function(ȳ_expr)
x̄! = mk_gg_function(x̄_expr)
ȳ_p! = mk_gg_function(ȳ_p_expr)
x̄_p! = mk_gg_function(x̄_p_expr)
steady_state! = nothing
allocate_solver_cache = mk_gg_function(allocate_solver_cache_expr)

return SecondOrderPerturbationModel(; n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ!,
                  Γ_p!, Ω!, Ω_p!, H!, H_yp!, H_y!, H_xp!,
                  H_x!, H_yp_p!, H_y_p!, H_xp_p!, H_x_p!,
                  H_p!, Ψ!, Ψ_p!, Ψ_yp!, Ψ_y!, Ψ_xp!, Ψ_x!,
                  H̄!, H̄_w!, ȳ_iv!, x̄_iv!, ȳ!, x̄!,
                  steady_state!, ȳ_p!, x̄_p!,
                  functions_type, select_p_ss_hash,
                  select_p_f_ss_hash,
                  select_p_perturbation_hash,
                  select_p_f_perturbation_hash,
                  allocate_solver_cache)
end

function save_second_order_module(H; ȳ = nothing, x̄ = nothing, ȳ_iv = nothing,
 x̄_iv = nothing, Γ, Ω = nothing, η, Q = I, p = nothing, y,
 x, p_f = nothing, functions_type = DenseFunctions(),
 select_p_ss_hash = I, select_p_f_ss_hash = I,
 select_p_perturbation_hash = I,
 select_p_f_perturbation_hash = I, simplify = true,
 skipzeros = true, parallel = ModelingToolkit.SerialForm(),
 model_name,
 model_cache_location = default_model_cache_location(),
 overwrite_model_cache = false, verbose = false)

model_cache_path = joinpath(model_cache_location, model_name * ".jl")

# only load cache if the module isn't already loaded in memory
if (isdefined(Main, Symbol(model_name)) && !overwrite_model_cache)
verbose && printstyled("Using existing module $model_name\n", color = :cyan)
return model_cache_path = model_cache_path
end

# if path already exists
if (ispath(model_cache_path) && !overwrite_model_cache)
# path exists and not overwriting
verbose && printstyled("Model already generated at $model_cache_path\n", color = :cyan)
else
mod = generate_second_order_model(H; y, x, ȳ, x̄, ȳ_iv, x̄_iv, Γ, Ω, η, Q, p, p_f,
         functions_type, simplify, parallel, skipzeros,
         verbose)
@unpack n, n_y, n_x, n_p, n_ϵ, n_z, η, Q, Γ_expr, Γ_p_expr, Ω_expr, Ω_p_expr, H_expr, H_yp_expr, H_y_expr, H_xp_expr, H_x_expr, H_yp_p_expr, H_y_p_expr, H_xp_p_expr, H_x_p_expr, H_p_expr, Ψ_expr, H̄_expr, H̄_w_expr, ȳ_iv_expr, x̄_iv_expr, ȳ_expr, x̄_expr, ȳ_p_expr, x̄_p_expr, functions_type, allocate_solver_cache_expr = mod
@unpack H_yp_p_expr, H_y_p_expr, H_xp_p_expr, H_x_p_expr, H_p_expr, Ψ_expr, Ψ_p_expr, Ψ_yp_expr, Ψ_y_expr, Ψ_xp_expr, Ψ_x_expr, = mod

mkpath(model_cache_location)
open(model_cache_path, "w") do io
write(io, "module $(model_name)\n")
write(io,
"using SparseArrays, LinearAlgebra, DifferentiableStateSpaceModels, LaTeXStrings, ModelingToolkit\n")
write(io, "const n_y = $n_y\n")
write(io, "const n_x = $n_x\n")
write(io, "const n = $n\n")
write(io, "const n_p = $n_p\n")
write(io, "const n_ϵ = $n_ϵ\n")
write(io, "const n_z = $n_z\n")
write(io, "const functions_type() = $functions_type\n")
if n_ϵ == 1
write(io, "const η = reshape($η, $n_x, $n_ϵ)\n")
else
write(io, "const η = $η\n")
end
write(io, "const Q = $Q\n")
write(io, "const Γ! = $(Γ_expr)\n")
write(io, "const Γ_p! = $(Γ_p_expr)\n")
write(io, "const Ω! = $(Ω_expr)\n")
write(io, "const Ω_p! = $(Ω_p_expr)\n")
write(io, "const H! = $(H_expr)\n")
write(io, "const H_yp! = $(H_yp_expr)\n")
write(io, "const H_y! = $(H_y_expr)\n")
write(io, "const H_xp! = $(H_xp_expr)\n")
write(io, "const H_x! = $(H_x_expr)\n")
write(io, "const H_yp_p! = $(H_yp_p_expr)\n")
write(io, "const H_y_p! = $(H_y_p_expr)\n")
write(io, "const H_xp_p! = $(H_xp_p_expr)\n")
write(io, "const H_x_p! = $(H_x_p_expr)\n")
write(io, "const H_p! = $(H_p_expr)\n")
write(io, "const Ψ! = $(Ψ_expr)\n")
write(io, "const Ψ_p! = $(Ψ_p_expr)\n")
write(io, "const Ψ_yp! = $(Ψ_yp_expr)\n")
write(io, "const Ψ_y! = $(Ψ_y_expr)\n")
write(io, "const Ψ_xp! = $(Ψ_xp_expr)\n")
write(io, "const Ψ_x! = $(Ψ_x_expr)\n")
write(io, "const H̄! = $(H̄_expr)\n")
write(io, "const H̄_w! = $(H̄_w_expr)\n")
write(io, "const ȳ_iv! = $(ȳ_iv_expr)\n")
write(io, "const x̄_iv! = $(x̄_iv_expr)\n")
write(io, "const ȳ! = $(ȳ_expr)\n")
write(io, "const x̄! = $(x̄_expr)\n")
write(io, "const ȳ_p! = $(ȳ_p_expr)\n")
write(io, "const x̄_p! = $(x̄_p_expr)\n")
write(io, "const steady_state! = nothing\n")
write(io, "const allocate_solver_cache = $(allocate_solver_cache_expr)\n")
write(io, "const select_p_ss_hash = $(select_p_ss_hash)\n")
write(io, "const select_p_f_ss_hash = $(select_p_f_ss_hash)\n")
write(io, "const select_p_perturbation_hash = $(select_p_perturbation_hash)\n")
write(io,
"const select_p_f_perturbation_hash = $(select_p_f_perturbation_hash)\n")
return write(io, "end\n") # end module
end
verbose && printstyled("Saved $model_name to $model_cache_path\n", color = :cyan)
end

# if the module was included, gets the module name, otherwise returns nothing
return model_cache_path
end
