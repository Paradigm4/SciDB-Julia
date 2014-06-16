#
# BEGIN_COPYRIGHT
#
# This file is part of SciDB.
# Copyright (C) 2008-2014 SciDB, Inc.
#
# SciDB is free software: you can redistribute it and/or modify
# it under the terms of the AFFERO GNU General Public License as published by
# the Free Software Foundation.
#
# SciDB is distributed "AS-IS" AND WITHOUT ANY WARRANTY OF ANY KIND,
# INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY,
# NON-INFRINGEMENT, OR FITNESS FOR A PARTICULAR PURPOSE. See
# the AFFERO GNU General Public License for the complete license terms.
#
# You should have received a copy of the AFFERO GNU General Public License
# along with SciDB.  If not, see <http://www.gnu.org/licenses/agpl-3.0.html>
#
# END_COPYRIGHT
#

module SciDBJulia

export scidb         # Convert Julia object to SciDB object
export remove        # GC function for SciDB cleanup
export scidb_array   # type for handle to SciDB array
export *             # GEMM and SPGEMM matrix mulitplication methods
export julia         # Populate a Julia array from a SciDB array which was
                     # previously created by a SciDB query from Julia
export julia_conversion_array

include("iquery.jl")

# Define the type representing SciDB arrays in Julia
type scidb_array   # Don't want to inherit from Julia types on purpose
    name::String              # The name of the array in SciDB
    julia_arr::AbstractArray  # A reference to the julia array
    chunkSize::Int            # The chunksize
    scidbsparse::Bool         # 'true' if the SciDB array is sparse, 'false' if not

    # "Constructor"
    function scidb_array(julia_arr::AbstractArray, chunkSize::Int, scidbsparse::Bool)
        return new("Julia_" * string(hash(time())) * "_" * string(length(julia_arr)), julia_arr, chunkSize, scidbsparse)
    end
end  # end scidb_array

# Some types, like Int (Int64) are consumed wholesale by SciDB.
# Others, like Float64, do not exist in SciDB and must be
# mapped into SciDB equivalents.
function eltype_lookup(eltype::DataType)
    if is(eltype,Float64)
        return "double"
    elseif is(eltype,Float32)
        return "double"
    end
    return string(eltype)
end  # end eltype_lookup

# Construct the query string for building a dense array on SciDB.
function dense_build_query(J::scidb_array)
    # Construct a query to send to the shim containing the SciDB array to build.
    scidb_query = "store(build(<attr:" * eltype_lookup(eltype(J.julia_arr)) * ">["
    total_dims = ndims(J.julia_arr)
    schema = ""

    # Julia arrays are 1-indexed, not 0-indexed like C arrays, but we need
    # to store 0-offset arrays because gemm requires 0-offset.  We will need
    # to correct for this when re-materializing arrays into Julia from SciDB.
    while total_dims > 1
        schema = (",i" * string(total_dims) * "=0:" *
                  string(size(J.julia_arr,total_dims)-1) * "," * string(J.chunkSize) * ",0" * schema)
        total_dims -= 1
    end
    if total_dims == 1
        schema = ("i" * string(total_dims) * "=0:" *
                  string(size(J.julia_arr,total_dims)-1) * "," * string(J.chunkSize) * ",0" * schema)
    end

    # We're going to leave all of the cells empty for now.  The file uploaded to
    # SciDB will be used by the load operator to populate the array with values.
    schema = schema * "],0)," * J.name * ")"
    scidb_query = scidb_query * schema
    return scidb_query
end  # end dense_build_query

# Construct the query string for building a sparse array on SciDB.
function sparse_build_query(J::scidb_array)
    # Construct a query to send to the shim containing the SciDB array to build.
    scidb_query = "create%20array%20" * J.name * "<attr:" * eltype_lookup(eltype(J.julia_arr)) * ">["
    total_dims = ndims(J.julia_arr)
    schema = ""

    # Julia arrays are 1-indexed, not 0-indexed like C arrays, but we need
    # to store 0-offset arrays because gemm requires 0-offset.  We will need
    # to correct for this when re-materializing arrays into Julia from SciDB.
    while total_dims > 1
        schema = (",i" * string(total_dims) * "=0:" *
                  string(size(J.julia_arr,total_dims)-1) * "," * string(J.chunkSize) * ",0" * schema)
        total_dims -= 1
    end
    if total_dims == 1
        schema = ("i" * string(total_dims) * "=0:" *
                  string(size(J.julia_arr,total_dims)-1) * "," * string(J.chunkSize) * ",0" * schema)
    end

    # We're going to leave all of the cells empty for now.  The file uploaded to
    # SciDB will be used by the load operator to populate the array with values.
    schema = schema * "]"
    scidb_query = scidb_query * schema
    return scidb_query
