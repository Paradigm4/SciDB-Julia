SciDB-Julia
===========
##Introduction

The SciDB-Julia package allows users of Julia to interface with SciDB. The API follows the Julia convention and allows for using Julia language constructs in SciDB operations.
Requirements

    Julia v0.3 (​http://julialang.org/)
    Julia package "Requests.jl" and its dependencies (​https://github.com/Keno/Requests.jl)
    SciDB 14.3 with Enterprise Edition
    Paradigm4 shim for REST-ful access to SciDB (​https://github.com/Paradigm4/shim)

##Installation and Usage

If you don't have the Julia package "Requests.jl" installed, please install it from within Julia via the following:

    julia> Pkg.add("Requests")

To download the source code for the 14.3 release, change 'branch:master' to 'tag:v14.3.0' and then click 'download', or directly download from https://github.com/Paradigm4/SciDB-Julia/archive/14.3.zip

To load the SciDB-Julia package, ensure that the Julia LOAD_PATH variable points towards the folder in which the package lives.
NOTE: this step is not required unless the package lives in a non-standard location.

    julia> push!(LOAD_PATH, "/path/to/SciDB-Julia")
    3-element Array{Union(UTF8String,ASCIIString),1}:
     "/ssd/julia/usr/local/share/julia/site/v0.3"
     "/ssd/julia/usr/share/julia/site/v0.3"      
     "/path/to/SciDB-Julia"

The Paradigm4 shim must be up-and-running, according to the instructions at the link given above, before proceeding. Once the shim has started, proceed to load the SciDB-Julia package within the Julia environment (there is a small load time as the dependencies themselves load):

    julia> using SciDBJulia

###Example 1 - Multiplying Two Dense SciDB Matrices

Create a Julia array and then use it to create a matching SciDB array. The first invocation of scidb takes a small amount of time to create network connections to the SciDB database. Subsequent invocations should take no noticeable amount of time.

    julia> a=rand(3,4)
    3x4 Array{Float64,2}:
     0.480573  0.684064  0.337876  0.48843 
     0.74014   0.55052   0.344965  0.504495
     0.191254  0.627969  0.341594  0.878666

    julia> A=scidb(a)
    scidb_array("Julia_15993245957846797056_12",3x4 Array{Float64,2}:
     0.480573  0.684064  0.337876  0.48843 
     0.74014   0.55052   0.344965  0.504495
     0.191254  0.627969  0.341594  0.878666,32,false)

_A_ is a handle to the SciDB corresponding SciDB array. It contains _a_ and a pointer to the same array on SciDB. Let's continue to make another array _b_, and its handle for a corresponding array on SciDB, _B_.
    
    julia> b=rand(4,3)
    4x3 Array{Float64,2}:
     0.959354  0.305615   0.375201
     0.600768  0.313162   0.69977 
     0.736307  0.883326   0.90877 
     0.936542  0.0650287  0.958536
    
    julia> B=scidb(b)
    scidb_array("Julia_6140101800367326939_12",4x3 Array{Float64,2}:
     0.959354  0.305615   0.375201
     0.600768  0.313162   0.69977 
     0.736307  0.883326   0.90877 
     0.936542  0.0650287  0.958536,32,false)
    
Let's multiply _A_ and _B_ on SciDB. The result will be stored on SciDB and a handle to that result will be returned to us in Julia. The handle will not itself contain the result data until we explicitly materialize it. This enables us to keep datasets on SciDB only.

    julia> C=A*B
    scidb_array("Julia_14736187500044874775_9",3x3 sparse matrix with 0 Float64 entries:,32,false)

Now, let's pull the result back from SciDB into Julia:

    julia> c=julia(C)
    3x3 sparse matrix with 9 Float64 entries:
    	[1, 1]  =  1.57822
    	[2, 1]  =  1.76727
    	[3, 1]  =  1.63517
    	[1, 2]  =  0.69131
    	[2, 2]  =  0.736123
    	[3, 2]  =  0.613984
    	[1, 3]  =  1.43423
    	[2, 3]  =  1.46001
    	[3, 3]  =  1.66386

Arrays created in SciDB from Julia are persistent and must be explicitly removed. This is done by the remove function:

    julia> remove(A)

    julia> remove(B)

    julia> remove(C)

###Example 2 - Multiplying Two Sparse Matrices, one from Julia, one from SciDB

    julia> a=sprand(3,4,0.40)
    3x4 sparse matrix with 3 Float64 entries:
    	[2, 1]  =  0.748581
    	[1, 2]  =  0.735042
    	[3, 4]  =  0.488018
    
    julia> A=scidb(a)
    scidb_array("Julia_2373004205611115214_12",3x4 sparse matrix with 3 Float64 entries:
    	[2, 1]  =  0.748581
    	[1, 2]  =  0.735042
    	[3, 4]  =  0.488018,32,true)
    
    julia> b=sprand(4,3,0.40)
    4x3 sparse matrix with 6 Float64 entries:
    	[3, 1]  =  0.577354
    	[1, 2]  =  0.610267
    	[4, 2]  =  0.586419
    	[1, 3]  =  0.760892
    	[2, 3]  =  0.499974
    	[3, 3]  =  0.385498
    
    julia> C=A*b
    scidb_array("Julia_13845036751259206723_9",3x3 sparse matrix with 0 Float64 entries:,32,true)
    
    julia> c=julia(C)
    3x3 sparse matrix with 4 Float64 entries:
    	[2, 2]  =  0.456835
    	[3, 2]  =  0.286183
    	[1, 3]  =  0.367502
    	[2, 3]  =  0.56959

##API

    function scidb(J::AbstractArray, chunkSize=32, densityOverride="none")
      # Create a SciDB array from a Julia array
      # TODO: Support for mxn matrices only at the moment (m,n>=1); same limitation as SciDB-R.
    
    function remove(J::scidb_array)
      # Remove the array from SciDB.
    
    function * (J::scidb_array, H::scidb_array)
    function * (J::scidb_array, H::AbstractArray)
    function * (J::AbstractArray, H::scidb_array)
      # GEMM and SPGEMM matrix mulitplication methods, supporting:
         scidb_array * scidb_array
         scidb_array * AbstractArray
         AbstractArray * scidb_array
    
    function julia(S::scidb_array)
      # Populate a Julia array from a SciDB array which was previously created by a SciDB query from Julia

##Limitations
    1. The plugin must be run on the same machine as the shim server and at port 8080.
    2. Only 2-dimensional matrices are supported.
    3. Load the dense_linear_algebra and linear_algebra libraries via iquery before running SciDBJulia.
