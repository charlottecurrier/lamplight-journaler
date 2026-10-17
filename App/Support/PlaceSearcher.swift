import Foundation
import MapKit

/// Suggests places as you type, using Apple Maps. Only the text you type is sent, nothing else from your journal.
@MainActor
final class PlaceSearcher: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }

    /// Looks up the coordinates for a suggestion. If that fails, the place is still usable by name.
    func resolve(_ suggestion: MKLocalSearchCompletion) async -> EntryLocation {
        let name = suggestion.title
        let request = MKLocalSearch.Request(completion: suggestion)
        if let response = try? await MKLocalSearch(request: request).start(),
           let coordinate = response.mapItems.first?.placemark.coordinate {
            return EntryLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return EntryLocation(name: name)
    }
}