end  # end sparse_build_query

# Query the SciDB database and get the schema for a particular array.
function getSchema(scidb_name::String)
    schema = iquery("show(" * scidb_name * ")", true)
    schema = schema[9+length(scidb_name):end]  # 9 is schema\n'
    schema = schema[1:end-2]  # 2 is '\n
    return schema   # Result is like:  <attr:int64> [i1=0:1,32,0,i2=0:2,32,0]
end  # end getSchema

# Remove the array from SciDB.  This is called
# by the garbage collector when a Julia array
# is no longer needed but it may also be called
# explicitly by the user.
function remove(J::scidb_array)
    iquery("remove(" * J.name * ")")
    return
end  # end remove

# Create a SciDB formatted data file from a Julia array.  The
# file will live in /tmp.
function file_from_array(J::AbstractArray)
    data_file = mktemp()
    out_name = data_file[1]  # Get the filename from the tuple (ASCIIString,IOStream)
    out_fd = data_file[2]  # Get the stream from the tuple (ASCIIString,IOStream)
    J_trans = J'  # transpose the input to make writing the SciDB-formatted file simpler
    write(out_fd, "[")
    row_i = 0
    rows = size(J,1)
    col_i = 0
    cols = size(J_trans,1)  # The count of rows of J' is the count of cols in J
    for elem in J_trans  # Julia 'for' construct walks column-major order
        if col_i == 0
            write(out_fd, "[")
        end
        if elem == 0 && issparse(J)
            write(out_fd, "()")
        else
            write(out_fd, "(" * string(elem) * ")")
        end
        col_i = col_i + 1
        if col_i == cols
            col_i = 0
            row_i = row_i + 1
            if row_i == rows
                write(out_fd, "]")
            else
                write(out_fd, "],")
            end
        else
            write(out_fd, ",")
        end
    end
    write(out_fd, "]");
    close(out_fd)
    return out_name
end    

# Create a SciDB array from a Julia array
# DJG TODO: Support for mxn matrices only at the moment (m,n>=1); same limitation as SciDB-R.
function scidb(J::AbstractArray, chunkSize=32, densityOverride="none")
    # Julia has a notion of Arrays which are n-dimensional matrices.
    # Julia's reflection indicates the contained array type
    # and then the number of dimensions within the array:
    #   julia> typeof(zeros(Int,2,3,4,5,6,7,2))
    #   Array{Int64,7}
    # Construct a SciDB representation of a Julia array.
    if (densityOverride == "none" && isa(J, DenseArray)) ||
        densityOverride == "dense"
            # Send a query to SciDB to build the array with zeros
            sa = scidb_array(J, chunkSize, false)
            iquery(dense_build_query(sa))
    elseif (densityOverride == "none" && issparse(J)) ||
            densityOverride == "sparse"
            # Send a query to SciDB to build a sparse array with no entries
            sa = scidb_array(J, chunkSize, true)
            iquery(sparse_build_query(sa))
    else
        error("Density override " * densityOverride * " not supported")
    end

    # Create a SciDB-formatted temporary file containing
    # Julia array J and then upload the file to the coordinator.
    file_on_coord, sess_id = http_post_file(file_from_array(J))

    # Tell the coordinator to load the file, via the load operator,
    # into the array we created just above.
    load_query = "load(" * sa.name * ",'%2ftmp%2f" * basename(file_on_coord) * "')" # basename hack
    iquery_existing(load_query, sess_id, false)
    iquery_close_session(sess_id)

    # Attach a callback for garbage collection when the sa goes out of scope
    #finalizer(sa, remove)  # DJG TODO: fix crash that happens when GC cleans-up scidb_array objs
    return sa
end  # end scidb

# Call gemm on SciDB
function gemm(matr::scidb_array, matr2::scidb_array, matr3::scidb_array, output::scidb_array)
    # Build the gemm query to multiply matr and matr2 together
    gemm_query = "store(gemm(" * matr.name * "," * matr2.name * "," * matr3.name * ")," * output.name * ")"

    # Execute the query
    return iquery(gemm_query,true)
end  # end gemm

# Call spgemm on SciDB
function spgemm(matr::scidb_array, matr2::scidb_array, output::scidb_array)
    # Build the gemm query to multiply matr and matr2 together
    spgemm_query = "store(spgemm(" * matr.name * "," * matr2.name * ")," * output.name * ")"

    # Execute the query
    return iquery(spgemm_query,true)
end  # end gemm

