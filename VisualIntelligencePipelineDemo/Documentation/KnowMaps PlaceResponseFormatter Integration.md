# KnowMaps: Use Revised `PlaceResponseFormatter` in `DefaultModelController` + `DefaultPlaceSearchService`

This repo’s Codex sandbox can’t directly edit `../Know-Maps`, so copy/paste the following changes into the KnowMaps project.

## 1) `DefaultModelController.swift`

File: `Know-Maps/Know-Maps/Know-Maps/Know Maps Prod/Model/Controllers/DefaultModelController.swift`

### A) Fix formatter call-site label (`with:` -> `from:`)

Replace:

```swift
let recs = try PlaceResponseFormatter.autocompleteRecommendedPlaceSearchResponses(
    with: payloadData
)
```

With:

```swift
let recs = try PlaceResponseFormatter.autocompleteRecommendedPlaceSearchResponses(from: payloadData)
```

### B) Stop calling nonexistent `placeSearchResponses(with: recs)` overload

Replace:

```swift
let recAsPlaces = PlaceResponseFormatter.placeSearchResponses(with: recs)

if !recAsPlaces.isEmpty {
    finalPlaceResponses = recAsPlaces
}
```

With:

```swift
let recAsPlaces: [PlaceSearchResponse] = recs.map { rec in
    PlaceSearchResponse(
        fsqID: rec.fsqID,
        name: rec.name,
        categories: rec.categories,
        latitude: rec.latitude,
        longitude: rec.longitude,
        address: rec.address,
        addressExtended: "",
        country: rec.country,
        dma: "",
        formattedAddress: rec.formattedAddress,
        locality: rec.city,
        postCode: rec.postCode,
        region: rec.state,
        chains: [],
        link: "",
        childIDs: [],
        parentIDs: []
    )
}

if !recAsPlaces.isEmpty {
    finalPlaceResponses = recAsPlaces
}
```

This ensures recommended places always have a non-empty `name` when converted to `PlaceSearchResponse` (and prevents the “empty title” cascade into caches).

## 2) `DefaultPlaceSearchService.swift`

File: `Know-Maps/Know-Maps/Know-Maps/Know Maps Prod/Model/Controllers/DefaultPlaceSearchService.swift`

### Always request core fields during details fetch

Replace:

```swift
let request = PlaceDetailsRequest(
    fsqID: response.fsqID,
    core: response.name.isEmpty,
    description: true,
    tel: true,
    fax: false,
    email: false,
    website: true,
    socialMedia: true,
    verified: false,
    hours: true,
    hoursPopular: true,
    rating: true,
    stats: false,
    popularity: true,
    price: true,
    menu: true,
    tastes: true,
    features: false
)
```

With:

```swift
let request = PlaceDetailsRequest(
    fsqID: response.fsqID,
    core: true,
    description: true,
    tel: true,
    fax: false,
    email: false,
    website: true,
    socialMedia: true,
    verified: false,
    hours: true,
    hoursPopular: true,
    rating: true,
    stats: false,
    popularity: true,
    price: true,
    menu: true,
    tastes: true,
    features: false
)
```

Rationale: `PlaceResponseFormatter.placeDetailsResponse(with: FSQPlace, for: PlaceSearchResponse, ...)` can only enrich/repair the `PlaceSearchResponse` (and build a complete `PlaceDetailsResponse`) if the details payload includes `name`, `location`, `geocodes`, etc. Those are only included when `core == true`.

