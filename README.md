# Howell Group Presentation Crawler

This is a program to fetch all of the presentation data from the Howell Collaboration Directory

## Running the Program

1. Create the `auth.toml` file
   
   This file is needed to perform authorization to access files. Create a file in this readme's directory called `auth.toml`. The file should contain the following:
   ```toml
   [authorization]
   username = "<USERNAME>"
   password = "<PASSWORD>"
   ```
   where `<USERNAME>` and `<PASSWORD>` should be replaced with your username and password.
1. Instantiate the Project:
   
   Open up a Julia repl in this README's directory and do:
   ```
   julia> using Pkg
   julia> Pkg.activate()
   julia> Pkg.instantiate()
   ```
1. Run the file
   
   ```
   julia --project hgpc.jl
   ```

## Output
The script outputs a `.csv` file containing all of  the files found and the following data:

- Name of the file
- Year, month, and day that the file was filed under
- Url of the file
- Content type (see [Advanced Configuration](#advanced-configuration))

## Advanced Configuration
The type of document is determined via the `content-type` header in the HTTP response; `config.toml` contains the mapping of `content-type` values to categories. Editing these will change how `hgpc.jl` will categorize documents.