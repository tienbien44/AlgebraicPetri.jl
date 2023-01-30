module TypedPetri
export prim_petri, strip_names, prim_cospan, oapply_typed, typed_product,
  add_params, add_reflexives, pairwise_id_petri, pairwise_id_typed_petri

using Catlab
using Catlab.CategoricalAlgebra
using Catlab.WiringDiagrams
using AlgebraicPetri
using AlgebraicPetri: LabelledPetriNetUntyped, OpenLabelledPetriNetUntyped, LabelledReactionNetUntyped


"""
Takes in a petri net and a transition in that petri net,
constructs a petri net with just that transition, returns
the acsettransformation from that into the type system.
"""
function prim_petri(type_system, transition)
  prim = typeof(type_system)()
  t = add_transition!(prim)
  s_map = Int[]
  for i in inputs(type_system, transition)
    s = is(type_system, i)
    s′ = add_species!(prim)
    push!(s_map, s)
    add_input!(prim, 1, s′)
  end
  for i in outputs(type_system, transition)
    s = os(type_system, i)
    s′ = add_species!(prim)
    push!(s_map, s)
    add_output!(prim, 1, s′)
  end
  ACSetTransformation(
    prim,
    type_system,
    S=s_map,
    T=[transition],
    O=incident(type_system, transition, :ot),
    I=incident(type_system, transition, :it),
  )
end

"""
Produces the structured cospan of the transition over
different species.
"""
function prim_cospan(type_system, transition)
  prim = prim_petri(type_system, transition)
  p = dom(prim)
  feet = [FinSet(1) for s in 1:ns(p)]
  structured_feet = [PetriNet(1) for s in 1:ns(p)]
  legs = [
    ACSetTransformation(
      structured_feet[s],
      p,
      S = [s],
      T = Int[],
      I = Int[],
      O = Int[],
    )
    for s in 1:ns(p)
  ]
  (OpenPetriNet(Multicospan(p, legs), feet), prim)
end

"""
Takes in a labelled petri net and an undirected wiring diagram,
where each of the boxes is labeled by a symbol that matches the label
of a transition in the petri net. Then produces a petri net given by
colimiting the transitions together, and returns the ACSetTransformation
from that Petri net to the type system.
"""
function oapply_typed(type_system::LabelledPetriNet, uwd, tnames::Vector{Symbol})
  type_system′ = PetriNet(type_system)
  prim_cospan_data = Dict(
    tname(type_system, t) => prim_cospan(type_system′, t)
    for t in 1:nt(type_system)
  )
  prim_cospans = Dict(t => prim_cospan_data[t][1] for t in keys(prim_cospan_data))
  petri, colim = oapply(uwd, prim_cospans; return_colimit=true)
  unlabelled_map = universal(
    colim,
    Multicospan(
      type_system′,
      [prim_cospan_data[subpart(uwd, b, :name)][2] for b in 1:nboxes(uwd)]
    )
  )
  labelled_petri = LabelledPetriNet(unlabelled_map.dom, uwd[:variable], tnames)
  ACSetTransformation(
    labelled_petri,
    type_system;
    unlabelled_map.components...,
    Name=name->nothing
  )
end

r"""
Modify a typed petri net to add "reflexive transitions". These are transitions which go from one species to itself, so they don't change the mass action semantics, but they are important for stratification.

The idea behind this is similar to the fact that the product of the graph *----* with itself is

*    *
    /
   /
  /
 /
*    *

One needs to add self-edges to each of the vertices in *----* to get

*----*
|   /|
|  / |
| /  |
|/   |
*----*

Example:
```julia
add_reflexives(sird_typed, [[:strata], [:strata], [:strata], []], infectious_ontology)
```
"""
function add_reflexives(
  typed_petri::ACSetTransformation,
  reflexive_transitions,
  type_system::AbstractPetriNet
)
  petri = deepcopy(dom(typed_petri))
  type_comps = Dict([k=>collect(v) for (k,v) in pairs(deepcopy(components(typed_petri)))])
  for (s_i,cts) in enumerate(reflexive_transitions)
    for ct in cts
      type_ind = findfirst(==(ct), type_system[:tname])
      is, os = [incident(type_system, type_ind, f) for f in [:it, :ot]]
      new_t = add_part!(petri, :T; tname=ct)
      if petri isa AbstractLabelledReactionNet
        set_subpart!(petri, new_t, :rate, 1.0)
      end
      add_parts!(petri, :I, length(is); is=s_i, it=new_t)
      add_parts!(petri, :O, length(os); os=s_i, ot=new_t)
      push!(type_comps[:T], type_ind)
      append!(type_comps[:I], is); append!(type_comps[:O], os);
    end
  end
  ACSetTransformation(
    petri,
    codom(typed_petri);
    type_comps...,
    Name=x->nothing,
    (petri isa AbstractLabelledReactionNet ? [:Rate=>x->nothing, :Concentration=>x->nothing] : [])...
  )
