using DifferentiableStateSpaceModels, Symbolics, LinearAlgebra, Test
using DifferentiableStateSpaceModels.Examples

@testset "FVGQ20 First Order" begin
    m = @include_example_module(Examples.FVGQ20)
    p_d = (β=0.998, h=0.97, ϑ=1.17, κ=9.51, α=0.21, θp=0.82, χ=0.63, γR=0.77, γy=0.19, γΠ=1.29, Πbar=1.01, ρd=0.12, ρφ=0.93, ρg=0.95, g_bar=0.3, σ_A=exp(-3.97), σ_d=exp(-1.51), σ_φ=exp(-2.36), σ_μ=exp(-5.43), σ_m=exp(-5.85), σ_g=exp(-3.0), Λμ=3.4e-3, ΛA=2.8e-3)
    p_f = (δ=0.025, ε=10, ϕ=0, γ2=0.001, Ω_ii=sqrt(1e-5))

    c = SolverCache(m, Val(1), p_d)
    sol = generate_perturbation(m, p_d, p_f; cache=c)
    generate_perturbation_derivatives!(m, p_d, p_f, c)

    @test sol.retcode == :Success
    @test sol.A ≈ [-6.574343880545165 -9.697555892032119 0.4081638833808286 -1.9778582376145583e-16 6.672244910947333 5.939416004880197 -4.270562962213779 0.23818034038345637 -0.5854427460938404 -1.1276837649128768 -1.7465272244094843 17.732179345016092 9.970731128386726 -12.451855870379198; -168.71391092047278 -216.57848565632133 9.27455224729595 -4.486234952716449e-15 149.50769475127888 132.892901188581 -95.60501039194422 5.263144329782749 -13.673004435032567 -25.249142782145704 -37.04185986399249 412.51208650565025 222.83144030677184 -278.752899299713; -111.42032878226023 -148.24773107624333 5.5507684380361395 -3.121707375452398e-15 103.29725599787731 94.14665891354095 -66.03586179472633 4.3894229085345575 -9.309878283993548 -14.714442961461309 -27.892531933721713 284.84042643290974 154.43040039147073 -190.86788735923585; 45.87880132776866 53.858289775301756 -3.16320719864632 9.790752036557883e-16 -35.56275629576426 -28.518291997305152 22.608557961129197 -0.14882093232454513 3.4018346260787977 9.263217264732903 4.900709301263245 -98.17363844894555 -52.41473093562862 67.6053272802169; -58.27317315053919 -70.00508173191203 4.762636466105313 -1.3907060275356816e-15 47.26056519205212 38.56290474126507 -29.68446934042827 0.7154809360460207 -4.406154144475667 -10.958287291843757 -8.477775729016978 128.95017575802817 69.76235051674095 -88.46987806580346; -247.31785590769232 -324.8711246781365 11.949321043336276 -6.787364185394931e-15 225.23304682798377 203.94616229226605 -143.93507620877435 8.917423531612153 -20.46387751147769 -34.534003313083815 -59.31258225426329 622.213650222867 336.4305312231251 -417.88780968791235; 3.1790019336851585 4.29464914238688 -0.11615582573248413 7.592113077990863e-17 -3.071679446030529 -2.86222205024117 2.831651432665515 -0.1636602316028529 0.27802566594351547 0.3641178196264159 0.987847210651594 -8.17560706158536 -4.6473166829685075 5.581099075819241; 979.6147920503815 1272.5256664097274 -52.08606824926272 2.6284032254010623e-14 -877.7229555350443 -783.9043700726019 560.3427008472619 -31.440372907954494 79.94171034583448 142.74250134258023 220.0868628488879 -2420.9437918323965 -1308.87152023847 1631.512761708278; -8.339180893456347e-14 -5.214358899007996e-13 1.2012252468806183e-14 5.908394333861841e-22 3.4980012452979993e-13 3.209431624713702e-13 -2.1187319104566474e-13 1.349293662482963e-14 0.11999999999997721 -0.0037697755356567004 -0.00022457145416837973 -0.0005044163547007832 0.00011676072268819539 -0.010070855520741112; -1.200344618526664e-11 -1.5152584337907102e-11 6.350525090851576e-13 7.898089235538926e-18 1.052755904526928e-11 9.423371667884284e-12 -6.797178959232524e-12 4.122090291498547e-13 -9.833436278769562e-13 0.9299999999980973 0.00021417462691080663 -0.0648804346658765 0.0005621958921623196 0.06543333724185131; 3.862478590006177e-12 1.2777657524603814e-11 -2.5387804418344406e-13 3.186838666968555e-19 -8.621879793469812e-12 -7.953872718976425e-12 5.305714323483182e-12 -3.383000657090825e-13 6.205070916575393e-13 -4.5218734576920194e-13 2.9247395779942913e-12 -1.9765769359629438e-11 -1.3019938799425658e-11 0.13510875126367242; 1.0705131313136659e-12 3.656290596927839e-12 -7.873901230013141e-14 3.9492337407583635e-20 -2.4670436420061355e-12 -2.270049805919267e-12 1.5175491412136339e-12 -9.637520892468294e-14 1.764348863228567e-13 -1.3537060775003133e-13 8.238576082551709e-13 -5.649860477062951e-12 -3.728708729192394e-12 0.016743114242558522; -2.685786197315766e-12 -9.060482150837633e-12 1.9643097975323396e-13 -7.160728997126952e-20 6.113224459901847e-12 5.623428424616271e-12 -3.755979007136294e-12 2.3827388120859045e-13 -4.382455094154887e-13 3.2663343026530086e-13 -2.0302813716281288e-12 1.4038358546336782e-11 9.23925674823589e-12 -0.030358523062136576; -5.076289755265102e-12 -6.539351320098492e-12 2.661354604536113e-13 2.2407850737012965e-18 4.5320729305898125e-12 4.059362362897056e-12 -2.9293512945858482e-12 1.7513874627762892e-13 -4.2326742855130296e-13 -8.023559613407056e-13 -6.524642427314813e-13 1.3734030102619703e-11 6.895002685675836e-12 0.9499999999913878]
    @show sol.C ≈ [0.046682850885188414 0.05930396759586929 0.5124199967950123 0.0 -0.19304430327244906 0.007127498526411165 0.06539752411292642 -0.0017145463126460162 0.0014650872902314323 0.056186338595056756 0.0010445094854684119 -0.0644816219419623 -0.2548524912562035 0.052000567405129226; 0.04848049555975208 0.05379806906178239 0.1434558395931211 0.0 0.6720261809473577 -0.024812260881409483 0.03410991773797231 -0.0017214819741272426 0.0014170563030341846 0.020359771812883194 0.014358229788893229 -0.0013258757233242705 0.8871929577850087 0.05190182556133141; 0.4733058027331458 0.6359954782844232 -0.7424379526200766 -0.8998686798130806 -2.8248246078053247 0.10429695613070526 0.9870305698304098 -0.015783391320695707 0.012204664624805324 0.7203057862292772 -0.02244989846562421 -0.7463737894434745 -3.729266165627129 0.5471617102883314; 0.7924415036295586 0.8284343678742737 -0.19631975872429247 0.0 -0.6446734730418766 -0.616178253872422 0.33653254769120866 -0.027752313116301518 0.0224797460923251 0.08442300123162487 0.056551418981011355 -0.854827568836762 -0.851082564294199 0.8346283115774529; 0.7095449970937021 0.7149458978760908 -0.06799364123668006 0.0 -0.10822645419616717 0.003995890475364564 1.0031833138000825 -0.025718053394227534 0.020408148007625304 -0.051400061887996056 0.06913294700293195 -0.7124691120650971 -0.14287798709487276 0.7379111193434185; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.9966057734548978 0.0 0.0 0.0]
    @show sol.Q ≈ [0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0]
    @test sol.y ≈ [0.8154780241332105, 0.2783051143056207, 1.01, 1.1112732584577985, 1.0165356601604938, 1.562547340626902, 1.0022208173087115, 1.0186852828361062, 1.0, 1.0, 1.2953143777555123, 1.0044580087526465, 0.03489877588693624, 1.0, 0.8982498823496541, 12.044079264159267, 13.382310293510294, 0.004448101265822784, 0.009950330853168092, 0.01640043478966387, 0.0, 0.0, 0.0, 0.0034]
    @test sol.x ≈ [0.8154780241332105, 0.2783051143056207, 1.01, 1.1112732584577985, 1.0165356601604938, 1.562547340626902, 1.0022208173087115, 8.53122233338444, 1.0, 1.0, 1.0034057865562385, 1.0028039236612292, 1.0, 0.4687642021880705]
    @test sol.B ≈ [0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.2209099779593782 0.0 0.0 0.0 0.0 0.0; 0.0 0.09442022319630236 0.0 0.0 0.0 0.0; 0.0 0.0 0.004383095802668776 0.0 0.0 0.0; 0.0 0.0 0.0 0.018873433135151486 0.0 0.0; 0.0 0.0 0.0 0.0 0.002879899158088243 0.0; 0.0 0.0 0.0 0.0 0.0 0.049787068367863944]
    @test sol.η ≈ [0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 0.0 0.0 0.0 0.0 0.0 0.0; 1.0 0.0 0.0 0.0 0.0 0.0; 0.0 1.0 0.0 0.0 0.0 0.0; 0.0 0.0 1.0 0.0 0.0 0.0; 0.0 0.0 0.0 1.0 0.0 0.0; 0.0 0.0 0.0 0.0 1.0 0.0; 0.0 0.0 0.0 0.0 0.0 1.0]
    @test sol.Γ ≈ [0.2209099779593782 0.0 0.0 0.0 0.0 0.0; 0.0 0.09442022319630236 0.0 0.0 0.0 0.0; 0.0 0.0 0.004383095802668776 0.0 0.0 0.0; 0.0 0.0 0.0 0.018873433135151486 0.0 0.0; 0.0 0.0 0.0 0.0 0.002879899158088243 0.0; 0.0 0.0 0.0 0.0 0.0 0.049787068367863944]
end

