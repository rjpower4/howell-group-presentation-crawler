using Cascadia    # HTML Querying
using Gumbo       # HTML Parsing
using HTTP        # HTTP Requests
using Base64      # Auth Encoding
using DataFrames  # DataFrames... 
using TOML        # Config Parsing
using URIs
using URIs: URI   # URL handling
using Transducers # Making my head hurt
using CSV

###
### Constants
###
const AUTH_FILE_NAME   = "auth.toml"
const AUTH_FILE_PATH   = joinpath(@__DIR__, AUTH_FILE_NAME)
const CONFIG_FILE_NAME = "config.toml"
const CONFIG_FILE_PATH = joinpath(@__DIR__, CONFIG_FILE_NAME)

###
### Authentication
###
"""
    AuthInfo

Struct containing information required to authenticate for HTTP request
"""
struct AuthInfo
    username::String
    password::String
end

"""Generate the http authorization header pair"""
function http_auth(ai::AuthInfo)
    code = Base64.base64encode("$(ai.username):$(ai.password)")
    return "Authorization" => "Basic $code"
end

###
### Configuration
###
struct ConfigurationContext
    root_url::URI  # Root url to start crawling from
    auth::AuthInfo # Authentication information
    known_content_types::Dict{String, Symbol} # Known content-types to symbols mappings
end

function ConfigurationContext(cpath, apath)
    if ~isfile(cpath)
        error("File at $cpath does not exist!")
    elseif ~isfile(apath)
        error("File at $apath does not exist!")
    end
    parsed_conf = TOML.parsefile(cpath)
    parsed_auth = TOML.parsefile(apath)
    auth = AuthInfo(
        parsed_auth["authorization"]["username"],
        parsed_auth["authorization"]["password"],
    )
    root_url = URI(parsed_conf["urlroot"])
    ctypes = Dict{String, Symbol}()
    ctypes_config::Dict{String, Vector{String}} = parsed_conf["content_types"]
    for (type, ctypelist) in ctypes_config
        sym = Symbol(type)
        foreach(ctypelist) do f
            ctypes[f] = sym
        end
    end
    ConfigurationContext(root_url, auth, ctypes)
end
root(cc::ConfigurationContext) = cc.root_url
http_auth(cc::ConfigurationContext) =  http_auth(cc.auth)

"""
    get_content_group(::ConfigurationContext, name::String, ctype::String)

Determine what "type" of file is pointed at with name `name` and content-type `ctype`.
"""
function get_content_group(cc::ConfigurationContext, name::String, ctype::String)
    if haskey(cc.known_content_types, ctype)
        cc.known_content_types[ctype]
    elseif endswith(name, r"ppt|pptx")
        :powerpoint
    elseif endswith(name, "jpg")
        :image
    elseif endswith(name, r"fig")
        :matlab_figure
    elseif endswith(name, r"mov|mp4|ogv")
        :video
    elseif endswith(name, "pdf")
        :pdf
    elseif endswith(name, ".mat")
        :matfile
    elseif endswith(name, "exe")
        :executable
    elseif contains(name, "Diane")
        :powerpoint
    else
        :unknown
    end
end

###
### Request Helpers
###
"""
    request(::ConfigurationContext, method, url)

Simple wrapper around [`HTTP.request`](@ref) that passes auth header from config context.
"""
function request(cc::ConfigurationContext, method, url)
    auth_header = http_auth(cc)
    return HTTP.request(method, url, headers=[auth_header, ])
end
request(cc::ConfigurationContext) = (method, url) -> request(cc, method, url)
request(cc::ConfigurationContext, method) = (url) -> request(cc, method, url)

"""
    content_type(r)

Return the content type of a response
"""
function content_type(r::HTTP.Messages.Response)
    headers = r.headers
    types = map(first, headers)
    ind::Int64 = if "Content-Type" in types
        findfirst(==("Content-Type"), types)
    else
        0
    end
    return ind == 0 ? "Unkown" : String(last(headers[ind]))
end

function links_on_page(cc::ConfigurationContext, url::URI)
    parsed_html = request(cc, "GET", url) |> String |> parsehtml
    all_links = eachmatch(sel"li, a", parsed_html.root)
    a(x) = haskey(x.attributes, "href")
    b(x) = x.attributes["href"]
    c(x) = startswith(x, url.uri)
    d(x) = URI(x)
    return all_links |> Filter(a) |> Map(b) |> Filter(c) |> Map(d) |> collect
end
links_on_page(cc) = url -> links_on_page(cc, url)

is_subpage_link(cc, url) = (request(cc, "HEAD", url) |> content_type) == "text/html"
is_subpage_link(cc) = url -> is_subpage_link(cc, url)

###
### Main Process
###

# Setting Up Configuration
cc = ConfigurationContext(CONFIG_FILE_PATH, AUTH_FILE_PATH)

# Getting the file URLs
year_links = links_on_page(cc, root(cc))
potential_month_links = year_links |> MapCat(links_on_page(cc)) |> collect
mlinks = map(is_subpage_link(cc), potential_month_links)
month_links = potential_month_links[mlinks]
files = potential_month_links[.!mlinks]
potential_day_links = month_links |> MapCat(links_on_page(cc)) |> collect
dlinks = map(is_subpage_link(cc), potential_day_links)
day_links = potential_day_links[dlinks]
append!(files, potential_day_links[.!dlinks])
potential_file_links = day_links |> MapCat(links_on_page(cc)) |> collect
flinks = .!map(is_subpage_link(cc), potential_file_links)
append!(files, potential_file_links[flinks])

# Determining types of files
content_types = files |> Map(request(cc, "HEAD")) |> Map(content_type) |> collect
uri_strings = map(string, files)
content_groups = map(zip(uri_strings, content_types)) do (us, ct)
    name = URIs.splitpath(us)[end]
    get_content_group(cc, name, ct)
end
names = map(x -> URIs.splitpath(x)[end], uri_strings)
dates = map(uri_strings) do u
    matches = match(r"(?<year>\d{4})[-_](?<month>\d+)[-_](?<day>\d+)", u)
    out = if isnothing(matches)
        yrmatch = match(r"(?<year>\d{4})/", u)
        mnmatch = match(r"[/_](?<month>\d{1,2})[/.]", u)
        (
            year = parse(Int64, yrmatch["year"]),
            month =  parse(Int64, mnmatch["month"]),
            day = 0,
        )
    else
        (
            year = parse(Int64, matches["year"]),
            month = parse(Int64, matches["month"]),
            day = parse(Int64, matches["day"]),
        )
    end
    if out.year == 2001
        out = (year=2007, month=out.month, day=out.day)
    end
    return out
end

# Build the DataFrame
output_dataframe = DataFrame(
    name = names,
    year = map(x -> getindex(x, 1), dates),
    month = map(x -> getindex(x, 2), dates),
    day = map(x -> getindex(x, 3), dates),
    url = uri_strings,
    content_group = content_groups
)

# Determine winner
gdf = groupby(output_dataframe, :year)
combine(gdf, nrow)
CSV.write("output.csv", output_dataframe)