import MapKit
import SwiftUI

/// Phone/website/address for an `MKMapItem`, as icon-prefixed rows in a
/// card — shared by `POIExplainSheet` and `MapScreen`'s inline map-feature
/// card so the two don't drift in how this looks. Previously plain,
/// unstyled `Link`/`Text` lines stacked directly on the page background
/// with nothing to visually group them (confirmed live: read as bare,
/// out of place next to everything else on the card, which is all
/// icon-led or card-backed).
struct PlaceDetailsCard: View {
    let mapItem: MKMapItem

    @ViewBuilder
    var body: some View {
        let phoneNumber = mapItem.phoneNumber
        let website = mapItem.url
        let address = mapItem.placemark.title

        if phoneNumber != nil || website != nil || address != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let phoneNumber, let telURL = URL(string: "tel:\(phoneNumber.filter { !$0.isWhitespace })") {
                    row(icon: "phone.fill") {
                        Link(phoneNumber, destination: telURL)
                    }
                }
                if let website {
                    row(icon: "globe") {
                        Link(website.host ?? website.absoluteString, destination: website)
                    }
                }
                if let address {
                    row(icon: "mappin.and.ellipse") {
                        Text(address).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.footnote)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }

    private func row(icon: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.gold)
                .frame(width: 18)
            content()
        }
    }
}
