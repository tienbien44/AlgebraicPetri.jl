module AlgebraicPetriCatalystExt

using AlgebraicPetri
using Catlab.CategoricalAlgebra
# TODO: Remove after dropping support for <Julia 1.9
if isdefined(Base, :get_extension)
  using Catalyst
  using Catalyst.Symbolics: scalarize
  import Catalyst: ReactionSystem
else
  using ..Catalyst
  using ..Catalyst.Symbolics: scalarize
  import ..Catalyst: ReactionSystem
end

counter(a) = [count(==(i),a) for i in unique(a)]

""" Convert a general PetriNet to a ReactionSystem

This conversion forgets any labels or rates provided, and converts all
parameters and variables into symbols. It does preserve the ordering of
transitions and states though (Transition 1 has a rate of k[1], state 1 has a
concentration of S[1])
"""
function ReactionSystem(pn::AbstractPetriNet)
  @parameters t k[1:nt(pn)]
  @species (S(t))[collect(1:ns(pn))]

  rxs = map(1:nt(pn)) do t
    inpts = pn[incident(pn, t, :it),:is]
    otpts = pn[incident(pn, t, :ot),:os]
    in_count = collect(counter(inpts))
    ot_count = collect(counter(otpts))
    Reaction(k[t], [S[i] for i in unique(inpts)],
                   [S[o] for o in unique(otpts)],
                   in_count, ot_count)
  end

  ReactionSystem(rxs, t, scalarize(S), scalarize(k), name=:PetriNet)
end


end
