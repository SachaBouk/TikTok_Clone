// La couche data/ de l'app utilise aussi le runtime (ClientMiddleware, HTTPBody), le transport URLSession
// et les types HTTP : ils sont réexportés, pour n'avoir qu'une source de versions (Package.swift).
@_exported import HTTPTypes
@_exported import OpenAPIRuntime
@_exported import OpenAPIURLSession
