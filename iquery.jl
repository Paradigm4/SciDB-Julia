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

using Requests

export iquery

# Use HTTP POST to upload a SciDB data file to the coordinator.
# Optionally remove the uploaded file from the client once posted.
function http_post_file(q::String, remove_temp=true)
    #println("filename: " * q)  # DJG
    session_id = int(Requests.get("http://localhost:8080/new_session").data)
    query_string = "http://localhost:8080/upload_file?id=" * string(session_id)
    coord_fname = Requests.post(query_string; files =
                                [Requests.FileParam(open(q, "r"), "application/octet-stream", q, q)]).data
    if remove_temp == true
        # Clear the file posted from the client machine.
        # We don't need to worry about clearing the file uploaded
        # to the coordinator because the shim will remove that file
        # when the session is released.
        rm(q)
    end
    return (coord_fname[1:end-2],session_id)  # Trim the '\r\n' from the output
end  # end http_post_file

# Interfaces with the 'Requests' API to send SciDB queries to the Shim over the REST interface
# utilizing a session_id which has already been created. 
function iquery_existing(q::String, session_id::Int, getres=false)
    #println("AFL% " * q)  # DJG
    query_string = "http://localhost:8080/execute_query?id=" * string(session_id) * "&query=" * q
    if getres
        query_string = query_string * "&save=csv"
    end
    Requests.get(query_string)
    results = Requests.post("http://localhost:8080/read_lines?id=" * string(session_id) * "&n=0")
    Requests.get("http://localhost:8080/release_session?id=" * string(session_id))
    if getres
        return results.data
    end
    return 
end  # end iquery_existing

# Closes an existing iquery session.
function iquery_close_session(session_id::Int)
    Requests.get("http://localhost:8080/release_session?id=" * string(session_id))
end  # end iquery_close_session
   
# Interfaces with the 'Requests' API to send SciDB queries to the Shim over the REST interface.
# This function creates the session, executes the query, and cleans-up the session; no need to
# call iquery_close_session explicitly when using this function.
function iquery(q::String, getres=false)
    #println("AFL% " * q)  # DJG
    session_id = int(Requests.get("http://localhost:8080/new_session").data)
    query_string = "http://localhost:8080/execute_query?id=" * string(session_id) * "&query=" * q
    if getres == true
        query_string = query_string * "&save=csv"
    end
    #println("  GET  " * query_string)
    Requests.get(query_string)
    results = Requests.post("http://localhost:8080/read_lines?id=" * string(session_id) * "&n=0")
    Requests.get("http://localhost:8080/release_session?id=" * string(session_id))
    if getres == true
        return results.data
    end
    return
end  # end iquery

