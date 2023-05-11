using Requires

function __init__()
  @require Petri="4259d249-1051-49fa-8328-3f8ab9391c33" include("../ext/AlgebraicPetriPetriExt.jl")
  @require Catalyst="479239e8-5488-4da2-87a7-35f2df7eef83" include("../ext/AlgebraicPetriCatalystExt.jl")
  @require ModelingToolkit="961ee093-0014-501f-94e3-6117800e7a78" include("../ext/AlgebraicPetriModelingToolkitExt.jl")
end