# Define 2-dimensional matrix multiplication for scidb array types.
# DJG TODO: Extend to n-dimensional types using eval to build-up
# the argument tuple for 'Array' when constructing jdest.
function * (J::scidb_array, H::scidb_array)
    # Build a destination matrix with the number of rows from J and cols from H
    jdest = spzeros(size(J.julia_arr,1), size(H.julia_arr,2))

    if J.scidbsparse == false && H.scidbsparse == false
        # Keep all Julia results in sparse arrays locally, but create a dense
        # array on SciDB.
        mMxN = scidb(jdest, 32, "dense")
        
        # Build a zeros matrix with the number of rows from J and cols from H
        # Store this matrix on SciDB as component 'C' for gemm's multiply-and-add
        # A*B+C (jzeros is C)
        jzeros = zeros(size(J.julia_arr,1), size(H.julia_arr,2))
        mZeros = scidb(jzeros)

        # Execute gemm to multiply the two together
        gemm(J,H,mZeros,mMxN)

        # Remove the zeros array from SciDB
        remove(mZeros)
    else
        # Keep all Julia results in sparse arrays locally, and create a sparse
        # array on SciDB.
        mMxN = scidb(jdest, 32, "sparse")
        
        # Execute spgemm to multiply the two together
        spgemm(J,H,mMxN)
    end

    # Return handle for result to the caller
    return mMxN
end  # end method for function *

# Define matrix multiplication for mixed scidb/Julia array types
function * (J::scidb_array, H::AbstractArray)
    return J * scidb(H)  # GC should cleanup transient SciDB array created here
end  # end method for function *

# Define matrix multiplication for mixed scidb/Julia array types
function * (J::AbstractArray, H::scidb_array)
    return scidb(J) * H  # GC should cleanup transient SciDB array created here
end  # end method for function *

# The dimensions in SciDB are 0-indexed whereas Julia dimensions are 1-indexed.
# This function takes the dimensions passed as a list "1,2,3" and returns them
# incremented by one e.g., "2,3,4".
function correct_dimensions(A::ASCIIString)
    return string(broadcast(+, [1], eval(parse("[" * A * "]"))))[2:end-1]
end  # end correct_dimensions

julia_scidb_conv_arry = nothing  # HACK HACK HACK because eval doesn't have function scope

# Read the contents of a SciDB array into a Julia array
# of the same dimensions
function julia(S::scidb_array)
    global julia_scidb_conv_arry  # HACK HACK HACK because eval doesn't have function scope
    
    # The scidb_array object S contains a Julia array whose
    # dimensions match the SciDB array named by S.name.  There's
    # no need to parse the SciDB schema to construct the Julia
    # object.
    # Issue query 'unpack(array)' on SciDB because the Shim returns
    # only attributes, not dimensions.  Unpacking allows the
    # attributes to carry the dimension information.
    # Do not store the results of the unpack on SciDB because
    # that achieves nothing in terms-of acquiring the data
    # into Julia.  Read the results into a string for further processing.
    mat_query = "unpack(" * S.name * ",__row" * ")"
    A = iquery(mat_query, true)

    # The first line in the stringified array will be the dimension
    # names followed by the attribute name on SciDB.  We know how
    # many dimensions are in the array based-on S.julia_arr.
    # Populate S.julia_arr by walking the stringified SciDB array
    # and copying values to their corresponding place in the Julia array.
    # Convert the stringified array into a list of tuples, where
    # each tuple is a row from the SciDB array.  This allows the Julia
    # 'for' operator to give us the next tuple on each iteration.
    # Skip the header
    index = 1
    length_A = length(A)
    while A[index] != '\n' && index < length_A
        index = index + 1
    end
    index = index + 1  # go one past '\n'

    # Walk the rest
    dim_start = index
    dim_count = 0
    julia_scidb_conv_arry = S.julia_arr
    expression = "julia_scidb_conv_arry["
    while index < length(A)
        if A[index] == ','
            dim_count = dim_count + 1
        end
        if dim_count == ndims(S.julia_arr)
            # The dimensions in SciDB are 0-indexed whereas Julia dimensions are 1-indexed.
            expression = expression * correct_dimensions(A[dim_start:index-1]) * "]="
            index = index + 1
            value_start = index
            while index <= length(A)
                if A[index] == '\n'
                    expression = expression * A[value_start:index-1]
                    eval(parse(expression))
                    break
                else
                    index = index + 1
                end
            end
            dim_start = index+1
            dim_count = 0
            expression = "julia_scidb_conv_arry["
        end
        index = index + 1
    end
    S.julia_arr = julia_scidb_conv_arry
    return S.julia_arr
end

end  # end module
