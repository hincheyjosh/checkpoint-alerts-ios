import SwiftUI

private let detailDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "EEEE, MMMM d, yyyy"
    return f
}()

struct DetailView: View {

    var checkpoint: Checkpoint

    var body: some View {
        List {
            Section {
                Text(detailDateFormatter.string(from: checkpoint.date))
                    .font(.title2)
                HStack(spacing: 8) {
                    TypeBadge(type: checkpoint.type)
                    Text("\(checkpoint.county) County, Tennessee")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(checkpoint.location)
                        .font(.body)
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                    Text("\(checkpoint.county) County, Tennessee")
                }
                if !checkpoint.sourceUrl.isEmpty, let url = URL(string: checkpoint.sourceUrl) {
                    Link("View announcement", destination: url)
                        .buttonStyle(.bordered)
                }
                Text("Announcements can change. Only publicly announced checkpoints are shown here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                MadeWithLoveFooter()
            }
        }
        .navigationTitle("Checkpoint details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