end

function add_params(
  typed_petri::ACSetTransformation,
  initial_concentrations::AbstractDict{Symbol,Float64},
  rates::AbstractDict{Symbol,Float64}
)
  domain = begin
    pn = LabelledReactionNet{Float64,Float64}()
    copy_parts!(pn, typed_petri.dom)
    for (tlabel, rate) in rates
      set_subpart!(pn, only(incident(typed_petri.dom, tlabel, :tname)), :rate, rate)
    end
    for (slabel, ic) in initial_concentrations
      set_subpart!(pn, only(incident(typed_petri.dom, slabel, :sname)), :concentration, ic)
    end
    pn
  end
  typing = begin
    pn = LabelledReactionNetUntyped{Nothing, Nothing, Nothing}()
    copy_parts!(pn, PetriNet(typed_petri.codom))
    for t in parts(pn, :T)
      set_subpart!(pn, t, :tname, nothing)
      set_subpart!(pn, t, :rate, nothing)
    end
    for s in parts(pn, :S)
      set_subpart!(pn, s, :sname, nothing)
      set_subpart!(pn, s, :concentration, nothing)
    end
    pn
  end
  ACSetTransformation(
    domain,
    typing;
    components(typed_petri)...,
    Name=x->nothing,
    Rate=x->nothing,
    Concentration=x->nothing
  )
end

"""
This takes the "typed product" of two typed Petri nets p1 and p2, which has

- a species for every pair of a species in p1 and a species in p2 with the same type
- a transition for every pair of a transitions in p1 and a species in p2 with the same type

This is the "workhorse" of stratification; this is what actually does the stratification, though you may have to "prepare" the petri nets first with `add_reflexives`

Returns a typed model, i.e. a map in Petri.
"""
function typed_product(p1, p2)
  pb = pullback(p1, p2; product_attrs=true)
  return first(legs(pb)) ⋅ p1
end

""" Make typed Petri net with 'identity' transformation between species pairs.

Assumes a single species type and a single transition type.
"""
function pairwise_id_typed_petri(type_net, stype, ttype, args...)
  net = pairwise_id_petri(args...)
  s = only(incident(type_net, stype, :sname))
  t = only(incident(type_net, ttype, :tname))
  ACSetTransformation(net, type_net;
    S = repeat([s], ns(net)),
    T = repeat([t], nt(net)),
    I = repeat(incident(type_net, t, :it), nt(net)),
    O = repeat(incident(type_net, t, :ot), nt(net)),
    Name = x->nothing
  )
end

""" Make Petri net with 'identity' transformation between all species pairs.
"""
function pairwise_id_petri(names::AbstractVector{Symbol})
  net = LabelledPetriNet()
  add_pairwise_id_transitions!(net, names)
  net
end
function add_pairwise_id_transitions!(net::AbstractPetriNet,
                                      names::AbstractVector{Symbol})
  n = length(names)
  species = add_species!(net, n, sname=names)
  for i in 1:n, j in 1:n
    tname = Symbol(string(names[i], "_", names[j]))
    t = add_transition!(net, tname=tname)
    add_input!(net, t, species[i])
    add_input!(net, t, species[j])
    add_output!(net, t, species[i])
    add_output!(net, t, species[j])
  end
  species
end

end
